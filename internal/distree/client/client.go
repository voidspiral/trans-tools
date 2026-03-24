// Package client 实现 DistTree 客户端，供 trans-tools deps 调用。
// 容错策略：client 按 width 将节点分组，每组独立建连。
// 若某组的 gateway 不可达，只标记该节点失败，剩余节点提升为新组继续。
// 每组独立传输（每组都从本地读一遍文件），互不影响。
package client

import (
	"context"
	"crypto/md5"
	"fmt"
	"io"
	"log"
	"math"
	"os"
	"sync"
	"syscall"
	"time"

	pb "trans-tools/internal/distree/proto"
	"trans-tools/internal/distree/nodeutil"

	"google.golang.org/grpc"
	"google.golang.org/grpc/credentials/insecure"
)

// Reply 是单个节点或批次的传输结果。
type Reply struct {
	OK       bool
	Nodelist string
	Message  string
}

// Options 控制单次 PutStreamFile 行为。
type Options struct {
	Port       string
	Width      int32
	BufferSize int
	Insecure   bool
	DestDir    string
}

type fileMeta struct {
	filename string
	size     int64
	uid, gid uint32
	filemod  uint32
	modtime  int64
}

// PutStreamFile 将 localFile 通过树形分发传输到 nodesExpr 描述的节点集合。
// 按 width 将节点分成若干组，每组独立建流发送。单组内 gateway 失败时只报告
// 该节点，剩余节点提升为新组继续尝试，保证其他健康节点不受影响。
func PutStreamFile(ctx context.Context, localFile, nodesExpr string, opts Options) ([]Reply, error) {
	fi, err := os.Stat(localFile)
	if err != nil {
		return nil, fmt.Errorf("stat %s: %w", localFile, err)
	}

	var uid, gid uint32
	if sys, ok := fi.Sys().(*syscall.Stat_t); ok {
		uid = sys.Uid
		gid = sys.Gid
	}
	meta := fileMeta{
		filename: fi.Name(),
		size:     fi.Size(),
		uid:      uid,
		gid:      gid,
		filemod:  uint32(fi.Mode().Perm()),
		modtime:  fi.ModTime().Unix(),
	}

	addrs := nodeutil.Expand(nodesExpr)
	if len(addrs) == 0 {
		return nil, fmt.Errorf("empty node list: %q", nodesExpr)
	}

	width := int(opts.Width)
	if width <= 0 {
		width = 1
	}
	groups := nodeutil.SplitByWidth(addrs, width)

	var allReplies []Reply
	var mu sync.Mutex
	var wg sync.WaitGroup

	for _, group := range groups {
		group := group
		wg.Add(1)
		go func() {
			defer wg.Done()
			replies := sendToGroup(ctx, localFile, meta, group, opts)
			mu.Lock()
			allReplies = append(allReplies, replies...)
			mu.Unlock()
		}()
	}
	wg.Wait()

	totalBlocks := int64(math.Ceil(float64(meta.size) / float64(resolveBufferSize(opts.BufferSize))))
	fmt.Printf("\r  发送进度: %d/%d\n", totalBlocks, totalBlocks)

	return allReplies, nil
}

// sendToGroup 尝试连接 group[0] 作为 gateway，成功则流式发送文件并将 group[1:]
// 作为 nodelist 下传。若 gateway 连接失败，记录该节点失败，然后将 group[1:] 递归
// 重新分组继续尝试，直到找到可用 gateway 或整组耗尽。
func sendToGroup(ctx context.Context, localFile string, meta fileMeta, group []nodeutil.NodeAddr, opts Options) []Reply {
	remaining := group
	var failReplies []Reply

	for len(remaining) > 0 {
		gateway := remaining[0]
		rest := remaining[1:]

		port := nodeutil.ResolvePort(gateway, opts.Port)
		addr := fmt.Sprintf("%s:%s", gateway.Host, port)

		replies, err := streamToNode(ctx, localFile, meta, addr, rest, opts)
		if err != nil {
			log.Printf("[distree client] connect to %s failed: %v", addr, err)
			failReplies = append(failReplies, Reply{
				OK:       false,
				Nodelist: gateway.Host,
				Message:  err.Error(),
			})
			remaining = rest
			continue
		}
		return append(failReplies, replies...)
	}
	return failReplies
}

// streamToNode 建连 → 流式发送文件 → 收集所有 Reply。
func streamToNode(ctx context.Context, localFile string, meta fileMeta, addr string, downstream []nodeutil.NodeAddr, opts Options) ([]Reply, error) {
	dialCtx, dialCancel := context.WithTimeout(ctx, 5*time.Second)
	defer dialCancel()

	dialOpts := []grpc.DialOption{grpc.WithBlock()}
	if opts.Insecure {
		dialOpts = append(dialOpts, grpc.WithTransportCredentials(insecure.NewCredentials()))
	}

	conn, err := grpc.DialContext(dialCtx, addr, dialOpts...)
	if err != nil {
		return nil, fmt.Errorf("dial %s: %w", addr, err)
	}
	defer conn.Close()

	cli := pb.NewDistTreeClient(conn)
	stream, err := cli.PutStream(ctx)
	if err != nil {
		return nil, fmt.Errorf("open PutStream to %s: %w", addr, err)
	}

	f, err := os.Open(localFile)
	if err != nil {
		return nil, fmt.Errorf("open %s: %w", localFile, err)
	}
	defer f.Close()

	bufSize := resolveBufferSize(opts.BufferSize)
	buf := make([]byte, bufSize)
	isFirst := true

	for {
		select {
		case <-ctx.Done():
			return nil, ctx.Err()
		default:
		}

		n, rerr := f.Read(buf)
		if rerr != nil && rerr != io.EOF {
			return nil, fmt.Errorf("read %s: %w", localFile, rerr)
		}
		if n == 0 {
			break
		}

		chunk := buf[:n]
		sum := fmt.Sprintf("%x", md5.Sum(chunk))

		req := &pb.PutStreamReq{
			Md5:     sum,
			DestDir: opts.DestDir,
			Body:    chunk,
		}
		if isFirst {
			req.Name = meta.filename
			req.Nodelist = nodeutil.Join(downstream)
			req.Port = opts.Port
			req.Width = opts.Width
			req.Uid = meta.uid
			req.Gid = meta.gid
			req.Filemod = meta.filemod
			req.Modtime = meta.modtime
			isFirst = false
		}

		if serr := stream.Send(req); serr != nil {
			return nil, fmt.Errorf("send to %s: %w", addr, serr)
		}

		if rerr == io.EOF {
			break
		}
	}

	if err = stream.CloseSend(); err != nil {
		return nil, fmt.Errorf("CloseSend: %w", err)
	}

	var replies []Reply
	for {
		r, rerr := stream.Recv()
		if rerr == io.EOF {
			break
		}
		if rerr != nil {
			log.Printf("[distree client] recv reply error: %v", rerr)
			break
		}
		replies = append(replies, Reply{
			OK:       r.Ok,
			Nodelist: r.Nodelist,
			Message:  r.Message,
		})
	}
	return replies, nil
}

func resolveBufferSize(size int) int {
	if size <= 0 {
		return 2 * 1024 * 1024
	}
	return size
}

// ConvertBufferSize 将 "2M"/"512k" 等字符串转换为字节数。
func ConvertBufferSize(s string) (int, error) {
	if s == "" {
		return 2 * 1024 * 1024, nil
	}
	var num int
	var unit string
	_, err := fmt.Sscanf(s, "%d%s", &num, &unit)
	if err != nil {
		_, err = fmt.Sscanf(s, "%d", &num)
		if err != nil {
			return 0, fmt.Errorf("invalid buffer size %q", s)
		}
		return num, nil
	}
	switch unit {
	case "k", "K", "kb", "KB":
		return num * 1024, nil
	case "m", "M", "mb", "MB":
		return num * 1024 * 1024, nil
	default:
		return 0, fmt.Errorf("unknown unit %q in buffer size %q", unit, s)
	}
}
