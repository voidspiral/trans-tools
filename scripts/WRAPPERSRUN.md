# wrappersrun.sh 运维说明

## 一、执行生命周期

1. **依赖分析与分发**  
   当 `WRAPPERSRUN_ENABLE_DEPS=true`（默认）时，`scripts/wrappersrun.sh` 会先执行 `trans-tools deps`，将依赖打包为 `*_so.tar`，输出到 `WRAPPERSRUN_DEPS_DEST`（默认 `/tmp/dependencies`）。
2. **Slurm Prolog 挂载 fakefs**  
   站点 Hook（如 `scripts/dependency_mount_fakefs_prolog_wrapper.sh`）读取这些 tar 包，并通过 `fakefs` 将 `/vol8/...` 叠加到 `${WRAPPERSRUN_DEPS_DEST}/.fakefs/...` 的上层目录。
3. **启动任务**  
   wrapper 最终执行 `exec srun`（或 `WRAPPERSRUN_LAUNCHER=mpirun` 时执行 `mpirun`），并透传原始调度参数。
4. **Slurm Epilog 清理**  
   Epilog Hook（如 `scripts/dependency_mount_fakefs_epilog_wrapper.sh`）卸载 FUSE 挂载，并按策略清理 `.fakefs` 状态目录。

## 二、Prolog 时序说明

在很多集群中，`Prolog=` 先于作业脚本执行；此时 `*_so.tar` 尚未生成，首次 Prolog 可能“空跑”。  
因此在 provenance 场景中，`WRAPPERSRUN_POST_DEPS_HOOK` 会在 tar patch 后立即再次调用 `dependency_mount_fakefs.sh`，确保 `exec srun` 前挂载已就绪。

## 三、调用方式

### 1) 直接 `srun`

将 `scripts/wrappersrun.sh` 作为 Slurm 作业命令（或在 `srun` step 内调用）。依赖目标节点需通过以下任一方式提供：

- `WRAPPERSRUN_DEPS_NODES`
- 在 `--` 前显式传入 `srun -w` / `--nodelist=...`
- 来自现有分配环境的 `SLURM_NODELIST` / `SLURM_JOB_NODELIST`

若使用随机分配（如 `srun -N1 -n1`）且没有节点列表信息，脚本会以状态码 `1` 失败并输出 `missing nodes for deps`。

### 2) `sbatch` 用法

在 batch 脚本中调用一次 `scripts/wrappersrun.sh`，并传入目标 `srun` 参数。  
建议导出 `WRAPPERSRUN_PROJECT_DIR`（也可依赖 `SLURM_SUBMIT_DIR`）以便脚本稳定定位仓库根目录。

### 3) `salloc --no-shell` 分段流程

1. 先申请资源：`salloc --no-shell ...`
2. 再使用 `srun --jobid=<jobid> ... scripts/wrappersrun.sh ...` 提交步骤任务
3. 若环境中没有可用节点列表，仍需显式设置 `WRAPPERSRUN_DEPS_NODES` 或传入 `-w/--nodelist`

## 四、快速排障

- **挂载可见性**：运行步骤内执行 `df -h`，应看到 `/vol8/` 上的 `fakefs` 挂载；再用 `findmnt -t fuse.fakefs` 交叉确认。
- **staging 目录检查**：缺库问题优先检查 `${WRAPPERSRUN_DEPS_DEST}/.fakefs/` 下各路径对应的 `upper/work` 目录。
- **deps 失败定位**：`trans-tools deps` 的错误会先于 `srun` 启动出现；`deps` 非 0 会直接中断 wrapper。
- **MPI 插件不匹配**：按集群 PMI 能力设置 `WRAPPERSRUN_SRUN_MPI`（如 `none` 或 `pmi2`），确保 wrapper 注入 `--mpi=<value>`。
