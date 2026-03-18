// Package server 实现 DistTree gRPC 服务端。
// 每次 PutStream 调用对应一个文件的完整传输（一轮）。
// 服务端同时扮演两个角色：
//   - 叶子节点：将接收到的数据写入本地临时文件，收完后 Rename 到目标路径；
//   - 中间节点：按 width 将下游节点列表拆分，对每组建立到网关节点的 PutStream 流并转发。
package server

import (
	"context"
	"crypto/md5"
	"fmt"
	"io"
	"log"
	"net"
	"os"
	"sync"

	pb "trans-tools/internal/distree/proto"
	"trans-tools/internal/distree/nodeutil"

	"google.golang.org/grpc"
)

// Config 是 Agent 启动时传入的服务端配置。
type Config struct {
	// TmpDir 是临时文件目录；若为空则使用系统默认。
	TmpDir string
	// DestOverride 若非空，则忽略客户端请求中的 dest_dir，统一将文件落盘到此目录。
	// 生产场景中每台计算节点可以有自己的本地存储路径，无需依赖 client 的配置。
	DestOverride string
	// Insecure 为 true 时不加载 TLS（测试用）。
	Insecure bool
}

// distTreeServer 实现 pb.DistTreeServer 接口。
type distTreeServer struct {
	pb.UnimplementedDistTreeServer
	cfg Config
}

// PutStream 是核心 RPC 实现。
func (s *distTreeServer) PutStream(stream pb.DistTree_PutStreamServer) error {
	ctx := stream.Context()

	// replies 汇总本节点与所有下游的结果，最终统一发回上游。
	replies := make(chan *pb.PutStreamReply, 64)

	var (
		writer      *localWriter
		downstreams []*downstreamConn
		failReplies []*pb.PutStreamReply
		once        sync.Once
		setupErr    error
	)

	hostname, _ := os.Hostname()
	localNode := hostname

	for {
		req, err := stream.Recv()
		switch err {
		case nil:
			// 首条消息：建立本地写盘与下游流
			once.Do(func() {
				writer, setupErr = s.initLocalWriter(req)
				if setupErr != nil {
					return
				}
				downstreams, failReplies = s.initDownstreams(ctx, req)
			})
			if setupErr != nil {
				return fmt.Errorf("setup failed: %w", setupErr)
			}

			// 校验块 md5（非空时才校验）
			if req.Md5 != "" {
				if got := blockMD5(req.Body); got != req.Md5 {
					writer.abort()
					for _, d := range downstreams {
						_ = d.stream.CloseSend()
						d.conn.Close()
					}
					return fmt.Errorf("md5 mismatch on block")
				}
			}

			// 本地写盘
			if werr := writer.write(req.Body); werr != nil {
				log.Printf("[distree server] local write error: %v", werr)
			}

			// 转发到所有下游：nodelist 为本组内网关之后的节点（保留 host:port 格式）
			for _, d := range downstreams {
				downReq := &pb.PutStreamReq{
					Name:       req.Name,
					Md5:        req.Md5,
					DestDir:    req.DestDir,
					Body:       req.Body,
					Nodelist:   nodeutil.Join(d.addrs[1:]),
					Port:       req.Port,
					Width:      req.Width,
					Uid:        req.Uid,
					Gid:        req.Gid,
					Filemod:    req.Filemod,
					Modtime:    req.Modtime,
					SourceNode: localNode,
				}
				if sendErr := d.send(downReq); sendErr != nil {
					log.Printf("[distree server] send to %s error: %v", d.gateway.Host, sendErr)
					replies <- &pb.PutStreamReply{
						Ok:       false,
						Nodelist: nodeutil.Join(d.addrs),
						Message:  sendErr.Error(),
					}
				}
			}

		case io.EOF:
			// 上游发送完毕：提交本地文件，等待所有下游结果
			if writer == nil {
				close(replies)
				return nil
			}

			// 先把建连失败的节点回复预入通道
			for _, fr := range failReplies {
				replies <- fr
			}

			// 并发等待本地提交和所有下游结果，全部完成后关闭 replies。
			var wg sync.WaitGroup

			// 本地提交 goroutine
			wg.Add(1)
			go func() {
				defer wg.Done()
				if cerr := writer.commit(); cerr != nil {
					replies <- &pb.PutStreamReply{
						Ok:       false,
						Nodelist: localNode,
						Message:  fmt.Sprintf("local commit: %v", cerr),
					}
				} else {
					replies <- &pb.PutStreamReply{
						Ok:       true,
						Nodelist: localNode,
						Message:  "success",
					}
				}
			}()

			// 下游接收 goroutines
			for _, d := range downstreams {
				d := d
				wg.Add(1)
				go func() {
					defer wg.Done()
					d.closeAndRecv(replies)
				}()
			}

			// 全部完成后关闭通道
			go func() {
				wg.Wait()
				close(replies)
			}()

			// 将所有回复发给上游（阻塞直到 replies 关闭）
			for r := range replies {
				if sendErr := stream.Send(r); sendErr != nil {
					log.Printf("[distree server] send reply error: %v", sendErr)
				}
			}
			return nil

		default:
			if writer != nil {
				writer.abort()
			}
			for _, d := range downstreams {
				_ = d.stream.CloseSend()
				d.conn.Close()
			}
			return fmt.Errorf("recv error: %w", err)
		}
	}
}

func (s *distTreeServer) initLocalWriter(req *pb.PutStreamReq) (*localWriter, error) {
	tmpDir := s.cfg.TmpDir
	if tmpDir == "" {
		tmpDir = os.TempDir()
	}
	destDir := req.DestDir
	if s.cfg.DestOverride != "" {
		destDir = s.cfg.DestOverride
	}
	return newLocalWriter(tmpDir, destDir, req.Name, req.Uid, req.Gid, req.Filemod, req.Modtime)
}

// initDownstreams 按 width 拆分下游节点，逐组建立连接。
// 返回成功建连的下游列表和连接失败节点的 Reply 列表。
func (s *distTreeServer) initDownstreams(ctx context.Context, req *pb.PutStreamReq) ([]*downstreamConn, []*pb.PutStreamReply) {
	if req.Nodelist == "" || req.Width <= 0 {
		return nil, nil
	}
	// Expand 支持 "cn1:port,cn2:port" 和 nodeset 表达式两种格式
	addrs := nodeutil.Expand(req.Nodelist)
	groups := nodeutil.SplitByWidth(addrs, int(req.Width))

	var downstreams []*downstreamConn
	var failReplies []*pb.PutStreamReply
	for _, group := range groups {
		if len(group) == 0 {
			continue
		}
		d, err := newDownstreamConn(ctx, group, req.Port, s.cfg.Insecure)
		if err != nil {
			log.Printf("[distree server] connect to %s failed: %v", group[0].Host, err)
			failReplies = append(failReplies, &pb.PutStreamReply{
				Ok:       false,
				Nodelist: nodeutil.Join(group),
				Message:  err.Error(),
			})
			continue
		}
		downstreams = append(downstreams, d)
	}
	return downstreams, failReplies
}

func blockMD5(b []byte) string {
	return fmt.Sprintf("%x", md5.Sum(b))
}

// Serve 启动 gRPC 服务并阻塞，直到 ctx 取消。
func Serve(ctx context.Context, cfg Config, port int) error {
	lis, err := net.Listen("tcp", fmt.Sprintf(":%d", port))
	if err != nil {
		return fmt.Errorf("listen :%d: %w", port, err)
	}

	grpcSrv := grpc.NewServer()
	pb.RegisterDistTreeServer(grpcSrv, &distTreeServer{cfg: cfg})

	errCh := make(chan error, 1)
	go func() {
		log.Printf("[distree server] listening on :%d (insecure=%v)", port, cfg.Insecure)
		errCh <- grpcSrv.Serve(lis)
	}()

	select {
	case <-ctx.Done():
		grpcSrv.GracefulStop()
		return nil
	case e := <-errCh:
		return e
	}
}
