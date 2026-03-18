package config

// Config 全局配置（按需扩展）
type Config struct {
	Verbose bool
}

// Default 返回默认配置
func Default() *Config {
	return &Config{
		Verbose: false,
	}
}
