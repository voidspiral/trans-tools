package deps

// DepFile 描述一个依赖文件（通常为 .so）
type DepFile struct {
	Path   string  // 绝对路径
	SizeMB float64 // 文件大小（MB）
}

// DirGroup 按目录聚合的一组依赖文件
type DirGroup struct {
	Dir   string
	Files []DepFile
}

// TarFile 表示打包后的 tar 结果
type TarFile struct {
	Dir      string  // 原始目录
	TarPath  string  // tar 文件绝对路径
	SizeMB   float64 // tar 文件大小（MB）
	FileCount int    // 打包的文件数量
}

// Options 控制分发行为
type Options struct {
	Port        int    // gRPC 端口
	Width       int    // 树宽
	BufferSize  string // 负载大小（如 2M）
	HealthCheck bool   // 是否做健康检查（预留）
	DestDir     string // 远端保存目录
	Insecure    bool   // 关闭 TLS，仅测试用
}

// NodeResult 是单个节点（或批次）针对某个目录组的分发结果。
type NodeResult struct {
	Dir      string // 源目录组（如 /lib/x86_64-linux-gnu）
	Nodelist string // 节点或节点列表
	OK       bool
	Message  string
}

// Result 汇总分发结果
type Result struct {
	SuccessNodes []string     // 所有节点均成功的目录组
	FailedNodes  []string     // 存在失败节点的目录组
	Details      []NodeResult // 每条 Reply 的详细结果（per-node 粒度）
}

