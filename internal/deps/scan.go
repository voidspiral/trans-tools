package deps

import (
	"bufio"
	"bytes"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"sort"
	"strconv"
	"strings"
)

// AnalyzeDependencies 使用 ldd 分析二进制程序依赖的 .so 文件，并按大小过滤。
func AnalyzeDependencies(programPath string, minSizeMB int) ([]DepFile, error) {
	if programPath == "" {
		return nil, fmt.Errorf("program path is empty")
	}
	abs, err := filepath.Abs(programPath)
	if err != nil {
		return nil, err
	}
	info, err := os.Stat(abs)
	if err != nil {
		return nil, err
	}
	if info.IsDir() {
		return nil, fmt.Errorf("program path %q is a directory", abs)
	}

	cmd := exec.Command("ldd", abs)
	var stdout, stderr bytes.Buffer
	cmd.Stdout = &stdout
	cmd.Stderr = &stderr
	if err := cmd.Run(); err != nil {
		return nil, fmt.Errorf("ldd failed: %v, stderr=%s", err, stderr.String())
	}

	minBytes := int64(minSizeMB) * 1024 * 1024
	var files []DepFile

	scanner := bufio.NewScanner(&stdout)
	for scanner.Scan() {
		line := strings.TrimSpace(scanner.Text())
		if line == "" || strings.Contains(line, "not found") {
			continue
		}
		// 两种典型格式：
		// libxxx.so => /path/to/libxxx.so (0x...)
		// /path/to/libxxx.so (0x...)
		var soPath string
		if strings.Contains(line, "=>") {
			parts := strings.SplitN(line, "=>", 2)
			if len(parts) != 2 {
				continue
			}
			fields := strings.Fields(strings.TrimSpace(parts[1]))
			if len(fields) == 0 {
				continue
			}
			soPath = fields[0]
		} else {
			fields := strings.Fields(line)
			if len(fields) == 0 {
				continue
			}
			soPath = fields[0]
		}
		if !filepath.IsAbs(soPath) {
			continue
		}
		st, err := os.Stat(soPath)
		if err != nil || !st.Mode().IsRegular() {
			continue
		}
		if st.Size() < minBytes {
			continue
		}
		sizeMB := float64(st.Size()) / (1024 * 1024)
		files = append(files, DepFile{
			Path:   soPath,
			SizeMB: sizeMB,
		})
	}
	if err := scanner.Err(); err != nil {
		return nil, err
	}

	// 按大小从大到小排序
	sort.Slice(files, func(i, j int) bool {
		return files[i].SizeMB > files[j].SizeMB
	})
	return files, nil
}

// normalizePrefix 将前缀规范为目录形式，避免 /vol8 匹配到 /vol8xxx。
func normalizePrefix(p string) string {
	p = strings.TrimSpace(p)
	if p == "" {
		return p
	}
	if !strings.HasSuffix(p, "/") {
		return p + "/"
	}
	return p
}

// FilterByPrefixes 只保留路径以任一指定前缀开头的依赖；prefixes 为空则不筛选。
func FilterByPrefixes(files []DepFile, prefixes []string) []DepFile {
	if len(prefixes) == 0 {
		return files
	}
	normed := make([]string, 0, len(prefixes))
	for _, p := range prefixes {
		if q := normalizePrefix(p); q != "" {
			normed = append(normed, q)
		}
	}
	if len(normed) == 0 {
		return files
	}
	var out []DepFile
	for _, f := range files {
		for _, pre := range normed {
			if strings.HasPrefix(f.Path, pre) {
				out = append(out, f)
				break
			}
		}
	}
	return out
}

// FilterByPrefix 只保留指定前缀（例如 /vol8/）的依赖。
func FilterByPrefix(files []DepFile, prefix string) []DepFile {
	if prefix == "" {
		return files
	}
	return FilterByPrefixes(files, []string{prefix})
}

// GroupByDir 将依赖按目录聚合。
func GroupByDir(files []DepFile) []DirGroup {
	if len(files) == 0 {
		return nil
	}
	m := make(map[string][]DepFile)
	for _, f := range files {
		dir := filepath.Dir(f.Path)
		m[dir] = append(m[dir], f)
	}
	dirs := make([]string, 0, len(m))
	for d := range m {
		dirs = append(dirs, d)
	}
	sort.Strings(dirs)
	out := make([]DirGroup, 0, len(dirs))
	for _, d := range dirs {
		out = append(out, DirGroup{
			Dir:   d,
			Files: m[d],
		})
	}
	return out
}

// ParseSizeString 解析诸如 "512k"、"1m"、"2M" 这样的大小字符串，返回字节数。
func ParseSizeString(s string) (int, error) {
	s = strings.TrimSpace(strings.ToLower(s))
	if s == "" {
		return 0, fmt.Errorf("size string is empty")
	}
	multiplier := 1
	switch {
	case strings.HasSuffix(s, "k"):
		multiplier = 1024
		s = strings.TrimSuffix(s, "k")
	case strings.HasSuffix(s, "m"):
		multiplier = 1024 * 1024
		s = strings.TrimSuffix(s, "m")
	case strings.HasSuffix(s, "g"):
		multiplier = 1024 * 1024 * 1024
		s = strings.TrimSuffix(s, "g")
	}
	n, err := strconv.Atoi(strings.TrimSpace(s))
	if err != nil || n <= 0 {
		return 0, fmt.Errorf("invalid size string: %q", s)
	}
	return n * multiplier, nil
}

