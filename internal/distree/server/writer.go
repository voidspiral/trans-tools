package server

import (
	"fmt"
	"os"
	"path/filepath"
	"sync/atomic"
	"time"
)

// localWriter 负责将接收到的字节块写入临时文件，
// 收完后 Rename 到目标路径（dest_dir/name）。
type localWriter struct {
	fp      string     // 目标路径 dest_dir/name
	f       *os.File   // 临时文件句柄
	bad     atomic.Bool
	writeErr error
}

func newLocalWriter(tmpDir, destDir, name string, uid, gid, filemod uint32, modtime int64) (*localWriter, error) {
	if err := os.MkdirAll(tmpDir, 0755); err != nil {
		return nil, fmt.Errorf("mkdir tmp dir %s: %w", tmpDir, err)
	}
	f, err := os.CreateTemp(tmpDir, "distree-*")
	if err != nil {
		return nil, fmt.Errorf("create temp file: %w", err)
	}

	if err = f.Chown(int(uid), int(gid)); err != nil {
		// 非 root 可能失败，记录警告但不中断
		_ = err
	}
	if filemod != 0 {
		if err = f.Chmod(os.FileMode(filemod)); err != nil {
			_ = err
		}
	}
	if modtime != 0 {
		_ = os.Chtimes(f.Name(), time.Now(), time.Unix(modtime, 0))
	}

	fp := filepath.Join(destDir, name)
	w := &localWriter{fp: fp, f: f}
	return w, nil
}

// write 将 data 追加写入临时文件；一旦出错后续写入均被忽略。
func (w *localWriter) write(data []byte) error {
	if w.bad.Load() {
		return w.writeErr
	}
	_, err := w.f.Write(data)
	if err != nil {
		w.bad.Store(true)
		w.writeErr = err
	}
	return err
}

// commit 关闭临时文件并 Rename 到目标路径；若之前有写入错误则清理临时文件并返回错误。
func (w *localWriter) commit() error {
	tmpName := w.f.Name()
	if err := w.f.Close(); err != nil {
		_ = os.Remove(tmpName)
		return fmt.Errorf("close temp file: %w", err)
	}
	if w.bad.Load() {
		_ = os.Remove(tmpName)
		return w.writeErr
	}
	if err := os.MkdirAll(filepath.Dir(w.fp), 0755); err != nil {
		_ = os.Remove(tmpName)
		return fmt.Errorf("mkdir dest dir: %w", err)
	}
	if err := os.Rename(tmpName, w.fp); err != nil {
		_ = os.Remove(tmpName)
		return fmt.Errorf("rename %s -> %s: %w", tmpName, w.fp, err)
	}
	return nil
}

// abort 丢弃临时文件（用于出错时清理）。
func (w *localWriter) abort() {
	_ = w.f.Close()
	_ = os.Remove(w.f.Name())
}
