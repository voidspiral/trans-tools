package deps

import (
	"context"
	"fmt"
	"sync"

	"trans-tools/internal/distree/client"
)

// DistributeTarTrees 使用 distree 树形协议分发 tar 文件到目标节点。
// 每个 tar 文件独立发起一轮 PutStreamFile 调用，按 width 分组并发送。
// 单节点故障不影响其他节点，结果汇总后返回。
func DistributeTarTrees(ctx context.Context, tarFiles []TarFile, nodesPattern string, opt Options) (Result, error) {
	if len(tarFiles) == 0 {
		return Result{}, nil
	}
	if nodesPattern == "" {
		return Result{}, fmt.Errorf("nodes pattern is empty")
	}

	bufBytes, err := client.ConvertBufferSize(opt.BufferSize)
	if err != nil {
		return Result{}, fmt.Errorf("invalid buffer size %q: %w", opt.BufferSize, err)
	}

	cliOpts := client.Options{
		Port:       fmt.Sprintf("%d", opt.Port),
		Width:      int32(opt.Width),
		BufferSize: bufBytes,
		Insecure:   opt.Insecure,
		DestDir:    opt.DestDir,
	}

	type rowResult struct {
		dir     string
		replies []client.Reply
		err     error
	}
	resultsCh := make(chan rowResult, len(tarFiles))

	var wg sync.WaitGroup
	for _, tf := range tarFiles {
		tf := tf
		wg.Add(1)
		go func() {
			defer wg.Done()
			replies, ferr := client.PutStreamFile(ctx, tf.TarPath, nodesPattern, cliOpts)
			resultsCh <- rowResult{dir: tf.Dir, replies: replies, err: ferr}
		}()
	}

	go func() {
		wg.Wait()
		close(resultsCh)
	}()

	var result Result
	for r := range resultsCh {
		if r.err != nil {
			result.FailedNodes = append(result.FailedNodes, r.dir)
			result.Details = append(result.Details, NodeResult{
				Dir:      r.dir,
				Nodelist: "-",
				OK:       false,
				Message:  r.err.Error(),
			})
			continue
		}

		allOK := true
		for _, reply := range r.replies {
			result.Details = append(result.Details, NodeResult{
				Dir:      r.dir,
				Nodelist: reply.Nodelist,
				OK:       reply.OK,
				Message:  reply.Message,
			})
			if !reply.OK {
				allOK = false
			}
		}
		if allOK {
			result.SuccessNodes = append(result.SuccessNodes, r.dir)
		} else {
			result.FailedNodes = append(result.FailedNodes, r.dir)
		}
	}

	return result, nil
}
