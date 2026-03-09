# Report Format Standard

All pipeline reports follow this format for consistency across agents and platforms.

## Per-Step YAML Record

Every pipeline step writes a YAML file to `docs/reports/YYYY-MM-DD/`.

### Common Fields

```yaml
step:
  number: <int>
  name: <string>
  type: discovery | exec | read
  executed_at: "YYYY-MM-DDTHH:MM:SSZ"
  status: PASS | FAIL | WARN | SKIP
  details: "<human-readable summary>"
```

### Type-Specific Fields

**exec**: `command`, `exit_code`, `output`, `files`, `error`, `skip_reason`
**read**: `total_modules`, `consistent`, `mismatched`, `modules[]`
**discovery**: `tf_dir`, `backend_type`, `tf_files_count`

## Final Markdown Report

Aggregates all step YAMLs into a human-readable summary.

### Rules

1. **Failed checks first** — full detail tables for FAIL steps
2. **Warnings second** — detail for WARN steps
3. **Passed checks last** — collapsed in `<details>` to reduce noise
4. **Auto-fix section** — list available fixes with counts
5. **Step YAML links** — reference per-step files for drill-down

### Overall Status Logic

- `PASS` — all steps PASS (0 FAIL, 0 WARN)
- `NEEDS ATTENTION` — 0 FAIL but 1+ WARN
- `FAIL` — 1+ FAIL

### Naming Convention

- Horus: `docs/reports/devops-horus-full-check-YYYY-MM-DD.md`
- Zeus: `docs/reports/devops-zeus-full-check-YYYY-MM-DD.md`
