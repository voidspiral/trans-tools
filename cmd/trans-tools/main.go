// trans-tools 命令行入口
package main

import (
	"context"
	"flag"
	"fmt"
	"io"
	"os"
	"sort"
	"strings"
	"time"

	"trans-tools/internal/deps"
	"trans-tools/internal/version"

	"github.com/iskylite/nodeset"
)

func main() {
	args := os.Args[1:]

	if len(args) == 0 {
		printMainUsage(os.Stdout)
		os.Exit(0)
	}

	switch args[0] {
	case "-h", "--help", "help":
		printMainUsage(os.Stdout)
		os.Exit(0)
	case "deps":
		runDeps(args[1:])
		return
	}

	fs := flag.NewFlagSet("trans-tools", flag.ExitOnError)
	fs.SetOutput(os.Stderr)
	fs.Usage = func() { printMainUsage(os.Stderr) }

	showVersion := fs.Bool("version", false, "显示版本信息（构建时间、Git commit）")

	for _, a := range args {
		if a == "-h" || a == "--help" {
			printMainUsage(os.Stdout)
			os.Exit(0)
		}
	}

	if err := fs.Parse(args); err != nil {
		os.Exit(2)
	}

	if *showVersion {
		fmt.Println(version.String())
		os.Exit(0)
	}

	if rest := fs.Args(); len(rest) > 0 {
		fmt.Fprintf(os.Stderr, "未知子命令或多余参数: %s\n\n", strings.Join(rest, " "))
		printMainUsage(os.Stderr)
		os.Exit(2)
	}

	printMainUsage(os.Stdout)
	os.Exit(0)
}

func printMainUsage(w io.Writer) {
	fmt.Fprintf(w, `trans-tools — 程序依赖分析 + 多节点树形分发

用法:
  trans-tools [全局选项]
  trans-tools deps [选项]

全局选项:
  -version       显示版本信息
  -h, --help     显示本帮助

子命令:
  deps           分析可执行文件依赖，按目录打 tar，经 gRPC 树形分发到目标节点
                 详见: trans-tools deps -h

示例:
  trans-tools -version
  trans-tools deps --program /opt/app/bin/prog --nodes 'cn[1-32]' --port 2007
  trans-tools deps --program /usr/bin/python3 --nodes 'h1:19951,h2:19952' --filter-prefix /lib --insecure
`)
}

func printDepsUsage(w io.Writer, fs *flag.FlagSet) {
	fmt.Fprintf(w, `用法: trans-tools deps [选项]

分析 --program 指定程序的共享库等依赖，按目录分组打包为本地临时 tar（默认目录: /tmp/trans-tools-deps*），
再向 --nodes 所列节点上的 agent 做树形分发，文件落在各节点 --dest 指定目录（或由 agent 的 -dest-override 覆盖）。

必填:
  -program string    待分析程序的绝对路径
  -nodes string      目标节点：nodeset 表达式（如 cn[1-3]）或逗号分隔的 host[:port]（端口与 agent 监听一致）

可选:
`)
	fs.SetOutput(w)
	fs.PrintDefaults()
	fmt.Fprintf(w, `
说明:
  -filter-prefix     多个目录用英文逗号分隔；传空字符串 "" 表示不按路径前缀筛选（使用全部依赖）。
  -auto-clean        为 true（默认）时，分发结束后删除本地临时 tar 目录；调试可设 -auto-clean=false。
  -insecure          关闭 TLS，仅用于测试；生产环境 agent 与客户端需一致配置。

示例:
  trans-tools deps --program /bin/myapp --nodes 'cn[1-100]' --dest /data/deps --filter-prefix /vol8
  trans-tools deps --program /bin/tool --nodes 'n1,n2,n3' --width 32 --buffer 4M --min-size-mb 5
`)
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
	fs.SetOutput(os.Stderr)

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

	fs.StringVar(&program, "program", "", "要分析的可执行文件绝对路径")
	fs.StringVar(&nodes, "nodes", "", "目标节点列表：nodeset（如 cn[1-3]）或 host:port 逗号列表")
	fs.IntVar(&minSizeMB, "min-size-mb", 10, "只包含大于等于该大小（MB）的依赖文件")
	fs.IntVar(&port, "port", 2007, "目标 agent gRPC 端口（nodes 为 host:port 时以各 host 端口为准）")
	fs.StringVar(&buffer, "buffer", "2M", "流传输单块大小，如 512k、1M、2M")
	fs.IntVar(&width, "width", 50, "树形分发每层下游数量上限")
	fs.StringVar(&destDir, "dest", "/tmp/dependencies", "远端写入依赖的根目录（agent 可用 -dest-override 覆盖）")
	fs.StringVar(&filterPrefix, "filter-prefix", "/vol8", "只打包路径具有此前缀的依赖；逗号多前缀；空字符串表示不筛选")
	fs.BoolVar(&autoClean, "auto-clean", true, "结束后是否删除本地临时 tar 目录（/tmp/trans-tools-deps*）")
	fs.BoolVar(&insecure, "insecure", false, "关闭 gRPC TLS（仅测试，须与 agent 一致）")

	fs.Usage = func() { printDepsUsage(os.Stderr, fs) }

	for _, a := range args {
		if a == "-h" || a == "--help" {
			printDepsUsage(os.Stdout, fs)
			os.Exit(0)
		}
	}

	if err := fs.Parse(args); err != nil {
		os.Exit(2)
	}
	if program == "" || nodes == "" {
		printDepsUsage(os.Stderr, fs)
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
	printResult(res)
	if len(res.FailedNodes) > 0 {
		os.Exit(1)
	}
}

// printResult 按 ClusterShell -b 风格聚合打印：
//   - 成功：只输出总数
//   - 失败：按错误信息聚合节点列表（折叠为 nodeset 表达式），方便复制排查
func printResult(res deps.Result) {
	if len(res.Details) == 0 {
		return
	}

	type dirStat struct {
		okCount   int
		failByMsg map[string][]string // msg → []nodelist
	}
	groups := map[string]*dirStat{}
	dirOrder := []string{}
	for _, d := range res.Details {
		if _, exists := groups[d.Dir]; !exists {
			groups[d.Dir] = &dirStat{failByMsg: map[string][]string{}}
			dirOrder = append(dirOrder, d.Dir)
		}
		g := groups[d.Dir]
		if d.OK {
			g.okCount++
		} else {
			g.failByMsg[d.Message] = append(g.failByMsg[d.Message], d.Nodelist)
		}
	}
	sort.Strings(dirOrder)

	fmt.Println()
	for _, dir := range dirOrder {
		g := groups[dir]
		totalFail := 0
		for _, nodes := range g.failByMsg {
			totalFail += len(nodes)
		}

		fmt.Printf("  %s: %d ok, %d fail\n", dir, g.okCount, totalFail)

		if totalFail > 0 {
			for msg, nodes := range g.failByMsg {
				folded, err := nodeset.Merge(nodes...)
				if err != nil {
					folded = strings.Join(nodes, ",")
				}
				fmt.Printf("    FAIL %s (%d): %s\n", folded, len(nodes), msg)
			}
		}
	}
	fmt.Println()
}
