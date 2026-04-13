# gateway-api-migration fixtures

Structural fixtures for the `gateway-api-migration` skill. Each fixture is
a self-contained example with an `input/` tree (Ingress manifests the skill
reads) and an `expected/` tree (Gateway/HTTPRoute output the skill should
produce).

## Running the structural validator

```bash
bash tests/gateway-api-migration/run-fixtures.sh
```

This validator checks:
1. Every fixture has both `input/` and `expected/` directories.
2. Every `*.yaml` file parses as YAML.
3. Every `expected/common.gateway/base/kustomization.yaml` resolves its
   `resources:` entries to files that exist.
4. Every `expected/common.gateway/base/gateway.yaml` has `kind: Gateway`
   and `gatewayClassName: gke-l7-global-external-managed`.
5. Master/minion fixtures have expected HTTPRoute files with matching
   `parentRefs.sectionName` values pointing at the generated Gateway.

## Running end-to-end (manual)

The skill is AI-interpreted. To run end-to-end:

1. Copy a fixture's `input/` tree to a scratch directory.
2. Run `*gateway-migrate` in a Zeus session on the scratch directory.
3. Diff the produced `common.gateway/` + `common.service/overlays/*` against
   the fixture's `expected/` tree.

## Fixture index

| Name | Topology | What it exercises |
|---|---|---|
| standalone-simple | standalone | Baseline: one Ingress, one Service |
| standalone-cors | standalone | Rows 5-8 (CORS → GCPBackendPolicy) |
| standalone-server-snippet | standalone | Row 9a/b/c (server-snippet split) |
| master-minion-minimal | master/minion | 2-service master/minion, idempotent kustomization.yaml edit |
| master-minion-orphan-host | master/minion | Orphan host WARN path |
| master-minion-orphan-minion | master/minion | Orphan minion HALT path |
| mergeable-master | master/minion | Row 4 drop-info (mergeable-ingress-type) |
| eye-of-horus-sample | master/minion | Real-world trimmed sample |
