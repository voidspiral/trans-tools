BINARY_NAME ?= trans-tools
VERSION ?= 0.1.2
BUILD_TIME := $(shell date -u '+%Y-%m-%d_%H:%M:%S')
GIT_COMMIT := $(shell git rev-parse --short HEAD 2>/dev/null || echo "unknown")

GO ?= go
# Force module mode (avoid GOPATH mode) and prefer vendored deps for offline builds.
GOENV ?= GO111MODULE=on
GOMOD ?= -mod=vendor

LDFLAGS = -ldflags "\
	-X trans-tools/internal/version.Version=$(VERSION) \
	-X trans-tools/internal/version.BuildTime=$(BUILD_TIME) \
	-X trans-tools/internal/version.GitCommit=$(GIT_COMMIT) \
	-s -w"

.PHONY: build build-agent build-all run clean test fmt lint vendor validate-fakefs-hooks validate-wrappersrun validate-sbatch-wrappersrun-cases validate-sbatch-no-umount-diagnostic validate-sbatch-wrappersrun-guards validate-sbatch-wrappersrun-all help

build:
	$(GOENV) $(GO) build $(GOMOD) $(LDFLAGS) -o bin/$(BINARY_NAME) ./cmd/trans-tools

build-agent:
	$(GOENV) $(GO) build $(GOMOD) $(LDFLAGS) -o bin/agent ./cmd/agent

build-all: build build-agent

run: build
	./bin/$(BINARY_NAME)

clean:
	rm -rf bin/

test:
	$(GOENV) $(GO) test $(GOMOD) ./...

fmt:
	$(GOENV) $(GO) fmt ./...

lint:
	golangci-lint run ./... 2>/dev/null || $(GOENV) $(GO) vet $(GOMOD) ./...

validate-fakefs-hooks:
	bash scripts/validate_fakefs_hooks.sh

validate-wrappersrun:
	bash scripts/wrappersrun_test.sh

validate-sbatch-wrappersrun-cases:
	bash scripts/run_sbatch_wrappersrun_cases.sh

validate-sbatch-no-umount-diagnostic:
	bash scripts/run_sbatch_no_umount_diagnostic.sh

validate-sbatch-wrappersrun-guards:
	bash scripts/regression_sbatch_wrappersrun_guards.sh

validate-sbatch-wrappersrun-all: validate-sbatch-wrappersrun-guards validate-sbatch-wrappersrun-cases validate-sbatch-no-umount-diagnostic

vendor:
	$(GOENV) $(GO) mod tidy
	$(GOENV) $(GO) mod vendor

help:
	@echo "trans-tools Makefile"
	@echo "  make build       - build client (trans-tools) to bin/"
	@echo "  make build-agent - build server (agent) to bin/"
	@echo "  make build-all   - build both client and server"
	@echo "  make run         - build and run client"
	@echo "  make test        - run tests"
	@echo "  make validate-fakefs-hooks - bash -n + hook regression test (+ shellcheck if installed)"
	@echo "  make validate-wrappersrun - wrappersrun.sh argument parsing + integration tests"
	@echo "  make validate-sbatch-wrappersrun-cases - submit sbatch wrappersrun case suite and validate markers"
	@echo "  make validate-sbatch-no-umount-diagnostic - run Epilog-disabled fakefs visibility diagnostic and cleanup checks"
	@echo "  make validate-sbatch-wrappersrun-guards - regression guards for wrappersrun/sbatch path and arg edge cases"
	@echo "  make validate-sbatch-wrappersrun-all - run guards + standard sbatch suite + no-umount diagnostic"
	@echo "  make fmt         - format code"
	@echo "  make vendor      - generate vendor/ (requires network)"
	@echo "  make clean       - remove bin/"
	@echo "  make help        - show this help"
