package deps

import (
	"archive/tar"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"strings"
)

// TarPackResult 表示一次打包操作的整体结果与临时目录。
type TarPackResult struct {
	TarFiles   []TarFile
	TempDir    string
	AutoRemove bool
}

// Close 清理临时目录（如 AutoRemove 为 true）。
func (r *TarPackResult) Close() error {
	if r == nil || !r.AutoRemove || r.TempDir == "" {
		return nil
	}
	return os.RemoveAll(r.TempDir)
}

// PackByDir 按目录聚合打包依赖文件，每个目录生成一个 tar。
func PackByDir(groups []DirGroup) (*TarPackResult, error) {
	if len(groups) == 0 {
		return &TarPackResult{}, nil
	}
	tempDir, err := os.MkdirTemp("", "trans-tools-deps-")
	if err != nil {
		return nil, err
	}
	result := &TarPackResult{
		TarFiles:   make([]TarFile, 0, len(groups)),
		TempDir:    tempDir,
		AutoRemove: true,
	}

	for _, g := range groups {
		if len(g.Files) == 0 {
			continue
		}
		// 将目录名中的所有 / 替换为 z（含开头），与 Python 实现保持一致：
		// /vol8/test_libs -> zvol8ztest_libs，挂载脚本可通过 ${name//z//} 正确还原原始路径
		name := strings.ReplaceAll(g.Dir, string(filepath.Separator), "z")
		if name == "" {
			name = "root"
		}
		tarName := name + "_so.tar"
		tarPath := filepath.Join(tempDir, tarName)

		f, err := os.Create(tarPath)
		if err != nil {
			result.Close()
			return nil, err
		}

		tw := tar.NewWriter(f)
		var totalSize int64
		for _, dep := range g.Files {
			info, err := os.Stat(dep.Path)
			if err != nil {
				_ = tw.Close()
				_ = f.Close()
				result.Close()
				return nil, fmt.Errorf("stat %s: %w", dep.Path, err)
			}
			hdr, err := tar.FileInfoHeader(info, "")
			if err != nil {
				_ = tw.Close()
				_ = f.Close()
				result.Close()
				return nil, err
			}
			// 去掉前导 /，保持相对路径结构
			hdr.Name = strings.TrimPrefix(dep.Path, string(filepath.Separator))
			if err := tw.WriteHeader(hdr); err != nil {
				_ = tw.Close()
				_ = f.Close()
				result.Close()
				return nil, err
			}
			src, err := os.Open(dep.Path)
			if err != nil {
				_ = tw.Close()
				_ = f.Close()
				result.Close()
				return nil, err
			}
			n, err := copyBuffer(tw, src)
			_ = src.Close()
			if err != nil {
				_ = tw.Close()
				_ = f.Close()
				result.Close()
				return nil, err
			}
			totalSize += n
		}
		if err := tw.Close(); err != nil {
			_ = f.Close()
			result.Close()
			return nil, err
		}
		if err := f.Close(); err != nil {
			result.Close()
			return nil, err
		}
		sizeMB := float64(totalSize) / (1024 * 1024)
		result.TarFiles = append(result.TarFiles, TarFile{
			Dir:       g.Dir,
			TarPath:   tarPath,
			SizeMB:    sizeMB,
			FileCount: len(g.Files),
		})
	}
	return result, nil
}

// copyBuffer 是对 io.Copy 的简单包装，返回复制的字节数。
func copyBuffer(dst *tar.Writer, src *os.File) (int64, error) {
	n, err := io.Copy(dst, src)
	return n, err
}

