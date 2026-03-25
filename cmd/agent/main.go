// cmd/agent runs the DistTree gRPC server.
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

	flag.StringVar(&tmpDir, "tmp-name", "trans-tools-agent", "temporary directory name under /tmp for incoming file buffering")
	flag.IntVar(&port, "port", 2007, "gRPC listen port")
	flag.StringVar(&destOverride, "dest-override", "", "override client dest_dir and write files to this local directory")
	flag.BoolVar(&insecure, "insecure", false, "disable TLS (testing only)")
	flag.Parse()

	// tmp-name is resolved under /tmp.
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
		fmt.Printf("agent: WARNING: insecure mode enabled (testing only)\n")
	}
	if destOverride != "" {
		fmt.Printf("agent: dest-override=%s (client dest_dir is ignored)\n", destOverride)
	}
	fmt.Printf("agent: starting on port %d, tmpDir=%s\n", port, tmpPath)

	if err := server.Serve(ctx, cfg, port); err != nil {
		fmt.Fprintf(os.Stderr, "agent: server error: %v\n", err)
		os.Exit(1)
	}
	fmt.Println("agent: stopped")
}
