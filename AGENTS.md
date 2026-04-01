# AGENTS.md

## Cursor Cloud specific instructions

### Project overview

trans-tools is a Go-based HPC toolset for program dependency analysis and tree-based multi-node file distribution via gRPC. See `README.md` for full documentation.

### Key commands

All standard build/test/lint commands are in the `Makefile`:

- `make build-all` — build both `bin/trans-tools` (CLI client) and `bin/agent` (gRPC server)
- `make test` — run unit tests
- `make lint` — run `golangci-lint` (falls back to `go vet` if not installed)
- `make fmt` — format code
- `make vendor` — regenerate `vendor/` directory

### Build requirements

- Go 1.24.0 (declared in `go.mod`). The Makefile uses `-mod=vendor`, so `vendor/` must exist before building.
- No database or external service dependencies.

### Running the e2e test locally

The script `scripts/e2e_deps_local.sh` starts 3 local agents on different ports and distributes dependencies of a given binary:

```bash
bash scripts/e2e_deps_local.sh /bin/ls "cn[1-3]"
```

This is the best way to validate the full client-server flow without a cluster.

### Gotchas

- The Makefile uses `-mod=vendor` for all Go commands. If `vendor/` is missing, run `go mod tidy && go mod vendor` before building.
- `go fmt` may reformat files that are committed with non-standard formatting. Do not commit formatting-only changes unless intentional.
- The `myclush`, `newserver`, and `syncFS` directories are reference-only and must not be modified (per workspace rules).
- The slurm hook regression test (`scripts/slurm_fakefs_hook_soft_fail_test.sh`) runs without `fakefs` installed and tests error-handling paths only.
