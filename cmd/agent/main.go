// cmd/agent: 依赖分发 agent，实现 DistTree gRPC 服务，替代原 myclush 服务。
package main

import (
	"context"
	"flag"
	"fmt"
	"os"
	"os/signal"

	"trans-tools/internal/distree/server"
)

func main() {
	var (
		tmpDir       string
		port         int
		insecure     bool
		destOverride string
	)

	flag.StringVar(&tmpDir, "tmp-name", "trans-tools-agent", "临时文件目录名（用于落盘前的临时文件存放，位于 /tmp 下）")
	flag.IntVar(&port, "port", 1995, "gRPC 监听端口")
	flag.StringVar(&destOverride, "dest-override", "", "覆盖客户端请求的 dest_dir，将接收到的文件落盘到此本地目录（为空则使用客户端指定的路径）")
	flag.BoolVar(&insecure, "insecure", false, "关闭 TLS，仅用于测试环境")
	flag.Parse()

	// tmp-name 直接拼 /tmp 前缀作为临时目录
	tmpPath := "/tmp/" + tmpDir

	cfg := server.Config{
		TmpDir:       tmpPath,
		DestOverride: destOverride,
		Insecure:     insecure,
	}

	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	c := make(chan os.Signal, 1)
	signal.Notify(c, os.Interrupt)
	go func() {
		<-c
		fmt.Println("\nagent: received interrupt, shutting down...")
		cancel()
	}()

	if insecure {
		fmt.Printf("agent: WARNING: insecure 模式，仅适用于测试环境\n")
	}
	if destOverride != "" {
		fmt.Printf("agent: dest-override=%s（忽略客户端 dest_dir）\n", destOverride)
	}
	fmt.Printf("agent: starting on port %d, tmpDir=%s\n", port, tmpPath)

	if err := server.Serve(ctx, cfg, port); err != nil {
		fmt.Fprintf(os.Stderr, "agent: server error: %v\n", err)
		os.Exit(1)
	}
	fmt.Println("agent: stopped")
}
