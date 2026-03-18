// Package client 实现 DistTree 客户端，供 trans-tools deps 调用。
// 每次调用 PutStreamFile 对应一轮传输（一个文件）；多文件时由上层循环调用。
package client

import (
	"context"
	"crypto/md5"
	"fmt"
	"io"
	"log"
	"math"
	"os"
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
	// Port 是所有节点的默认端口；若节点列表中某节点以 "host:port" 格式给出，则以该端口为准。
	Port string
	// Width 是树宽：每个中间节点最多向 Width 个子节点建立直连流。
	Width int32
	// BufferSize 是每次 Send 的字节数。
	BufferSize int
	// Insecure 为 true 时不加载 TLS（测试用）。
	Insecure bool
	// DestDir 是远端落盘目录。
	DestDir string
}

// PutStreamFile 将 localFile 通过树形分发传输到 nodesExpr 描述的节点集合，
// 每个节点将文件保存到 opts.DestDir/<basename(localFile)>。
//
// nodesExpr 支持两种格式（可混用）：
//   - "cn[1-3]" 或 "cn1,cn2,cn3"       → 所有节点使用 opts.Port
//   - "cn1:19951,cn2:19952,cn3:19953"  → 每个节点使用各自端口（单机测试场景）
func PutStreamFile(ctx context.Context, localFile, nodesExpr string, opts Options) ([]Reply, error) {
	f, err := os.Open(localFile)
	if err != nil {
		return nil, fmt.Errorf("open %s: %w", localFile, err)
	}
	defer f.Close()

	fi, err := f.Stat()
	if err != nil {
		return nil, fmt.Errorf("stat %s: %w", localFile, err)
	}

	var uid, gid uint32
	var filemod uint32
	if sys, ok := fi.Sys().(*syscall.Stat_t); ok {
		uid = sys.Uid
		gid = sys.Gid
	}
	filemod = uint32(fi.Mode().Perm())
	modtime := fi.ModTime().Unix()
	filename := fi.Name()

	// 展开节点列表；支持 host:port 格式
	addrs := nodeutil.Expand(nodesExpr)
	if len(addrs) == 0 {
		return nil, fmt.Errorf("empty node list: %q", nodesExpr)
	}

	// 第一个节点：直连目标；其余节点作为 nodelist 下传（保留 host:port 格式）
	first := addrs[0]
	rest := addrs[1:]

	port := nodeutil.ResolvePort(first, opts.Port)
	addr := fmt.Sprintf("%s:%s", first.Host, port)

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

	client := pb.NewDistTreeClient(conn)
	stream, err := client.PutStream(ctx)
	if err != nil {
		return nil, fmt.Errorf("open PutStream to %s: %w", addr, err)
	}

	bufSize := opts.BufferSize
	if bufSize <= 0 {
		bufSize = 2 * 1024 * 1024
	}

	totalBlocks := int64(math.Ceil(float64(fi.Size()) / float64(bufSize)))
	sent := int64(0)
	isFirst := true

	buf := make([]byte, bufSize)
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
			req.Name = filename
			// rest 保留 host:port 格式，以便中间节点按节点自身端口拨号
			req.Nodelist = nodeutil.Join(rest)
			req.Port = opts.Port
			req.Width = opts.Width
			req.Uid = uid
			req.Gid = gid
			req.Filemod = filemod
			req.Modtime = modtime
			isFirst = false
		}

		if serr := stream.Send(req); serr != nil {
			return nil, fmt.Errorf("send to %s: %w", first.Host, serr)
		}
		sent++
		fmt.Printf("\r  发送进度: %d/%d", sent, totalBlocks)

		if rerr == io.EOF {
			break
		}
	}
	fmt.Println()

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
