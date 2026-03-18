package server

import (
	"context"
	"fmt"
	"io"
	"sync"
	"sync/atomic"
	"time"

	pb "trans-tools/internal/distree/proto"
	"trans-tools/internal/distree/nodeutil"

	"google.golang.org/grpc"
	"google.golang.org/grpc/credentials/insecure"
)

// downstreamConn 封装对下一跳节点的 gRPC 双流连接。
// 服务端对每组节点（SplitByWidth 后的每组）建一个 downstreamConn。
type downstreamConn struct {
	conn    *grpc.ClientConn
	stream  pb.DistTree_PutStreamClient
	addrs   []nodeutil.NodeAddr // 本组全部节点（含网关）
	gateway nodeutil.NodeAddr   // 网关节点（addrs[0]）
	bad     atomic.Bool
	mu      sync.Mutex
}

// newDownstreamConn 拨号到 gateway 节点并建立 PutStream 双流。
// group 是本组节点列表，网关是 group[0]。
// defaultPort 是协议中携带的端口；若节点自身携带端口（host:port 格式）则优先使用。
func newDownstreamConn(ctx context.Context, group []nodeutil.NodeAddr, defaultPort string, insecureMode bool) (*downstreamConn, error) {
	if len(group) == 0 {
		return nil, fmt.Errorf("empty node group")
	}
	gateway := group[0]
	port := nodeutil.ResolvePort(gateway, defaultPort)
	addr := fmt.Sprintf("%s:%s", gateway.Host, port)

	dialCtx, cancel := context.WithTimeout(ctx, 5*time.Second)
	defer cancel()

	var opts []grpc.DialOption
	if insecureMode {
		opts = append(opts, grpc.WithTransportCredentials(insecure.NewCredentials()))
	}
	opts = append(opts, grpc.WithBlock())

	conn, err := grpc.DialContext(dialCtx, addr, opts...)
	if err != nil {
		return nil, fmt.Errorf("dial %s: %w", addr, err)
	}

	client := pb.NewDistTreeClient(conn)
	stream, err := client.PutStream(ctx)
	if err != nil {
		_ = conn.Close()
		return nil, fmt.Errorf("open PutStream to %s: %w", addr, err)
	}

	return &downstreamConn{
		conn:    conn,
		stream:  stream,
		addrs:   group,
		gateway: gateway,
	}, nil
}

// send 将一条消息发送到下游，若之前已标记为 bad 则跳过。
func (d *downstreamConn) send(req *pb.PutStreamReq) error {
	if d.bad.Load() {
		return fmt.Errorf("downstream %s marked bad", d.gateway.Host)
	}
	d.mu.Lock()
	defer d.mu.Unlock()
	if err := d.stream.Send(req); err != nil {
		d.bad.Store(true)
		return fmt.Errorf("send to %s: %w", d.gateway.Host, err)
	}
	return nil
}

// closeAndRecv 通知下游发送结束，然后收集所有 Reply 返回。
// 返回的 replies 中已包含下游递归汇总的结果。
func (d *downstreamConn) closeAndRecv(replies chan<- *pb.PutStreamReply) {
	defer d.conn.Close()

	if err := d.stream.CloseSend(); err != nil && err != io.EOF {
		replies <- &pb.PutStreamReply{
			Ok:       false,
			Nodelist: nodeutil.Join(d.addrs),
			Message:  fmt.Sprintf("CloseSend to %s: %v", d.gateway.Host, err),
		}
		return
	}

	for {
		r, err := d.stream.Recv()
		if err == io.EOF {
			break
		}
		if err != nil {
			replies <- &pb.PutStreamReply{
				Ok:       false,
				Nodelist: nodeutil.Join(d.addrs),
				Message:  fmt.Sprintf("recv from %s: %v", d.gateway.Host, err),
			}
			return
		}
		replies <- r
	}
}
