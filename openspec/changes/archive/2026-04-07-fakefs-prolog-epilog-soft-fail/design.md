## Context

Current fakefs Slurm hook scripts run in prolog/epilog contexts where non-zero exit codes can be interpreted as hook failure and may trigger node drain policies. Existing cleanup paths are not explicitly constrained to preserve `/tmp/dependency` when a failure occurs, which makes postmortem diagnosis harder. The cluster operations requirement is to keep scheduling healthy (no drain caused by hook return code), keep failure evidence on disk, and retain actionable logs.

## Goals / Non-Goals

**Goals:**
- Ensure Slurm prolog and epilog invocations return exit code `0` after handled errors.
- Preserve `/tmp/dependency` whenever mount/cleanup flow enters an error path, and disallow cleanup-script deletion during failures.
- Persist error logs with stable fields (severity, reason code, job id, node id when available) for operator troubleshooting.
- Keep stricter behavior for non-Slurm/manual execution unless explicitly configured otherwise.

**Non-Goals:**
- Redesign fakefs mount architecture or dependency extraction format.
- Introduce external logging services or new runtime dependencies.
- Change successful-path cleanup semantics where no error occurred.

## Decisions

1. **Context-aware soft-fail gate for Slurm hooks**
   - Decision: Keep a Slurm-context detector (for example `SLURM_JOB_ID` presence) and force final exit code `0` in prolog/epilog error handlers.
   - Rationale: This directly prevents scheduler-side drain caused by hook script failures.
   - Alternative considered: Always exit `0` in all contexts. Rejected because it weakens local/manual validation and hides real failures during development.

2. **Error-preservation policy for `/tmp/dependency`**
   - Decision: Guard destructive cleanup calls behind success-state checks; if an error is detected, the cleanup script MUST NOT remove `/tmp/dependency`.
   - Rationale: Retaining artifacts improves root-cause analysis of mount and cleanup failures.
   - Alternative considered: Conditional retention via separate feature flag only. Rejected because operational requirement is explicit default preservation on error.

3. **Durable structured error logging**
   - Decision: Route all handled error branches through common logging helpers that emit severity and reason code plus Slurm context identifiers.
   - Rationale: Normalized log lines make triage and alert parsing consistent across mount and cleanup scripts.
   - Alternative considered: Ad-hoc `echo` statements per branch. Rejected due to inconsistent format and missing correlation fields.

## Risks / Trade-offs

- **[Risk]** Preserving `/tmp/dependency` on repeated failures can increase temporary storage usage.  
  **Mitigation:** Keep preservation only on error paths; maintain normal cleanup on success; document operator cleanup procedure.
- **[Risk]** Soft-fail can hide recurring hook issues from scheduler status alone.  
  **Mitigation:** Require explicit ERROR log records with reason codes and job context; rely on log monitoring.
- **[Risk]** Divergent behavior between Slurm and non-Slurm runs can confuse maintainers.  
  **Mitigation:** Keep context detection and behavior comments concise in script headers and tests.

## Migration Plan

1. Update both scripts to centralize error handling and logging behavior.
2. Add/refresh tests for Slurm error paths, directory retention, and exit codes.
3. Roll out in staging partition and inspect logs for one release cycle.
4. Roll back by restoring previous script versions if unexpected side effects appear.

## Open Questions

- Should preserved `/tmp/dependency` content be auto-pruned by a periodic maintenance job after a retention window?
- Should the log reason code taxonomy be standardized across other Slurm hook scripts now or in a follow-up change?
