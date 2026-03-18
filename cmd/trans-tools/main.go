// trans-tools 命令行入口
package main

import (
	"context"
	"flag"
	"fmt"
	"os"
	"strings"
	"time"

	"trans-tools/internal/deps"
	"trans-tools/internal/version"
)

func main() {
	if len(os.Args) > 1 && os.Args[1] == "deps" {
		runDeps(os.Args[2:])
		return
	}

	showVersion := flag.Bool("version", false, "显示版本信息")
	flag.Parse()

	if *showVersion {
		fmt.Println(version.String())
		os.Exit(0)
	}

	fmt.Println("trans-tools - 工具集")
	fmt.Println("用法示例:")
	fmt.Println("  trans-tools -version")
	fmt.Println("  trans-tools deps --program /path/to/prog --nodes cn[1-3]")
	fmt.Println("  trans-tools deps --program /path/to/prog --nodes cn[1-3] --insecure  # 测试用，关闭 TLS")
	fmt.Println("  trans-tools deps --program /path/to/prog --nodes cn[1-3] --filter-prefix /lib  # 单机测试，指定依赖目录")
}

func parseFilterPrefixes(s string) []string {
	s = strings.TrimSpace(s)
	if s == "" {
		return nil
	}
	var out []string
	for _, p := range strings.Split(s, ",") {
		if q := strings.TrimSpace(p); q != "" {
			out = append(out, q)
		}
	}
	return out
}

func runDeps(args []string) {
	fs := flag.NewFlagSet("deps", flag.ExitOnError)
	var (
		program      string
		nodes        string
		minSizeMB    int
		port         int
		buffer       string
		width        int
		destDir      string
		filterPrefix string
		autoClean    bool
		insecure     bool
	)
	fs.StringVar(&program, "program", "", "要分析的程序路径（绝对路径）")
	fs.StringVar(&nodes, "nodes", "", "目标节点列表（如 cn[1-3]）")
	fs.IntVar(&minSizeMB, "min-size-mb", 10, "最小依赖文件大小（MB）")
	fs.IntVar(&port, "port", 1995, "gRPC 服务端口")
	fs.StringVar(&buffer, "buffer", "2M", "上传时的 payload 大小，例如 512k, 1M, 2M")
	fs.IntVar(&width, "width", 50, "树形分发宽度")
	fs.StringVar(&destDir, "dest", "/tmp/dependencies", "远端依赖存储目录")
	fs.StringVar(&filterPrefix, "filter-prefix", "/vol8", "依赖挂载目录前缀，逗号分隔多目录（默认 /vol8）；空表示不筛选。单机测试可填 /lib 或 /lib,/usr/lib")
	fs.BoolVar(&autoClean, "auto-clean", true, "完成后自动删除本地临时 tar 包")
	fs.BoolVar(&insecure, "insecure", false, "关闭 gRPC TLS 与认证，仅用于测试多节点分发")

	if err := fs.Parse(args); err != nil {
		fmt.Fprintln(os.Stderr, "解析参数失败:", err)
		os.Exit(2)
	}
	if program == "" || nodes == "" {
		fs.Usage()
		os.Exit(2)
	}

	if insecure {
		fmt.Println("WARNING: 使用 insecure 传输模式，仅适用于测试环境")
	}

	fmt.Println("== 步骤 1: 分析程序依赖 ==")
	allDeps, err := deps.AnalyzeDependencies(program, minSizeMB)
	if err != nil {
		fmt.Fprintln(os.Stderr, "依赖分析失败:", err)
		os.Exit(1)
	}
	if len(allDeps) == 0 {
		fmt.Println("未找到符合条件的依赖文件，直接退出。")
		return
	}

	var filtered []deps.DepFile
	prefixes := parseFilterPrefixes(filterPrefix)
	if len(prefixes) == 0 {
		fmt.Println("== 步骤 2: 不按目录筛选，使用全部依赖 ==")
		filtered = allDeps
	} else {
		fmt.Printf("== 步骤 2: 筛选指定目录下的依赖: %s ==\n", strings.Join(prefixes, ", "))
		filtered = deps.FilterByPrefixes(allDeps, prefixes)
		if len(filtered) == 0 {
			fmt.Println("未找到指定目录下的依赖，使用全部依赖。")
			filtered = allDeps
		}
	}

	fmt.Println("== 步骤 3: 按目录分组并打包 ==")
	groups := deps.GroupByDir(filtered)
	packResult, err := deps.PackByDir(groups)
	if err != nil {
		fmt.Fprintln(os.Stderr, "打包失败:", err)
		os.Exit(1)
	}
	if autoClean {
		defer packResult.Close()
	}
	if len(packResult.TarFiles) == 0 {
		fmt.Println("没有需要分发的 tar 包，直接退出。")
		return
	}

	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Minute)
	defer cancel()

	fmt.Println("== 步骤 4: 通过树形分发传输 tar 包 ==")
	res, err := deps.DistributeTarTrees(ctx, packResult.TarFiles, nodes, deps.Options{
		Port:        port,
		Width:       width,
		BufferSize:  buffer,
		HealthCheck: false,
		DestDir:     destDir,
		Insecure:    insecure,
	})
	if err != nil {
		fmt.Fprintln(os.Stderr, "分发失败:", err)
		os.Exit(1)
	}

	fmt.Println("== 步骤 5: 结果汇总 ==")

	// per-node 详细结果
	if len(res.Details) > 0 {
		fmt.Println("  节点分发明细:")
		for _, d := range res.Details {
			status := "OK  "
			if !d.OK {
				status = "FAIL"
			}
			fmt.Printf("    [%s] dir=%-40s node=%-20s msg=%s\n", status, d.Dir, d.Nodelist, d.Message)
		}
	}

	fmt.Printf("\n成功目录组: %d\n", len(res.SuccessNodes))
	for _, n := range res.SuccessNodes {
		fmt.Println("  OK :", n)
	}
	fmt.Printf("失败目录组: %d\n", len(res.FailedNodes))
	for _, n := range res.FailedNodes {
		fmt.Println("  FAIL:", n)
	}
	if len(res.FailedNodes) > 0 {
		os.Exit(1)
	}
}
