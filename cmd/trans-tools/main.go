// trans-tools CLI entrypoint
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

	showVersion := fs.Bool("version", false, "show version information (build time, Git commit)")

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
		fmt.Fprintf(os.Stderr, "unknown subcommand or extra arguments: %s\n\n", strings.Join(rest, " "))
		printMainUsage(os.Stderr)
		os.Exit(2)
	}

	printMainUsage(os.Stdout)
	os.Exit(0)
}

func printMainUsage(w io.Writer) {
	fmt.Fprintf(w, `trans-tools — dependency analysis + tree distribution

Usage:
  trans-tools [global options]
  trans-tools deps [options]

Global options:
  -version       show version information
  -h, --help     show this help

Subcommands:
  deps           analyze executable dependencies, pack by directory, and
                 distribute by gRPC tree to target nodes
                 see: trans-tools deps -h

Examples:
  trans-tools -version
  trans-tools deps --program /opt/app/bin/prog --nodes 'cn[1-32]' --port 2007
  trans-tools deps --program /usr/bin/python3 --nodes 'h1:19951,h2:19952' --filter-prefix /lib --insecure
`)
}

func printDepsUsage(w io.Writer, fs *flag.FlagSet) {
	fmt.Fprintf(w, `Usage: trans-tools deps [options]

Analyze dependencies of --program, pack by directory to local temporary tar files
(default: /tmp/trans-tools-deps*), then distribute by tree to agents listed in
--nodes. Files are written under --dest on each node (or overridden by agent -dest-override).

Required:
  -program string    absolute path of executable to analyze
  -nodes string      target nodes: nodeset expression (e.g. cn[1-3]) or
                     comma-separated host[:port] list

Options:
`)
	fs.SetOutput(w)
	fs.PrintDefaults()
	fmt.Fprintf(w, `
Notes:
  -filter-prefix     use comma-separated prefixes; pass "" to disable prefix filtering.
  -auto-clean        true by default; remove local temporary tar directory after distribution.
  -insecure          disable TLS for testing only; client/agent settings must match.

Examples:
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

	fs.StringVar(&program, "program", "", "absolute path of executable to analyze")
	fs.StringVar(&nodes, "nodes", "", "target nodes: nodeset (e.g. cn[1-3]) or host:port comma list")
	fs.IntVar(&minSizeMB, "min-size-mb", 10, "include only dependencies with size >= this value (MB)")
	fs.IntVar(&port, "port", 2007, "target agent gRPC port (host:port entries override this default)")
	fs.StringVar(&buffer, "buffer", "2M", "stream payload size per chunk, e.g. 512k, 1M, 2M")
	fs.IntVar(&width, "width", 50, "max fan-out per tree layer")
	fs.StringVar(&destDir, "dest", "/tmp/dependencies", "destination root directory on remote nodes")
	fs.StringVar(&filterPrefix, "filter-prefix", "/vol8", "dependency path prefixes to include; comma-separated, empty string disables filter")
	fs.BoolVar(&autoClean, "auto-clean", true, "remove local temporary tar directory after distribution")
	fs.BoolVar(&insecure, "insecure", false, "disable gRPC TLS (testing only, must match agent)")

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
		fmt.Println("WARNING: insecure transport mode enabled (testing only)")
	}

	fmt.Println("== Step 1: Analyze program dependencies ==")
	allDeps, err := deps.AnalyzeDependencies(program, minSizeMB)
	if err != nil {
		fmt.Fprintln(os.Stderr, "dependency analysis failed:", err)
		os.Exit(1)
	}
	if len(allDeps) == 0 {
		fmt.Println("No dependency files matched filters. Exit.")
		return
	}

	var filtered []deps.DepFile
	prefixes := parseFilterPrefixes(filterPrefix)
	if len(prefixes) == 0 {
		fmt.Println("== Step 2: Use all dependencies (no prefix filter) ==")
		filtered = allDeps
	} else {
		fmt.Printf("== Step 2: Filter dependencies by prefixes: %s ==\n", strings.Join(prefixes, ", "))
		filtered = deps.FilterByPrefixes(allDeps, prefixes)
		if len(filtered) == 0 {
			fmt.Println("No dependencies matched prefixes. Fallback to all dependencies.")
			filtered = allDeps
		}
	}

	fmt.Println("== Step 3: Group and pack dependencies by directory ==")
	groups := deps.GroupByDir(filtered)
	packResult, err := deps.PackByDir(groups)
	if err != nil {
		fmt.Fprintln(os.Stderr, "pack failed:", err)
		os.Exit(1)
	}
	if autoClean {
		defer packResult.Close()
	}
	if len(packResult.TarFiles) == 0 {
		fmt.Println("No tar package to distribute. Exit.")
		return
	}

	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Minute)
	defer cancel()

	fmt.Println("== Step 4: Distribute tar files by tree ==")
	res, err := deps.DistributeTarTrees(ctx, packResult.TarFiles, nodes, deps.Options{
		Port:        port,
		Width:       width,
		BufferSize:  buffer,
		HealthCheck: false,
		DestDir:     destDir,
		Insecure:    insecure,
	})
	if err != nil {
		fmt.Fprintln(os.Stderr, "distribution failed:", err)
		os.Exit(1)
	}

	fmt.Println("== Step 5: Summary ==")
	printResult(res)
	if len(res.FailedNodes) > 0 {
		os.Exit(1)
	}
}

// printResult prints ClusterShell-style aggregated output:
//   - success: only counts
//   - failures: grouped by error message with folded nodeset lists
func printResult(res deps.Result) {
	if len(res.Details) == 0 {
		return
	}

	type dirStat struct {
		okCount   int
		failByMsg map[string][]string // msg -> []nodelist
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
