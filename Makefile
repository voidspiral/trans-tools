BINARY_NAME ?= trans-tools
VERSION ?= 0.1.0
BUILD_TIME := $(shell date -u '+%Y-%m-%d_%H:%M:%S')
GIT_COMMIT := $(shell git rev-parse --short HEAD 2>/dev/null || echo "unknown")

LDFLAGS = -ldflags "\
	-X trans-tools/internal/version.Version=$(VERSION) \
	-X trans-tools/internal/version.BuildTime=$(BUILD_TIME) \
	-X trans-tools/internal/version.GitCommit=$(GIT_COMMIT) \
	-s -w"

.PHONY: build run clean test fmt lint help

build:
	go build $(LDFLAGS) -o bin/$(BINARY_NAME) ./cmd/trans-tools

run: build
	./bin/$(BINARY_NAME)

clean:
	rm -rf bin/

test:
	go test ./...

fmt:
	go fmt ./...

lint:
	golangci-lint run ./... 2>/dev/null || go vet ./...

help:
	@echo "trans-tools Makefile"
	@echo "  make build   - 编译二进制到 bin/"
	@echo "  make run     - 编译并运行"
	@echo "  make test    - 运行测试"
	@echo "  make fmt     - 格式化代码"
	@echo "  make clean   - 清理 bin/"
	@echo "  make help    - 显示此帮助"
