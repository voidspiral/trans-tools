# trans-tools

Go 命令行工具项目模板，采用标准 `cmd` + `internal` 布局。

## 目录结构

```
trans-tools/
├── cmd/
│   └── trans-tools/     # 主程序入口
│       └── main.go
├── internal/            # 私有包（仅本项目使用）
│   ├── config/          # 配置
│   └── version/         # 版本信息
├── pkg/                 # 可对外复用的包（可选）
├── go.mod
├── Makefile
└── README.md
```

## 使用

```bash
# 编译
make build

# 运行
./bin/trans-tools

# 查看版本（需先 make build 注入版本信息）
./bin/trans-tools -version

# 测试
make test
```

## 扩展

- 在 `cmd/trans-tools/main.go` 中增加子命令或业务逻辑
- 在 `internal/` 下新增包实现具体功能
- 需要被其他项目引用时，将代码放在 `pkg/` 下

## 要求

- Go 1.21+
