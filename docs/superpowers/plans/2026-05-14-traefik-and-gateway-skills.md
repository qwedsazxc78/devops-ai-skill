# Traefik + Gateway API Migration Skills Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship `devops-ai-skill` v1.11.0 with two new skills (`nginx-to-traefik` skill A, `nginx-to-gateway` skill C orchestrator) and four additive enhancements to the existing `gateway-api-migration` skill (skill B), so operators can class-swap NGINX→Traefik, resource-swap NGINX→Gateway API, or chain both phases against one module.

**Architecture:** Three skills, three Zeus pipelines, no shared state file. Skill A converts NGINX Ingress to Traefik Ingress (class-swap), tightly coupled to eye-of-horus-gitops conventions via an operator-supplied env-config. Skill B (existing) gains a `--source-class` switch so its classifier accepts `ingressClassName: traefik` as first-class input, a `--no-redirect` flag to suppress the redundant `tls-redirect` HTTPRoute, and two new semantic checks. Skill C is a thin ~200-line orchestrator that invokes A then B with the right flags, writing a single chain `index.yaml` + `index.md` that links both sub-reports. The rename `gateway-api-migration` → `ingress-to-gateway` is **deferred to v2.0.0** and is not in scope here.

**Tech Stack:** Bash + Python 3 stdlib (with `yq` v4+), Markdown SKILL.md with YAML frontmatter, Kustomize, Traefik IngressRoute/Middleware CRDs and standard `networking.k8s.io/v1` Ingress with `ingressClassName: traefik`, GKE Gateway API (`gateway.networking.k8s.io/v1`), pnpm release tooling, Gemini TOML commands.

**Spec:** `docs/superpowers/specs/2026-05-14-traefik-and-gateway-skills-design.md` (commit `9bbc267`). The spec is the authoritative content source — many tasks reference specific sections to avoid duplication.

**External dependency:** The source slash command at `eye-of-horus-gitops/.claude/commands/gitops/nginx-to-traefik.md` is **not** checked out in this repo. Phase 1 derives skill A from the spec's §5 alone — invariants in §5.3, step flow in §5.2, state schema in §5.4. If the executor has access to that repo, treat it as supplementary; otherwise the spec is sufficient.

---

## File Structure

### New files (Phase 1 — Skill A: `nginx-to-traefik`)

```
skills/nginx-to-traefik/
  SKILL.md                                       Authoritative skill (~600 lines)
  references/
    nginx-to-traefik-env-config.md               Env-config template + operator prompts
    annotation-translation.md                    nginx → traefik annotation map
    dns-cutover-runbook.md                       The cutover playbook
  scripts/
    inventory_nginx_ingresses.py                 Per-env nginx Ingress inventory (JSON out)
    generate_traefik_ingress.py                  Emit <service>-traefik-ingress.yaml
    update_kustomization.py                      Idempotent edits to kustomization.yaml + app.ingress.yaml
    validate_cross_consistency.sh                4-way DNS↔verify↔ingress↔cert cross-check

prompts/zeus/
  nginx-to-traefik.md                            Thin pipeline (10 steps)

.gemini/commands/devops/pipelines/
  zeus-nginx-to-traefik.toml                     Gemini TOML entry

tests/nginx-to-traefik/
  README.md                                      Fixture usage
  run-fixtures.sh                                Structural validator
  fixtures/
    basic-three-services/
      input/common.service/overlays/dev/argocd-nginx-ingress.yaml
      input/common.service/overlays/dev/grafana-nginx-ingress.yaml
      input/common.service/overlays/dev/temporal-traefik-ingress.yaml   (already migrated)
      input/common.service/overlays/dev/kustomization.yaml
      input/common.traefik/overlays/dev/app.ingress.yaml
      input/scripts/dns-create-traefik.sh
      input/scripts/verify-traefik-dev.sh
      input/references/nginx-to-traefik-env-config.md
      expected/common.service/overlays/dev/argocd-traefik-ingress.yaml
      expected/common.service/overlays/dev/grafana-traefik-ingress.yaml
      expected/common.service/overlays/dev/kustomization.yaml
      expected/common.service/overlays/dev/archive/argocd-nginx-ingress.yaml
      expected/common.service/overlays/dev/archive/grafana-nginx-ingress.yaml
      expected/common.traefik/overlays/dev/app.ingress.yaml
    annotation-translation-cases/
      input/cert-manager-dns01-nginx-ingress.yaml
      input/impl-specific-path-nginx-ingress.yaml
      input/untranslatable-snippet-nginx-ingress.yaml
      expected/cert-manager-dns01-traefik-ingress.yaml
      expected/impl-specific-path-traefik-ingress.yaml
      expected/untranslatable-snippet-traefik-ingress.yaml     (with WARN markers)
    cross-consistency-stale-dns/
      input/...                                  Setup with a stale DNS entry
      expected_exit_code                         1
      expected_stderr_contains                   "stale host: <host>"
```

### New files (Phase 2 — Skill B enhancements; no rename in v1.11.0)

```
tests/gateway-api-migration/fixtures/traefik-source-minimal/
  input/common.service/overlays/dev/argocd-traefik-ingress.yaml
  input/common.service/overlays/dev/grafana-traefik-ingress.yaml
  input/common.service/overlays/dev/kustomization.yaml
  input/common.traefik/overlays/dev/app.ingress.yaml
  expected/common.gateway/base/gateway.yaml
  expected/common.service/overlays/dev/argocd-httproute.yaml
  expected/common.service/overlays/dev/grafana-httproute.yaml
  expected/common.service/overlays/dev/kustomization.yaml
tests/gateway-api-migration/fixtures/traefik-source-middleware-coverage-fail/
  input/...
  expected_check12_status                       fail
tests/gateway-api-migration/fixtures/traefik-source-redundant-redirect-warn/
  input/...
  expected_check13_status                       warn
```

### New files (Phase 3 — Skill C: `nginx-to-gateway`)

```
skills/nginx-to-gateway/
  SKILL.md                                       Orchestrator (~200 lines)
  references/
    chain-report-template.md                     index.md template

prompts/zeus/
  nginx-to-gateway.md                            Thin pipeline (6 gates)

.gemini/commands/devops/pipelines/
  zeus-nginx-to-gateway.toml

tests/nginx-to-gateway/
  README.md
  run-fixtures.sh
  fixtures/
    chain-happy-path/
      mocks/nginx-to-traefik                     Executable stub of skill A
      mocks/gateway-migrate                      Executable stub of skill B
    chain-phase-a-halt/
      mocks/nginx-to-traefik                     Stub that exits non-zero
```

### Modified files

```
skills/gateway-api-migration/SKILL.md                            +Invocation flags (--source-class, --source-state, --no-redirect)
skills/gateway-api-migration/scripts/classify_ingress.py         +sourceClass field, recognise ingressClassName=traefik
skills/gateway-api-migration/scripts/validate_generated.py       +check 12 traefik branch, +check 13 no-redundant-tls-redirect
skills/gateway-api-migration/references/annotation-map.md        +Traefik source annotation section
docs/PROJECT.md                                                  Add 2 skill rows + 2 Zeus command rows
CLAUDE.md                                                        Zeus table: +*nginx-to-traefik, +*nginx-to-gateway
AGENTS.md                                                        Same
GEMINI.md                                                        Same
README.md (en, zh-TW, zh-CN)                                     Skill table updates
VERSION                                                          → 1.11.0
package.json                                                     → 1.11.0
.claude-plugin/plugin.json                                       → 1.11.0 + 2 new skill entries
.claude-plugin/marketplace.json                                  → 1.11.0
.gemini/extensions/devops/gemini-extension.json                  → 1.11.0
tests/test-structure.sh                                          New skill registrations
CHANGELOG.md                                                     Entry for v1.11.0
```

---

## Phase 1 — Skill A: `nginx-to-traefik` (NEW)

Builds the class-swap skill. Tasks ordered so the operator can exercise scripts against fixtures before the SKILL.md narrative is written.

### Task 1.1: Create `references/nginx-to-traefik-env-config.md`

**Files:**
- Create: `skills/nginx-to-traefik/references/nginx-to-traefik-env-config.md`

- [x] **Step 1: Write the file**

```markdown
# nginx-to-traefik env config

This reference documents the **env-config snapshot** that the skill prompts
the operator to fill in on first run (step 0b). The file is consumed by
`generate_traefik_ingress.py` and written into `state.yaml.envConfig`.

## Layout (operator pastes this into the state file or supplies via prompts)

```yaml
envConfig:
  capturedAt: 2026-05-14T10:00:00Z
  envs:
    dev:
      nginxLbIp: "10.0.0.10"             # current nginx Service LB IP
      traefikLbIp: "10.0.0.20"           # new Traefik Service LB IP
      certIssuer: "letsencrypt-prod"
      managedCertNamespace: "traefik"
      managedCertResourceName: "app-managed-cert"
    stage:
      nginxLbIp: "10.0.1.10"
      traefikLbIp: "10.0.1.20"
      certIssuer: "letsencrypt-prod"
      managedCertNamespace: "traefik"
      managedCertResourceName: "app-managed-cert"
    prod:
      nginxLbIp: "10.0.2.10"
      traefikLbIp: "10.0.2.20"
      certIssuer: "letsencrypt-prod"
      managedCertNamespace: "traefik"
      managedCertResourceName: "app-managed-cert"
```

## Invariant

LB IPs **must** come from the operator's keyboard — never derived from
`common.ingress/overlays/<env>/app.service.yaml` or
`common.traefik/overlays/<env>/app.service.yaml`. The DNS cutover script
relies on these values being authoritative, and silently re-deriving them
from cluster state has caused historical incidents.

## Prompts the skill issues if values are missing

1. `Enter nginxLbIp for env=<env>:` (validate as IPv4)
2. `Enter traefikLbIp for env=<env>:` (validate as IPv4, must differ from nginxLbIp)
3. `Enter certIssuer name (default: letsencrypt-prod):`
4. `Enter managedCertNamespace (default: traefik):`
5. `Enter managedCertResourceName (default: app-managed-cert):`

After capture, write the snapshot back into `state.yaml.envConfig` and
also persist a one-line audit entry to `state.yaml.audit[]`.
```

- [x] **Step 2: Verify**

Run: `wc -l skills/nginx-to-traefik/references/nginx-to-traefik-env-config.md`
Expected: 30–60 lines.

- [x] **Step 3: Commit**

```bash
git add skills/nginx-to-traefik/references/nginx-to-traefik-env-config.md
git commit -m "$(cat <<'EOF'
docs(nginx-to-traefik): 新增 env-config snapshot 參考文件

定義 skill A 啟動時向操作者收集 LB IP、cert issuer 等
env 等級設定的格式與提示流程，並標記「LB IP 必須由人輸入」
這個來自歷史事故的不可違反規則。

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 1.2: Create `references/annotation-translation.md`

**Files:**
- Create: `skills/nginx-to-traefik/references/annotation-translation.md`

- [x] **Step 1: Write the file**

The file is the per-annotation rulebook for `generate_traefik_ingress.py`. Use this exact table — it is the authoritative knowledge the script reads against. Categories follow the same vocabulary as `docs/gateway/annotation-map.md` to keep operator mental model consistent.

```markdown
# nginx → Traefik Ingress Annotation Translation

Authoritative table for `*nginx-to-traefik` skill A. Every row is a
deterministic translation decision the converter makes every run.

| # | nginx annotation | Category | Traefik Ingress equivalent | Converter action |
|---|---|---|---|---|
| 1 | `kubernetes.io/ingress.class: nginx` | portable | `ingressClassName: traefik` on `spec` | Always rewrite |
| 2 | `nginx.ingress.kubernetes.io/ssl-redirect: "true"` | drop-info | Implicit via Traefik EntryPoint (`websecure` redirect) | Drop; INFO in state |
| 3 | `nginx.ingress.kubernetes.io/force-ssl-redirect: "true"` | drop-info | Same as row 2 | Drop; INFO in state |
| 4 | `nginx.ingress.kubernetes.io/backend-protocol: HTTPS` | convertible | `traefik.ingress.kubernetes.io/service.serversscheme: https` annotation | Translate |
| 5 | `nginx.ingress.kubernetes.io/proxy-body-size: 50m` | convertible-lossy | Middleware `buffering.maxRequestBodyBytes: 52428800` | WARN: unit conversion in report risk register |
| 6 | `nginx.ingress.kubernetes.io/cors-allow-origin: "*"` | convertible | Middleware `headers.accessControlAllowOriginList: ["*"]` | Reuse `cors@kubernetescrd` Middleware in `traefik` namespace if present; else stub |
| 7 | `nginx.ingress.kubernetes.io/configuration-snippet: <raw nginx>` | split-category (stub) | None — Traefik has no equivalent | Emit Traefik Ingress with TODO comment + WARN in report |
| 8 | `cert-manager.io/cluster-issuer: <name>` | portable | Same annotation | Carry through unchanged |
| 9 | `cert-manager.io/dns01-recursive-nameservers: <ns>` | portable | Same annotation | Carry through unchanged |
| 10 | `nginx.ingress.kubernetes.io/rewrite-target: <path>` | convertible | Middleware `replacePathRegex.replacement` | Translate (single-segment only); WARN otherwise |

## Category definitions

- **portable** — translates 1:1 with no information loss
- **convertible** — translates to a Traefik-specific resource/annotation
- **convertible-lossy** — translation drops information; WARN in report
- **drop-info** — annotation is obsolete under Traefik; drop silently with INFO in state
- **split-category (stub)** — cannot auto-convert; emit TODO + WARN

## Trade-offs called out in every Skill A report

1. **`configuration-snippet`** never translates — operators must rewrite the snippet as a Traefik Middleware manually.
2. **Body size limits** require unit conversion (`50m` → `52428800` bytes); always WARN to catch typos.
3. **CORS Middleware reuse**: if `cors@kubernetescrd` exists in the `traefik` namespace, skill A links to it; never regenerates.
```

- [x] **Step 2: Verify**

Run: `grep -c "^| " skills/nginx-to-traefik/references/annotation-translation.md`
Expected: at least 12 table rows (10 data + 2 header rows).

- [x] **Step 3: Commit**

```bash
git add skills/nginx-to-traefik/references/annotation-translation.md
git commit -m "$(cat <<'EOF'
docs(nginx-to-traefik): 新增 nginx→traefik 註解轉換對應表

定義 10 條 deterministic 轉換規則供 generate_traefik_ingress.py
作為唯一知識來源，包含類別、Traefik 對應做法、轉換器動作，
以及每份報告必須揭露的 3 個 trade-offs。

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 1.3: Create `references/dns-cutover-runbook.md`

**Files:**
- Create: `skills/nginx-to-traefik/references/dns-cutover-runbook.md`

- [x] **Step 1: Write the file**

Content sourced from spec §5.3 invariants + §7.7 cutover runbook (the first 6 steps are class-swap only). Structure:

1. H1 `# DNS Cutover Runbook — nginx-to-traefik (class swap)`
2. Preface paragraph: "This runbook is the operator-facing cutover script for skill A. The skill emits a link to this file at step 10. DNS is the only cutover lever — no LB IP changes, no nginx Ingress deletions."
3. H2 `## Pre-cutover invariants` — list spec §5.3 invariants verbatim.
4. H2 `## Cutover sequence`:
   1. Commit phase-A artifacts (Traefik Ingress files, archived nginx, updated `kustomization.yaml`, updated `app.ingress.yaml`, updated `dns-create-traefik.sh` / `verify-traefik-<env>.sh`).
   2. ArgoCD reconciles. Verify Traefik Ingresses live alongside nginx via `kubectl get ingress -A`.
   3. Run `verify-traefik-<env>.sh` with `--pre-cutover` to confirm Traefik serves traffic via `--resolve` overrides.
   4. Run `dns-create-traefik.sh <env>-<batch> --force` to flip DNS A-records to the Traefik LB IP.
   5. Run `verify-traefik-<env>.sh <env>-<batch> --post-cutover`.
   6. Soak period (operator-defined, suggested 24h+).
   7. Optional: archive or delete the nginx Ingress files (already moved to `archive/` by skill A).
5. H2 `## Rollback procedure`:
   - DNS only: re-run `dns-create-nginx.sh <env>-<batch>` (operator must keep this script in eye-of-horus-gitops).
   - Code: `git revert <commit-sha>` to restore the nginx file from `archive/`.
6. H2 `## Cross-links to skill C`:
   - "If this run is phase A of a chain, skill C records the cutover state in `docs/reports/nginx-to-gateway/<chain-slug>/index.yaml.phaseA.cutover`. After soak, run `*nginx-to-gateway <env> --skip-a` to start phase B."

Target length: ~120 lines.

- [x] **Step 2: Verify**

Run: `grep -c "^## " skills/nginx-to-traefik/references/dns-cutover-runbook.md`
Expected: 4 (Pre-cutover invariants, Cutover sequence, Rollback procedure, Cross-links to skill C).

- [x] **Step 3: Commit**

```bash
git add skills/nginx-to-traefik/references/dns-cutover-runbook.md
git commit -m "$(cat <<'EOF'
docs(nginx-to-traefik): 新增 DNS 切換 runbook

操作者面向的切換腳本，定義 7 步切換序列、回滾程序，
以及 chain 模式下與 skill C phaseA.cutover 狀態的連結點。

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 1.4: Create `scripts/inventory_nginx_ingresses.py`

**Files:**
- Create: `skills/nginx-to-traefik/scripts/inventory_nginx_ingresses.py`
- Test fixture: `tests/nginx-to-traefik/fixtures/basic-three-services/input/`

- [x] **Step 1: Write the fixture inputs (3 ingress files, kustomization, env-config)**

Create `tests/nginx-to-traefik/fixtures/basic-three-services/input/common.service/overlays/dev/argocd-nginx-ingress.yaml`:

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: argocd-server
  namespace: argocd
  annotations:
    kubernetes.io/ingress.class: nginx
    nginx.ingress.kubernetes.io/backend-protocol: HTTPS
    cert-manager.io/cluster-issuer: letsencrypt-prod
spec:
  tls:
  - hosts: ["argocd.dev.awoo.org"]
    secretName: argocd-server-tls
  rules:
  - host: argocd.dev.awoo.org
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: argocd-server
            port:
              number: 80
```

Create `tests/nginx-to-traefik/fixtures/basic-three-services/input/common.service/overlays/dev/grafana-nginx-ingress.yaml`:

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: grafana
  namespace: monitoring
  annotations:
    kubernetes.io/ingress.class: nginx
    cert-manager.io/cluster-issuer: letsencrypt-prod
spec:
  tls:
  - hosts: ["grafana.dev.awoo.org"]
    secretName: grafana-tls
  rules:
  - host: grafana.dev.awoo.org
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: grafana
            port:
              number: 3000
```

Create `tests/nginx-to-traefik/fixtures/basic-three-services/input/common.service/overlays/dev/temporal-traefik-ingress.yaml` (already migrated, should be skipped):

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: temporal-web
  namespace: temporal
spec:
  ingressClassName: traefik
  tls:
  - hosts: ["temporal.dev.awoo.org"]
    secretName: temporal-web-tls
  rules:
  - host: temporal.dev.awoo.org
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: temporal-web
            port:
              number: 8080
```

Create `tests/nginx-to-traefik/fixtures/basic-three-services/input/common.service/overlays/dev/kustomization.yaml`:

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
namespace: services
resources:
  - argocd-nginx-ingress.yaml
  - grafana-nginx-ingress.yaml
  - temporal-traefik-ingress.yaml
```

- [x] **Step 2: Write the failing test**

Create `tests/nginx-to-traefik/run-fixtures.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
INVENTORY="$ROOT_DIR/skills/nginx-to-traefik/scripts/inventory_nginx_ingresses.py"

PASS=0; FAIL=0

test_inventory_basic() {
  local fixture="$SCRIPT_DIR/fixtures/basic-three-services/input/common.service/overlays/dev"
  local actual
  actual=$(python3 "$INVENTORY" --overlay-dir "$fixture")
  local count
  count=$(echo "$actual" | jq '[.[] | select(.ingressClass == "nginx")] | length')
  if [[ "$count" == "2" ]]; then
    echo "  [PASS] inventory: 2 nginx ingresses (temporal skipped)"
    PASS=$((PASS+1))
  else
    echo "  [FAIL] inventory: expected 2 nginx ingresses, got $count"
    FAIL=$((FAIL+1))
  fi
}

test_inventory_basic

echo ""
echo "Total: $((PASS+FAIL)), Passed: $PASS, Failed: $FAIL"
[[ "$FAIL" == "0" ]]
```

Run: `chmod +x tests/nginx-to-traefik/run-fixtures.sh && tests/nginx-to-traefik/run-fixtures.sh`
Expected: FAIL with `python3: can't open file '.../inventory_nginx_ingresses.py'`.

- [x] **Step 3: Implement `inventory_nginx_ingresses.py`**

Create `skills/nginx-to-traefik/scripts/inventory_nginx_ingresses.py`:

```python
#!/usr/bin/env python3
"""
inventory_nginx_ingresses.py — list active nginx Ingresses in an overlay.

Scans an overlay directory for `kind: Ingress` documents and emits a JSON
array (single document on stdout) with one entry per Ingress:

  [{
    "file": "argocd-nginx-ingress.yaml",
    "name": "argocd-server",
    "namespace": "argocd",
    "ingressClass": "nginx" | "traefik" | null,
    "hosts": ["argocd.dev.awoo.org"],
    "backendServices": [{"service": "argocd-server", "port": 80}],
    "annotations": {"key": "value", ...}
  }, ...]

Already-migrated Traefik ingresses are emitted but flagged
`ingressClass == "traefik"` so the caller can filter.

Usage:
    inventory_nginx_ingresses.py --overlay-dir <path>
"""
from __future__ import annotations

import argparse
import json
import shutil
import subprocess
import sys
from pathlib import Path


def _yq_ea_json(path: Path) -> list[dict]:
    rc = subprocess.run(
        ["yq", "ea", "-o=json", "[.]", str(path)],
        capture_output=True, text=True,
    )
    if rc.returncode != 0:
        return []
    try:
        data = json.loads(rc.stdout or "[]")
    except json.JSONDecodeError:
        return []
    out: list[dict] = []
    if isinstance(data, list):
        for elem in data:
            if isinstance(elem, list):
                out.extend(d for d in elem if isinstance(d, dict))
            elif isinstance(elem, dict):
                out.append(elem)
    elif isinstance(data, dict):
        out.append(data)
    return out


def _ingress_class(doc: dict) -> str | None:
    ann = (doc.get("metadata") or {}).get("annotations") or {}
    spec = doc.get("spec") or {}
    return ann.get("kubernetes.io/ingress.class") or spec.get("ingressClassName")


def _extract(doc: dict, file: Path) -> dict:
    md = doc.get("metadata") or {}
    spec = doc.get("spec") or {}
    rules = spec.get("rules") or []
    backends: list[dict] = []
    for rule in rules:
        for p in (rule.get("http") or {}).get("paths", []) or []:
            svc = ((p.get("backend") or {}).get("service") or {})
            if svc.get("name"):
                backends.append({
                    "service": svc.get("name"),
                    "port": (svc.get("port") or {}).get("number"),
                })
    return {
        "file": file.name,
        "name": md.get("name"),
        "namespace": md.get("namespace"),
        "ingressClass": _ingress_class(doc),
        "hosts": [r["host"] for r in rules if "host" in r],
        "backendServices": backends,
        "annotations": md.get("annotations") or {},
    }


def main() -> int:
    p = argparse.ArgumentParser()
    p.add_argument("--overlay-dir", required=True, type=Path)
    args = p.parse_args()
    if not shutil.which("yq"):
        print("[inventory_nginx_ingresses] yq not found on PATH", file=sys.stderr)
        return 2
    if not args.overlay_dir.is_dir():
        print(f"[inventory_nginx_ingresses] not a directory: {args.overlay_dir}", file=sys.stderr)
        return 2
    rows: list[dict] = []
    for yaml in sorted(args.overlay_dir.glob("*.yaml")):
        for doc in _yq_ea_json(yaml):
            if doc.get("kind") == "Ingress":
                rows.append(_extract(doc, yaml))
    json.dump(rows, sys.stdout, ensure_ascii=False, indent=2)
    sys.stdout.write("\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
```

- [x] **Step 4: Run the test and verify PASS**

Run: `tests/nginx-to-traefik/run-fixtures.sh`
Expected: `[PASS] inventory: 2 nginx ingresses (temporal skipped)`.

- [x] **Step 5: Commit**

```bash
git add skills/nginx-to-traefik/scripts/inventory_nginx_ingresses.py tests/nginx-to-traefik/
git commit -m "$(cat <<'EOF'
feat(nginx-to-traefik): 新增 inventory 腳本與 basic fixture

inventory_nginx_ingresses.py 掃描 overlay 目錄列出所有 Ingress
並標記 ingressClass，讓 SKILL.md 步驟 1 可直接 filter 出待轉換的
nginx 條目；basic-three-services fixture 確認已遷移的 Traefik
條目會被回報但不重複處理。

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 1.5: Create `scripts/generate_traefik_ingress.py`

**Files:**
- Create: `skills/nginx-to-traefik/scripts/generate_traefik_ingress.py`
- Test fixture: `tests/nginx-to-traefik/fixtures/basic-three-services/expected/` (Traefik ingress files)

- [x] **Step 1: Write expected outputs in fixture**

Create `tests/nginx-to-traefik/fixtures/basic-three-services/expected/common.service/overlays/dev/argocd-traefik-ingress.yaml`:

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: argocd-server
  namespace: argocd
  annotations:
    cert-manager.io/cluster-issuer: letsencrypt-prod
    traefik.ingress.kubernetes.io/service.serversscheme: https
spec:
  ingressClassName: traefik
  tls:
  - hosts: ["argocd.dev.awoo.org"]
    secretName: argocd-server-tls
  rules:
  - host: argocd.dev.awoo.org
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: argocd-server
            port:
              number: 80
```

Create `tests/nginx-to-traefik/fixtures/basic-three-services/expected/common.service/overlays/dev/grafana-traefik-ingress.yaml`:

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: grafana
  namespace: monitoring
  annotations:
    cert-manager.io/cluster-issuer: letsencrypt-prod
spec:
  ingressClassName: traefik
  tls:
  - hosts: ["grafana.dev.awoo.org"]
    secretName: grafana-tls
  rules:
  - host: grafana.dev.awoo.org
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: grafana
            port:
              number: 3000
```

- [x] **Step 2: Write the failing test (extend `run-fixtures.sh`)**

Add to `tests/nginx-to-traefik/run-fixtures.sh` before `echo "Total..."`:

```bash
test_generate_basic() {
  local fixture_in="$SCRIPT_DIR/fixtures/basic-three-services/input/common.service/overlays/dev/argocd-nginx-ingress.yaml"
  local fixture_exp="$SCRIPT_DIR/fixtures/basic-three-services/expected/common.service/overlays/dev/argocd-traefik-ingress.yaml"
  local tmpdir; tmpdir=$(mktemp -d)
  python3 "$ROOT_DIR/skills/nginx-to-traefik/scripts/generate_traefik_ingress.py" \
    --input "$fixture_in" --output "$tmpdir/argocd-traefik-ingress.yaml"
  # Normalise both files through yq before diff to ignore key-order drift
  if diff -u <(yq -P . "$fixture_exp") <(yq -P . "$tmpdir/argocd-traefik-ingress.yaml") >/dev/null; then
    echo "  [PASS] generate argocd: matches expected"
    PASS=$((PASS+1))
  else
    echo "  [FAIL] generate argocd: differs from expected"
    diff -u <(yq -P . "$fixture_exp") <(yq -P . "$tmpdir/argocd-traefik-ingress.yaml") || true
    FAIL=$((FAIL+1))
  fi
  rm -rf "$tmpdir"
}

test_generate_basic
```

Run: `tests/nginx-to-traefik/run-fixtures.sh`
Expected: FAIL (script missing).

- [x] **Step 3: Implement `generate_traefik_ingress.py`**

Create `skills/nginx-to-traefik/scripts/generate_traefik_ingress.py`:

```python
#!/usr/bin/env python3
"""
generate_traefik_ingress.py — emit a Traefik Ingress from a source nginx Ingress.

Reads one Ingress document from --input, applies the translation rules from
references/annotation-translation.md, and writes the Traefik Ingress to
--output. Returns warnings on stderr (JSON lines).

Translation rules (see references/annotation-translation.md):
  Row 1  kubernetes.io/ingress.class: nginx → ingressClassName: traefik
  Row 2-3 ssl-redirect / force-ssl-redirect → DROP (info)
  Row 4  backend-protocol: HTTPS → service.serversscheme annotation
  Row 5  proxy-body-size → WARN, emit stub Middleware reference comment
  Row 6  cors-allow-origin → reuse cors@kubernetescrd Middleware if present, else stub + WARN
  Row 7  configuration-snippet → TODO comment + WARN
  Row 8-9 cert-manager.io/* → carry through
  Row 10 rewrite-target → translate single-segment; WARN otherwise

Usage:
    generate_traefik_ingress.py --input <nginx-ingress.yaml> --output <traefik-ingress.yaml>
"""
from __future__ import annotations

import argparse
import json
import subprocess
import sys
from pathlib import Path

DROP = {
    "kubernetes.io/ingress.class",
    "nginx.ingress.kubernetes.io/ssl-redirect",
    "nginx.ingress.kubernetes.io/force-ssl-redirect",
}
CARRY = {
    "cert-manager.io/cluster-issuer",
    "cert-manager.io/dns01-recursive-nameservers",
}


def _load(path: Path) -> dict:
    rc = subprocess.run(["yq", "ea", "-o=json", ".", str(path)], capture_output=True, text=True)
    if rc.returncode != 0:
        sys.stderr.write(rc.stderr)
        sys.exit(2)
    return json.loads(rc.stdout or "{}")


def _warn(msg: str) -> None:
    sys.stderr.write(json.dumps({"level": "WARN", "msg": msg}) + "\n")


def _translate_annotations(src: dict) -> tuple[dict, list[str]]:
    out: dict[str, str] = {}
    warns: list[str] = []
    for k, v in (src or {}).items():
        if k in DROP:
            continue
        if k in CARRY:
            out[k] = v
            continue
        if k == "nginx.ingress.kubernetes.io/backend-protocol" and v.upper() == "HTTPS":
            out["traefik.ingress.kubernetes.io/service.serversscheme"] = "https"
            continue
        if k == "nginx.ingress.kubernetes.io/proxy-body-size":
            warns.append(f"proxy-body-size={v} requires manual Middleware (buffering)")
            continue
        if k == "nginx.ingress.kubernetes.io/cors-allow-origin":
            warns.append(f"cors-allow-origin={v}: reuse cors@kubernetescrd Middleware (no auto-generation)")
            continue
        if k == "nginx.ingress.kubernetes.io/configuration-snippet":
            warns.append("configuration-snippet does not translate; emit Middleware manually")
            out[f"# TODO: {k}"] = v
            continue
        if k == "nginx.ingress.kubernetes.io/rewrite-target":
            if v.count("/") <= 1:
                warns.append(f"rewrite-target={v}: emit Middleware replacePathRegex manually")
            else:
                warns.append(f"rewrite-target={v}: multi-segment, manual review required")
            continue
        warns.append(f"unrecognised annotation dropped: {k}={v}")
    return out, warns


def _build_traefik(src: dict) -> dict:
    md = (src.get("metadata") or {}).copy()
    annotations, warns = _translate_annotations((md.get("annotations") or {}))
    for w in warns:
        _warn(w)
    md["annotations"] = annotations
    spec = (src.get("spec") or {}).copy()
    spec.pop("ingressClassName", None)
    new_spec = {"ingressClassName": "traefik"}
    for k in ("tls", "rules"):
        if k in spec:
            new_spec[k] = spec[k]
    return {
        "apiVersion": "networking.k8s.io/v1",
        "kind": "Ingress",
        "metadata": md,
        "spec": new_spec,
    }


def _write_yaml(doc: dict, out: Path) -> None:
    rc = subprocess.run(
        ["yq", "-P", "."],
        input=json.dumps(doc), capture_output=True, text=True,
    )
    if rc.returncode != 0:
        sys.stderr.write(rc.stderr)
        sys.exit(2)
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(rc.stdout)


def main() -> int:
    p = argparse.ArgumentParser()
    p.add_argument("--input", required=True, type=Path)
    p.add_argument("--output", required=True, type=Path)
    args = p.parse_args()
    src = _load(args.input)
    if src.get("kind") != "Ingress":
        print("[generate_traefik_ingress] input is not an Ingress", file=sys.stderr)
        return 2
    out = _build_traefik(src)
    _write_yaml(out, args.output)
    return 0


if __name__ == "__main__":
    sys.exit(main())
```

- [x] **Step 4: Run the test and verify PASS**

Run: `tests/nginx-to-traefik/run-fixtures.sh`
Expected: `[PASS] generate argocd: matches expected`.

- [x] **Step 5: Commit**

```bash
git add skills/nginx-to-traefik/scripts/generate_traefik_ingress.py tests/nginx-to-traefik/fixtures/basic-three-services/expected/
git commit -m "$(cat <<'EOF'
feat(nginx-to-traefik): 新增 generate_traefik_ingress 與 expected fixture

實作 annotation-translation.md 10 條規則的轉換器，輸出
ingressClassName: traefik 的 Ingress YAML，並對 lossy/未知註解
寫入 WARN JSON Lines 到 stderr，供 SKILL.md 步驟 3 收集。

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 1.6: Create `scripts/update_kustomization.py`

**Files:**
- Create: `skills/nginx-to-traefik/scripts/update_kustomization.py`

- [x] **Step 1: Add fixture for idempotent kustomization edit**

Create `tests/nginx-to-traefik/fixtures/basic-three-services/expected/common.service/overlays/dev/kustomization.yaml`:

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
namespace: services
resources:
  - argocd-traefik-ingress.yaml
  - grafana-traefik-ingress.yaml
  - temporal-traefik-ingress.yaml
```

Also create the archive subdirectory fixture files (`archive/argocd-nginx-ingress.yaml`, `archive/grafana-nginx-ingress.yaml`) as exact copies of the input nginx files.

- [x] **Step 2: Write the failing test**

Add to `tests/nginx-to-traefik/run-fixtures.sh`:

```bash
test_update_kustomization_idempotent() {
  local tmpdir; tmpdir=$(mktemp -d)
  cp -r "$SCRIPT_DIR/fixtures/basic-three-services/input/common.service" "$tmpdir/"
  # First run: replace nginx → traefik resource entries
  python3 "$ROOT_DIR/skills/nginx-to-traefik/scripts/update_kustomization.py" \
    --overlay-dir "$tmpdir/common.service/overlays/dev" \
    --replace "argocd-nginx-ingress.yaml=argocd-traefik-ingress.yaml" \
    --replace "grafana-nginx-ingress.yaml=grafana-traefik-ingress.yaml"
  local after_first
  after_first=$(cat "$tmpdir/common.service/overlays/dev/kustomization.yaml")
  # Second run: same flags → no-op (idempotency)
  python3 "$ROOT_DIR/skills/nginx-to-traefik/scripts/update_kustomization.py" \
    --overlay-dir "$tmpdir/common.service/overlays/dev" \
    --replace "argocd-nginx-ingress.yaml=argocd-traefik-ingress.yaml" \
    --replace "grafana-nginx-ingress.yaml=grafana-traefik-ingress.yaml"
  local after_second
  after_second=$(cat "$tmpdir/common.service/overlays/dev/kustomization.yaml")
  if [[ "$after_first" == "$after_second" ]]; then
    echo "  [PASS] update_kustomization: idempotent"
    PASS=$((PASS+1))
  else
    echo "  [FAIL] update_kustomization: second run produced different output"
    diff <(echo "$after_first") <(echo "$after_second") || true
    FAIL=$((FAIL+1))
  fi
  rm -rf "$tmpdir"
}

test_update_kustomization_idempotent
```

Run: `tests/nginx-to-traefik/run-fixtures.sh`
Expected: FAIL (script missing).

- [x] **Step 3: Implement `update_kustomization.py`**

Create `skills/nginx-to-traefik/scripts/update_kustomization.py`:

```python
#!/usr/bin/env python3
"""
update_kustomization.py — idempotent kustomization.yaml edits for skill A.

Two operations:

  --replace OLD=NEW   In `resources:`, replace entry OLD with NEW. If NEW is
                      already present (and OLD is absent), no-op.
  --drop-patch FILE   Drop FILE from `patches:`. If absent, no-op.
  --add-host HOST     Append HOST to common.traefik/overlays/<env>/app.ingress.yaml
                      managed-cert host list. If HOST already present, no-op.

Usage:
    update_kustomization.py --overlay-dir <path> [--replace OLD=NEW]... [--drop-patch FILE]
    update_kustomization.py --app-ingress <path> [--add-host HOST]...
"""
from __future__ import annotations

import argparse
import sys
from pathlib import Path
import subprocess


def _yq(expr: str, file: Path) -> None:
    rc = subprocess.run(["yq", "-i", expr, str(file)], capture_output=True, text=True)
    if rc.returncode != 0:
        sys.stderr.write(rc.stderr)
        sys.exit(2)


def _yq_eval(expr: str, file: Path) -> str:
    rc = subprocess.run(["yq", "-r", expr, str(file)], capture_output=True, text=True)
    if rc.returncode != 0:
        sys.stderr.write(rc.stderr)
        sys.exit(2)
    return rc.stdout.strip()


def replace_resource(kfile: Path, old: str, new: str) -> None:
    has_new = _yq_eval(f'.resources | contains(["{new}"])', kfile) == "true"
    has_old = _yq_eval(f'.resources | contains(["{old}"])', kfile) == "true"
    if has_new and not has_old:
        return
    _yq(f'(.resources[] | select(. == "{old}")) |= "{new}"', kfile)
    _yq('.resources |= unique', kfile)


def drop_patch(kfile: Path, fname: str) -> None:
    has_patch = _yq_eval(f'(.patches // []) | map(.path // "") | contains(["{fname}"])', kfile) == "true"
    if not has_patch:
        return
    _yq(f'(.patches //= []) | del(.patches[] | select(.path == "{fname}"))', kfile)


def add_host(app_ingress: Path, host: str) -> None:
    has_host = _yq_eval(
        f'(.spec.rules // []) | map(.host) | contains(["{host}"])', app_ingress
    ) == "true"
    if has_host:
        return
    _yq(f'.spec.rules += [{{"host": "{host}"}}]', app_ingress)


def main() -> int:
    p = argparse.ArgumentParser()
    p.add_argument("--overlay-dir", type=Path)
    p.add_argument("--app-ingress", type=Path)
    p.add_argument("--replace", action="append", default=[])
    p.add_argument("--drop-patch", action="append", default=[])
    p.add_argument("--add-host", action="append", default=[])
    args = p.parse_args()

    if args.overlay_dir:
        kfile = args.overlay_dir / "kustomization.yaml"
        if not kfile.is_file():
            print(f"[update_kustomization] not found: {kfile}", file=sys.stderr)
            return 2
        for spec in args.replace:
            if "=" not in spec:
                print(f"[update_kustomization] --replace expects OLD=NEW, got {spec!r}", file=sys.stderr)
                return 2
            old, new = spec.split("=", 1)
            replace_resource(kfile, old, new)
        for fname in args.drop_patch:
            drop_patch(kfile, fname)

    if args.app_ingress:
        if not args.app_ingress.is_file():
            print(f"[update_kustomization] not found: {args.app_ingress}", file=sys.stderr)
            return 2
        for host in args.add_host:
            add_host(args.app_ingress, host)

    return 0


if __name__ == "__main__":
    sys.exit(main())
```

- [x] **Step 4: Run the test and verify PASS**

Run: `tests/nginx-to-traefik/run-fixtures.sh`
Expected: `[PASS] update_kustomization: idempotent`.

- [x] **Step 5: Commit**

```bash
git add skills/nginx-to-traefik/scripts/update_kustomization.py tests/nginx-to-traefik/
git commit -m "$(cat <<'EOF'
feat(nginx-to-traefik): 新增 update_kustomization 與冪等性測試

提供 --replace / --drop-patch / --add-host 三個冪等操作，
SKILL.md 步驟 5、6 直接呼叫。第二次以相同參數執行必為 no-op，
fixture 測試覆蓋此性質。

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 1.7: Create `scripts/validate_cross_consistency.sh`

**Files:**
- Create: `skills/nginx-to-traefik/scripts/validate_cross_consistency.sh`
- Test fixture: `tests/nginx-to-traefik/fixtures/cross-consistency-stale-dns/`

The script reads the same host lists the operator-owned `dns-create-traefik.sh` and `verify-traefik-<env>.sh` declare, but to avoid sourcing those scripts (and the risk of `eval` or side effects) it parses them as plain text using `grep`/`awk`. This keeps the verification step a read-only static check.

- [x] **Step 1: Write fixture with a stale DNS entry**

Create `tests/nginx-to-traefik/fixtures/cross-consistency-stale-dns/input/scripts/dns-create-traefik.sh`:

```bash
#!/usr/bin/env bash
# Stub of eye-of-horus-gitops dns script — only the host list matters for tests
HOSTS_DEV_B1=(
  "argocd.dev.awoo.org"
  "grafana.dev.awoo.org"
  "stale.dev.awoo.org"
)
```

Create `tests/nginx-to-traefik/fixtures/cross-consistency-stale-dns/input/scripts/verify-traefik-dev.sh`:

```bash
#!/usr/bin/env bash
URLS_DEV_B1=(
  "https://argocd.dev.awoo.org/"
  "https://grafana.dev.awoo.org/"
)
```

Create the two Traefik ingress files (argocd, grafana — hosts only, matching) and `common.traefik/overlays/dev/app.ingress.yaml` (TLS hosts: argocd, grafana — no `stale`).

- [x] **Step 2: Write the failing test**

Add to `tests/nginx-to-traefik/run-fixtures.sh`:

```bash
test_cross_consistency_detects_stale_dns() {
  local fdir="$SCRIPT_DIR/fixtures/cross-consistency-stale-dns/input"
  set +e
  local out
  out=$("$ROOT_DIR/skills/nginx-to-traefik/scripts/validate_cross_consistency.sh" \
    --env dev --batch b1 \
    --dns-script "$fdir/scripts/dns-create-traefik.sh" \
    --verify-script "$fdir/scripts/verify-traefik-dev.sh" \
    --ingress-dir "$fdir/common.service/overlays/dev" \
    --app-ingress "$fdir/common.traefik/overlays/dev/app.ingress.yaml" 2>&1)
  local rc=$?
  set -e
  if [[ "$rc" != "0" ]] && [[ "$out" == *"stale.dev.awoo.org"* ]]; then
    echo "  [PASS] cross-consistency: stale host detected"
    PASS=$((PASS+1))
  else
    echo "  [FAIL] cross-consistency: rc=$rc out=$out"
    FAIL=$((FAIL+1))
  fi
}

test_cross_consistency_detects_stale_dns
```

Run: `tests/nginx-to-traefik/run-fixtures.sh`
Expected: FAIL (script missing).

- [x] **Step 3: Implement `validate_cross_consistency.sh`**

The script parses the source bash arrays statically (via `awk`) rather than `source`-ing them, so external scripts cannot inject side effects. It does not use `eval`.

Create `skills/nginx-to-traefik/scripts/validate_cross_consistency.sh`:

```bash
#!/usr/bin/env bash
# validate_cross_consistency.sh — 4-way cross-check for nginx-to-traefik.
#
# Statically parses the host arrays declared in:
#   1. <dns-script>            : HOSTS_<ENV>_<BATCH>=( "host" "host" ... )
#   2. <verify-script>         : URLS_<ENV>_<BATCH>=( "https://host/" ... )
#   3. <ingress-dir>/*-traefik-ingress.yaml  via yq
#   4. <app-ingress>           : .spec.tls[].hosts[]    via yq
#
# Reports any host appearing in fewer than all 4 sources. Exit non-zero on
# divergence. No `source`, no `eval` — the dns/verify scripts may be
# arbitrary operator-supplied bash and must be treated as untrusted text.
#
# Usage:
#   validate_cross_consistency.sh --env dev --batch b1 \
#     --dns-script SCRIPT --verify-script SCRIPT \
#     --ingress-dir DIR --app-ingress FILE

set -euo pipefail

ENV=""; BATCH=""; DNS_SCRIPT=""; VERIFY_SCRIPT=""
INGRESS_DIR=""; APP_INGRESS=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --env) ENV="$2"; shift 2 ;;
    --batch) BATCH="$2"; shift 2 ;;
    --dns-script) DNS_SCRIPT="$2"; shift 2 ;;
    --verify-script) VERIFY_SCRIPT="$2"; shift 2 ;;
    --ingress-dir) INGRESS_DIR="$2"; shift 2 ;;
    --app-ingress) APP_INGRESS="$2"; shift 2 ;;
    *) echo "Unknown arg: $1" >&2; exit 2 ;;
  esac
done

env_upper="$(printf '%s' "$ENV" | tr '[:lower:]' '[:upper:]')"
batch_upper="$(printf '%s' "$BATCH" | tr '[:lower:]' '[:upper:]')"
hosts_var="HOSTS_${env_upper}_${batch_upper}"
urls_var="URLS_${env_upper}_${batch_upper}"

# Extract a bash array literal `NAME=( "a" "b" ... )` as one host per line.
# awk reads the file as plain text — no sourcing, no command execution.
extract_array() {
  local var="$1" file="$2"
  awk -v var="$var" '
    $0 ~ "^" var "=\\(" { inside=1; sub("^" var "=\\(", ""); }
    inside {
      gsub(/[()"\\\047]/, "", $0)
      n = split($0, toks, /[[:space:]]+/)
      for (i=1; i<=n; i++) if (toks[i] != "") print toks[i]
      if ($0 ~ /\)/) { exit }
    }
  ' "$file"
}

mapfile -t dns_hosts < <(extract_array "$hosts_var" "$DNS_SCRIPT")
mapfile -t verify_raw < <(extract_array "$urls_var" "$VERIFY_SCRIPT")
verify_hosts=()
for u in "${verify_raw[@]}"; do
  h="${u#https://}"; h="${h#http://}"; h="${h%%/*}"
  [[ -n "$h" ]] && verify_hosts+=("$h")
done

ingress_hosts=()
shopt -s nullglob
for f in "$INGRESS_DIR"/*-traefik-ingress.yaml; do
  while IFS= read -r h; do
    [[ -n "$h" && "$h" != "null" ]] && ingress_hosts+=("$h")
  done < <(yq -r '.spec.rules[].host' "$f" 2>/dev/null || true)
done
shopt -u nullglob

cert_hosts=()
while IFS= read -r h; do
  [[ -n "$h" && "$h" != "null" ]] && cert_hosts+=("$h")
done < <(yq -r '.spec.tls[].hosts[]' "$APP_INGRESS" 2>/dev/null || true)

declare -A presence
for h in "${dns_hosts[@]}";     do presence["$h"]+="D"; done
for h in "${verify_hosts[@]}";  do presence["$h"]+="V"; done
for h in "${ingress_hosts[@]}"; do presence["$h"]+="I"; done
for h in "${cert_hosts[@]}";    do presence["$h"]+="C"; done

bad=0
for h in "${!presence[@]}"; do
  marks="${presence[$h]}"
  missing=""
  [[ "$marks" != *D* ]] && missing+="dns "
  [[ "$marks" != *V* ]] && missing+="verify "
  [[ "$marks" != *I* ]] && missing+="ingress "
  [[ "$marks" != *C* ]] && missing+="cert "
  if [[ -n "$missing" ]]; then
    echo "stale host: $h (missing from: $missing)" >&2
    bad=1
  fi
done

exit "$bad"
```

Make it executable: `chmod +x skills/nginx-to-traefik/scripts/validate_cross_consistency.sh`

- [x] **Step 4: Run the test and verify PASS**

Run: `tests/nginx-to-traefik/run-fixtures.sh`
Expected: `[PASS] cross-consistency: stale host detected`.

- [x] **Step 5: Commit**

```bash
git add skills/nginx-to-traefik/scripts/validate_cross_consistency.sh tests/nginx-to-traefik/fixtures/cross-consistency-stale-dns/
git commit -m "$(cat <<'EOF'
feat(nginx-to-traefik): 新增 4-way cross-consistency 檢查

驗證 DNS、verify、Traefik Ingress、managed-cert 四處的 host 集合
完全一致；任一處遺漏即 exit non-zero 並 stderr 印出 stale host。
使用 awk 靜態解析 bash 陣列，不 source 也不 eval 操作者腳本。
SKILL.md 步驟 7b 直接呼叫。

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 1.8: Write `SKILL.md` for `nginx-to-traefik`

**Files:**
- Create: `skills/nginx-to-traefik/SKILL.md`

- [x] **Step 1: Write the SKILL.md frontmatter and overview (top ~80 lines)**

```markdown
---
name: nginx-to-traefik
description: >
  Class-swap migration that ports services from NGINX Ingress to Traefik
  Ingress (`ingressClassName: traefik`) while keeping both controllers
  running in parallel. DNS A-records are the only cutover lever. Designed
  for eye-of-horus-gitops conventions: nginx files move to archive/ (never
  deleted), Traefik Ingresses live in kustomization.resources (never
  patches), backend Service names and secretName are written verbatim
  (Kustomize namePrefix does not touch them). Operator-declared LB IPs
  only — never auto-derived from cluster state. State stored in
  docs/reports/nginx-to-traefik/<slug>/.
version: "1.0.0"
---

# nginx-to-traefik Skill

Invoked by Zeus pipeline `*nginx-to-traefik`.

This skill is the **first half** of the chained migration NGINX → Traefik
Ingress → Gateway API. Used standalone it ports a batch of services to
Traefik while leaving the NGINX controller serving everyone else. Used
under skill `nginx-to-gateway` (the orchestrator), its `state.yaml` output
is consumed as the input to skill `gateway-api-migration` with
`--source-class traefik`.

## Canonical references

| File | When to read |
|---|---|
| `references/nginx-to-traefik-env-config.md` | Step 0b — env-config schema and operator prompts |
| `references/annotation-translation.md` | Step 3 — annotation mapping |
| `references/dns-cutover-runbook.md` | Step 10 — printed/linked at end of run |

## Bundled scripts

| Script | Used by | Purpose |
|---|---|---|
| `scripts/inventory_nginx_ingresses.py` | Step 1 | Per-overlay nginx Ingress inventory |
| `scripts/generate_traefik_ingress.py` | Step 3 | Emit `<service>-traefik-ingress.yaml` |
| `scripts/update_kustomization.py` | Step 5, 6 | Idempotent edits to kustomization.yaml + app.ingress.yaml |
| `scripts/validate_cross_consistency.sh` | Step 7b | 4-way DNS↔verify↔ingress↔cert cross-check |

## Activation

Triggered explicitly by `*nginx-to-traefik` from Zeus. Not auto-triggered.

## Invocation forms

```
*nginx-to-traefik                              # interactive: inventory + propose batches
*nginx-to-traefik <env>                        # process all services in one env
*nginx-to-traefik <env> <batch>                # named batch (b1 | b2)
*nginx-to-traefik <env> <service>              # single service
*nginx-to-traefik --resume                     # continue from state.yaml
```
```

- [x] **Step 2: Write the Step Flow section (steps 0–10)**

Append this section. The 11-row step table is the **authoritative spec §5.2**; the body below it explains halts, state writes, and the operator-facing behaviour each step exhibits.

```markdown
## Step Flow

| Step | Action | Script |
|---|---|---|
| 0 | Tool check (`kustomize`, `yq`, `git`) | inline `command -v` |
| 0b | Load `references/nginx-to-traefik-env-config.md`; prompt operator for Traefik + nginx LB IPs if missing, write to config, then continue | inline |
| 1 | Inventory active nginx ingresses per env | `inventory_nginx_ingresses.py` |
| 2 | Propose batch plan, wait for `y/N` confirmation | inline |
| 3 | Generate `<service>-traefik-ingress.yaml` per service | `generate_traefik_ingress.py` |
| 4 | `git mv` nginx file to `archive/` | inline |
| 5 | Edit `kustomization.yaml`: add Traefik file to `resources:`, drop nginx from `patches:` | `update_kustomization.py` |
| 6 | Update `common.traefik/overlays/<env>/app.ingress.yaml` managed-cert host list | `update_kustomization.py` |
| 7 | `kustomize build` both modules for the env | inline |
| 7b | 4-way consistency check | `validate_cross_consistency.sh` |
| 8 | Update `scripts/dns-create-traefik.sh` batch list | inline |
| 9 | Update `scripts/verify-traefik-<env>.sh` URL list | inline |
| 10 | Print commit message + file list (never auto-commit) | inline |

### Step 0 — Tool check

Run `command -v kustomize yq git`. HALT on any missing.

### Step 0b — Env-config

Read `references/nginx-to-traefik-env-config.md`. If `state.yaml.envConfig`
is missing entries for the target env, issue the 5 prompts listed in the
reference and write the captured values back. Never derive LB IPs from
any cluster resource — this is invariant §5.3 from the spec.

### Step 1 — Inventory

Invoke `inventory_nginx_ingresses.py --overlay-dir
<common.service/overlays/<env>>`. Filter to `ingressClass == "nginx"`.
Write to `state.yaml.inventory[]`. HALT if zero nginx ingresses found.

### Step 2 — Batch plan

Group inventory entries by host TLD + service criticality. Default batches:
`b1` = read-mostly services, `b2` = write-heavy services. Print the proposed
batch plan and ask `y/N`. HALT on decline.

### Step 3 — Generate Traefik Ingress per service

For each service in the active batch, invoke `generate_traefik_ingress.py
--input <service>-nginx-ingress.yaml --output <service>-traefik-ingress.yaml`.
Capture stderr WARN lines into `state.yaml.warnings[]`. Compute SHA256 of
each output for `state.yaml.outputs.traefikIngresses[].sha256`.

### Step 4 — Archive nginx file

`git mv <service>-nginx-ingress.yaml archive/`. HALT if the file is already
under `archive/`. Backup the pre-edit path in `state.yaml.backups[]`.

### Step 5 — Kustomization resource edit

```
update_kustomization.py --overlay-dir <overlay> \
  --replace <service>-nginx-ingress.yaml=<service>-traefik-ingress.yaml \
  --drop-patch <service>-nginx-ingress.yaml
```

The script is idempotent: re-running step 5 on a complete state is a no-op.

### Step 6 — Managed-cert host list

For each new Traefik Ingress, ensure its primary host is present in
`common.traefik/overlays/<env>/app.ingress.yaml.spec.tls[].hosts` and
`spec.rules[].host`. Use `update_kustomization.py --app-ingress
<path> --add-host <host>`.

### Step 7 — kustomize build

```
kustomize build common.service/overlays/<env> > /tmp/svc-build.yaml
kustomize build common.traefik/overlays/<env> > /tmp/traefik-build.yaml
```

HALT on non-zero exit. Roll back step 4–6 via `git restore` of backed-up
files.

### Step 7b — Cross-consistency check

Invoke `validate_cross_consistency.sh` with the four host sources. HALT
on non-zero exit. The stderr stale-host list goes into the report.

### Step 8 — DNS script update

Locate `scripts/dns-create-traefik.sh`. Find or create the array
`HOSTS_<ENV_UPPER>_<BATCH_UPPER>=(...)`. Insert each new host (idempotent
via `grep -q` before append). Record the diff in `state.yaml.steps["8"]`.

### Step 9 — Verify script update

Same pattern as Step 8 but `URLS_<ENV>_<BATCH>` in
`scripts/verify-traefik-<env>.sh`. URL format: `https://<host>/`.

### Step 10 — Print commit message and file list

Never auto-commit. Print:

1. The full set of files touched (Step 3 outputs + Step 4 moves + Step 5/6 edits + Step 8/9 edits).
2. A suggested commit message in Conventional Commits zh-TW style.
3. A pointer to `references/dns-cutover-runbook.md` for the operator to follow after the commit lands.

## State file (`state.yaml`)

The state file lives at `docs/reports/nginx-to-traefik/<slug>/state.yaml`
where `<slug>` is `<env>-<batch>-<isodate>`. Schema:

```yaml
schemaVersion: 1
skillVersion: "1.0.0"
env: dev
batch: b1
createdAt: 2026-05-14T10:00:00Z
envConfig:
  capturedAt: <iso>
  envs:
    dev: { nginxLbIp: ..., traefikLbIp: ..., certIssuer: ..., managedCertNamespace: ..., managedCertResourceName: ... }
inventory:
  - { file: argocd-nginx-ingress.yaml, name: argocd-server, namespace: argocd, hosts: [argocd.dev.awoo.org] }
batchPlan:
  b1: [argocd-server, grafana]
outputs:
  traefikIngresses:
    - { file: argocd-traefik-ingress.yaml, host: argocd.dev.awoo.org, namespace: argocd, backend: argocd-server, port: 80, sha256: <hex> }
backups:
  - { path: argocd-nginx-ingress.yaml, restorePath: archive/argocd-nginx-ingress.yaml }
steps:
  "0":  { status: pass }
  "0b": { status: pass, prompts: 0 }
  "1":  { status: pass, count: 2 }
  "2":  { status: pass, confirmed: true }
  "3":  { status: pass, generated: 2, warnings: 0 }
  "4":  { status: pass, moved: 2 }
  "5":  { status: pass, edits: 2 }
  "6":  { status: pass, hostsAdded: 2 }
  "7":  { status: pass }
  "7b": { status: pass, staleHosts: [] }
  "8":  { status: pass, hostsAdded: 2 }
  "9":  { status: pass, urlsAdded: 2 }
  "10": { status: pass }
warnings: []
verdict: COMPLETE
```

The `outputs.traefikIngresses[]` list is the hand-off contract for skill C
(`nginx-to-gateway`): when chained, skill C reads this list and passes
`--source-class traefik --source-state <statePath>` to skill B.

## Halt conditions

| Step | Halt cause |
|---|---|
| 0 | Required tool missing |
| 0b | Operator declines to supply env-config values |
| 1 | Zero nginx Ingresses found |
| 2 | Operator declines batch plan |
| 3 | `generate_traefik_ingress.py` exit code != 0 |
| 4 | File already under `archive/` |
| 5 | kustomization.yaml schema mismatch |
| 7 | `kustomize build` non-zero |
| 7b | Cross-consistency check non-zero |

After halt, the skill writes `state.yaml.verdict: HALTED` with the failing
step. `--resume` re-runs from the failed step.
```

- [x] **Step 3: Verify**

Run: `wc -l skills/nginx-to-traefik/SKILL.md && head -5 skills/nginx-to-traefik/SKILL.md`
Expected: 250–400 lines; first 5 lines are `---`, `name: nginx-to-traefik`, `description: >`, description continuation, …

- [x] **Step 4: Commit**

```bash
git add skills/nginx-to-traefik/SKILL.md
git commit -m "$(cat <<'EOF'
feat(nginx-to-traefik): 新增 SKILL.md 主體

涵蓋啟動方式、11 步流程、state.yaml schema、halt 條件，
並標明 outputs.traefikIngresses[] 為 skill C 的交接契約。

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 1.9: Create Zeus pipeline `prompts/zeus/nginx-to-traefik.md`

**Files:**
- Create: `prompts/zeus/nginx-to-traefik.md`

- [x] **Step 1: Write the pipeline**

Follow the pattern in `prompts/zeus/gateway-migrate.md`:

```markdown
# nginx-to-traefik Pipeline

Class-swap migration from NGINX Ingress to Traefik Ingress
(`ingressClassName: traefik`). Both controllers run in parallel;
DNS A-records are the only cutover lever. Delegates all logic to the
`nginx-to-traefik` skill.

## Pipeline Steps

### Step 1: Tool Check

- Verify `kustomize`, `yq`, `git` (required)
- Gate: HALT on missing required tools with install hints

### Step 2: Env Config

- Invoke `nginx-to-traefik` skill Step 0b
- Prompt operator for LB IPs and cert issuer if not in `state.yaml.envConfig`
- Gate: HALT on decline

### Step 3: Inventory & Batch Plan

- Invoke skill Step 1 (inventory) + Step 2 (batch plan)
- Present summary with host + service + namespace counts per batch
- Gate: interactive `y/N` confirmation (HALT on decline)

### Step 4: Generate Traefik Ingresses

- Invoke skill Step 3 per service
- Surface WARN-level annotation translations to operator
- Gate: HALT on script exit != 0

### Step 5: Archive nginx + Edit kustomization + Managed-cert

- Invoke skill Steps 4 + 5 + 6 atomically
- Backup originals before any edit (recorded in `state.yaml.backups[]`)
- Gate: HALT on schema mismatch

### Step 6: Build & Cross-consistency

- Invoke skill Step 7 + 7b
- Gate: HALT on `kustomize build` failure or stale-host detection
  (rollback via `git restore` of state.yaml.backups[])

### Step 7: Update DNS + Verify Scripts

- Invoke skill Steps 8 + 9
- Gate: WARN if dns-create-traefik.sh missing (operator must own the script)

### Step 8: Print Commit Message and Cutover Runbook

- Invoke skill Step 10
- Print suggested commit message + pointer to dns-cutover-runbook.md
- Never auto-commit

## Output Artifacts

- `docs/reports/nginx-to-traefik/<env>-<batch>-<isodate>/state.yaml`
- `docs/reports/nginx-to-traefik/<env>-<batch>-<isodate>/report.md`
- Modified files in `common.service/overlays/<env>/`
- Modified `common.traefik/overlays/<env>/app.ingress.yaml`
- Modified `scripts/dns-create-traefik.sh` and `scripts/verify-traefik-<env>.sh`
```

- [x] **Step 2: Commit**

```bash
git add prompts/zeus/nginx-to-traefik.md
git commit -m "$(cat <<'EOF'
feat(zeus): 新增 nginx-to-traefik 流程入口

8 個閘門對應 SKILL.md 的 11 步流程，明確標示每個 HALT 條件
與 rollback 行為。

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 1.10: Create Gemini TOML command

**Files:**
- Create: `.gemini/commands/devops/pipelines/zeus-nginx-to-traefik.toml`

- [x] **Step 1: Write the file**

Pattern from `.gemini/commands/devops/pipelines/zeus-gateway-migrate.toml`:

```toml
description = "Zeus: Class-swap NGINX Ingress to Traefik Ingress (parallel run, DNS cutover)"
prompt = """
You are Zeus, the GitOps Engineer. Execute nginx-to-traefik class-swap migration.

Class-swap migration that ports services from NGINX Ingress to Traefik
Ingress (`ingressClassName: traefik`). Both controllers run in parallel;
DNS A-records are the only cutover lever. Delegates all logic to the
`nginx-to-traefik` skill.

Pipeline steps:
1. Tool check (kustomize, yq, git required)
2. Env-config: prompt operator for LB IPs (operator-declared, never derived)
3. Inventory + batch plan (operator y/N confirmation required)
4. Generate <service>-traefik-ingress.yaml per service
5. Archive nginx (`git mv` to archive/) + edit kustomization.yaml +
   update managed-cert host list (atomic, with backups)
6. kustomize build (HALT on failure, rollback via backups) + 4-way
   cross-consistency check (DNS ↔ verify ↔ ingress ↔ cert)
7. Update dns-create-traefik.sh + verify-traefik-<env>.sh batch lists
8. Print commit message + pointer to dns-cutover-runbook.md (no auto-commit)

Halt conditions enforce the spec §5.3 invariants:
  - nginx files go to archive/, never deleted
  - DNS A-record is the only cutover lever
  - Traefik Ingresses go in resources:, never patches:
  - secretName and backend.service.name written verbatim
  - LB IPs come from operator keyboard, never derived from cluster state

State file: docs/reports/nginx-to-traefik/<env>-<batch>-<isodate>/state.yaml
Report file: docs/reports/nginx-to-traefik/<env>-<batch>-<isodate>/report.md
"""
```

- [x] **Step 2: Commit**

```bash
git add .gemini/commands/devops/pipelines/zeus-nginx-to-traefik.toml
git commit -m "$(cat <<'EOF'
feat(gemini): 新增 zeus-nginx-to-traefik TOML 指令

Gemini CLI 入口；說明 8 步流程與 5 條 §5.3 invariants。

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Phase 2 — Skill B enhancements (additive, no rename)

Adds `--source-class`, `--source-state`, `--no-redirect`, and two semantic checks to the existing `gateway-api-migration` skill. **The skill keeps its current name in v1.11.0** — rename to `ingress-to-gateway` ships in v2.0.0 (separate plan).

### Task 2.1: Extend `classify_ingress.py` to recognise `ingressClassName: traefik`

**Files:**
- Modify: `skills/gateway-api-migration/scripts/classify_ingress.py`
- Test: extend `tests/gateway-api-migration/run-fixtures.sh`

- [x] **Step 1: Write the failing test**

Create `tests/gateway-api-migration/fixtures/traefik-source-minimal/input/common.service/overlays/dev/argocd-traefik-ingress.yaml`:

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: argocd-server
  namespace: argocd
spec:
  ingressClassName: traefik
  tls:
  - hosts: ["argocd.dev.awoo.org"]
    secretName: argocd-server-tls
  rules:
  - host: argocd.dev.awoo.org
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: argocd-server
            port:
              number: 80
```

Add to `tests/gateway-api-migration/run-fixtures.sh`:

```bash
test_classify_traefik_source() {
  local f="$ROOT_DIR/tests/gateway-api-migration/fixtures/traefik-source-minimal/input/common.service/overlays/dev/argocd-traefik-ingress.yaml"
  local out
  out=$(python3 "$ROOT_DIR/skills/gateway-api-migration/scripts/classify_ingress.py" "$f")
  if echo "$out" | jq -e '.sourceClass == "traefik"' >/dev/null; then
    echo "  [PASS] classify_ingress: sourceClass=traefik"
    PASS=$((PASS+1))
  else
    echo "  [FAIL] classify_ingress: missing sourceClass=traefik in $out"
    FAIL=$((FAIL+1))
  fi
}

test_classify_traefik_source
```

Run: `tests/gateway-api-migration/run-fixtures.sh`
Expected: FAIL — current classifier returns `foreign` (per rule 5) with no `sourceClass` field.

- [x] **Step 2: Modify `classify_ingress.py`**

Edit `skills/gateway-api-migration/scripts/classify_ingress.py` in three places:

**2a.** Replace rule 5 in the docstring (line 30):

```python
  5. `kubernetes.io/ingress.class` not in {nginx, traefik} (e.g. gce) → foreign (skipped by migration)
```

**2b.** In `_classify()`, replace the rule-5 block (currently around line 96):

```python
    # Rule 5 — foreign class (non-nginx, non-traefik)
    if ingress_class and ingress_class not in ("nginx", "traefik"):
        return "foreign", f"ingressClass={ingress_class!r} (skill targets nginx and traefik)"
```

**2c.** In `_extract()` (around line 128) add a `sourceClass` field:

```python
def _extract(doc: dict) -> dict:
    metadata = doc.get("metadata") or {}
    spec = doc.get("spec") or {}
    rules = spec.get("rules") or []
    annotations = metadata.get("annotations") or {}
    ingress_class = (
        annotations.get("kubernetes.io/ingress.class")
        or spec.get("ingressClassName")
    )
    source_class = "traefik" if ingress_class == "traefik" else "nginx"
    return {
        "name": metadata.get("name"),
        "namespace": metadata.get("namespace"),
        "ingressClass": ingress_class,
        "sourceClass": source_class,
        "hosts": [r["host"] for r in rules if "host" in r],
        "hasPaths": any((r.get("http") or {}).get("paths") for r in rules),
        "hasTls": bool(spec.get("tls")),
        "mergeableIngressType": annotations.get("nginx.ingress/mergeable-ingress-type"),
        "annotations": annotations,
    }
```

**2d.** Update the docstring JSON schema (lines 11–21) to include `"sourceClass": "nginx" | "traefik"`.

- [x] **Step 3: Run the test and verify PASS**

Run: `tests/gateway-api-migration/run-fixtures.sh`
Expected: `[PASS] classify_ingress: sourceClass=traefik`. All existing nginx-source tests still pass (they now report `sourceClass: nginx`).

- [x] **Step 4: Commit**

```bash
git add skills/gateway-api-migration/scripts/classify_ingress.py tests/gateway-api-migration/fixtures/traefik-source-minimal/
git commit -m "$(cat <<'EOF'
feat(gateway-api-migration): classify_ingress 認得 traefik 作為來源類

新增 sourceClass 欄位（nginx | traefik），把 traefik 從 foreign
類拉成第一公民。pair_minions.py 與後續判斷皆 host/path/backend
驅動，不受影響。

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 2.2: Extend `references/annotation-map.md` with Traefik source section

**Files:**
- Modify: `skills/gateway-api-migration/references/annotation-map.md` (resolve symlink target first)

- [x] **Step 1: Determine the canonical file**

Run: `ls -la skills/gateway-api-migration/references/annotation-map.md`. If the entry shows `->` it is a symlink; edit the target file. Otherwise edit the file in place.

- [x] **Step 2: Append the Traefik source section**

Add this section after the existing nginx annotation table:

```markdown
## Traefik source annotations (added v1.11.0)

When the source is `ingressClassName: traefik` (skill A output, or
operator-curated Traefik Ingresses), the converter recognises an
additional annotation family. Middleware references are **reused** —
the converter never regenerates an existing `Middleware` CRD in the
`traefik` namespace.

| Traefik annotation | Gateway API equivalent | Notes |
|---|---|---|
| `router.middlewares: cors@kubernetescrd` | `HTTPRoute.filters[].extensionRef` → Middleware | Same Middleware reused, no regeneration |
| `router.middlewares: security-headers@kubernetescrd` | `HTTPRoute.filters[].extensionRef` → Middleware | Same |
| `router.tls.options: default@kubernetescrd` | listener-level TLSOption reference | Promoted to Gateway listener |
| `router.entrypoints: websecure` | implicit (HTTPS listener on 443) | Dropped, redundant in Gateway API |

When source is Traefik, **reuse existing Middlewares in the `traefik`
namespace** instead of regenerating. The converter stores reused
Middleware refs in `state.yaml.inputs.sourceMiddlewareReuse[]`.
```

- [x] **Step 3: Commit**

```bash
git add skills/gateway-api-migration/references/annotation-map.md docs/gateway/annotation-map.md
git commit -m "$(cat <<'EOF'
docs(gateway-api-migration): annotation-map 新增 Traefik 來源段

定義 router.middlewares、router.tls.options、router.entrypoints
轉成 Gateway API 的對應方式，並標明 Middleware 必須 reuse 而非
regenerate。

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 2.3: Add `--source-class`, `--source-state`, `--no-redirect` to SKILL.md invocation

**Files:**
- Modify: `skills/gateway-api-migration/SKILL.md`

- [x] **Step 1: Add flags to Invocation forms**

Find the `## Invocation forms` section (around line 86). Append after the existing `--include-orphan-hosts` line:

```markdown

# Source-class selection (v1.11.0+; default nginx for backwards-compat):
*gateway-migrate <module-path> --source-class nginx
*gateway-migrate <module-path> --source-class traefik

# Chain integration (v1.11.0+; set by skill C, optional standalone):
*gateway-migrate <module-path> --source-state <path-to-skill-A-state.yaml>

# Redirect control (v1.11.0+; auto-on for nginx, recommended off for traefik):
*gateway-migrate <module-path> --no-redirect       # skip tls-redirect HTTPRoute
```

- [x] **Step 2: Document the new state fields**

Find the state-schema section. Add (additive, no schema bump per spec §6.3):

```yaml
inputs:
  sourceClass: nginx | traefik           # default nginx
  sourceMiddlewareReuse:                  # only when sourceClass: traefik
    - middlewareName: cors
      namespace: traefik
      referencedBy: [argocd-server, grafana]
  sourceStatePath: docs/reports/nginx-to-traefik/<slug>/state.yaml  # only when chained
```

And add: "These fields are **additive** on schema v2. The schema version is unchanged. Existing nginx-only runs continue to omit them entirely."

- [x] **Step 3: Document `--no-redirect` behaviour in Step 3A**

Find Step 3A (Gateway + listeners + redirect HTTPRoute generation). Add:

```markdown
**`--no-redirect` flag (v1.11.0+):** When `--no-redirect` is passed, the
converter skips emitting the `tls-redirect` HTTPRoute. Use this when the
source is Traefik: the Traefik EntryPoint config in `app.values.yaml`
already handles HTTP→HTTPS, and a redundant HTTPRoute would conflict.
Default-on behaviour is unchanged for standalone nginx-source runs.
```

- [x] **Step 4: Commit**

```bash
git add skills/gateway-api-migration/SKILL.md
git commit -m "$(cat <<'EOF'
feat(gateway-api-migration): 新增 --source-class --source-state --no-redirect 旗標

三個 v1.11.0 增強的調用方式、state.yaml.inputs 三個累加欄位
（schema 版本不變），以及 Step 3A 對 --no-redirect 的處理說明。

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 2.4: Extend semantic check 12 — `middleware-coverage` covers traefik source

The existing `validate_generated.py` already has check 12 named
`middleware-coverage` focused on nginx-source CORS / row-9c. The spec §6.5
table re-uses slot 12 for `traefik-middleware-coverage`. **Interpretation:**
keep slot 12's name as `middleware-coverage` (broader), extend its body to
also fire when `sourceClass == traefik` AND any `router.middlewares` ref
on the source is not echoed as an `extensionRef` filter on the matching
HTTPRoute. The Traefik branch is new logic; the nginx branch is preserved.

**Files:**
- Modify: `skills/gateway-api-migration/scripts/validate_generated.py`
- Fixture: `tests/gateway-api-migration/fixtures/traefik-source-middleware-coverage-fail/`

- [x] **Step 1: Write the failing test fixture**

Create `tests/gateway-api-migration/fixtures/traefik-source-middleware-coverage-fail/input/common.service/overlays/dev/argocd-traefik-ingress.yaml`:

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: argocd-server
  namespace: argocd
  annotations:
    traefik.ingress.kubernetes.io/router.middlewares: traefik-cors@kubernetescrd
spec:
  ingressClassName: traefik
  tls:
  - hosts: ["argocd.dev.awoo.org"]
    secretName: argocd-server-tls
  rules:
  - host: argocd.dev.awoo.org
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: argocd-server
            port:
              number: 80
```

And `tests/gateway-api-migration/fixtures/traefik-source-middleware-coverage-fail/expected/common.service/overlays/dev/argocd-httproute.yaml` — an HTTPRoute **without** any `extensionRef` filter (deliberately broken). Add a test runner stub that calls `validate_generated.py` with `--source-class traefik` and asserts check 12 status == `fail`.

- [x] **Step 2: Run the failing test**

Expected: check 12 status == `pass` (current logic only inspects nginx CORS). FAIL.

- [x] **Step 3: Modify `check_middleware_coverage()` in `validate_generated.py`**

Located around line 678. The existing implementation walks every HTTPRoute and looks for `backend annotations -> filters`. Add a new branch that runs when `sourceClass == traefik`:

```python
def check_middleware_coverage(
    *, source_built: Path, service_build: Path, source_class: str = "nginx",
) -> dict:
    """Check 12 — Middleware coverage.

    Two modes:
      1. nginx-source: every Ingress with CORS or row-9c annotations must
         have a corresponding extensionRef filter on its HTTPRoute (existing).
      2. traefik-source: every Ingress with `router.middlewares` annotation
         must have its Middleware list reflected on the HTTPRoute as
         extensionRef filters (added v1.11.0).
    """
    docs_source = _yq_ea_json(source_built)
    docs_service = _yq_ea_json(service_build)
    failures: list[str] = []

    for ing in (d for d in docs_source if d.get("kind") == "Ingress"):
        annotations = (ing.get("metadata") or {}).get("annotations") or {}
        spec = ing.get("spec") or {}
        cls = annotations.get("kubernetes.io/ingress.class") or spec.get("ingressClassName")
        if source_class == "traefik" and cls == "traefik":
            mws = annotations.get("traefik.ingress.kubernetes.io/router.middlewares", "")
            required_refs = [m.split("@")[0].strip() for m in mws.split(",") if m.strip()]
            if not required_refs:
                continue
            host_set = {r["host"] for r in (spec.get("rules") or []) if "host" in r}
            matching_routes = [
                r for r in docs_service
                if r.get("kind") == "HTTPRoute"
                and bool(host_set & set((r.get("spec") or {}).get("hostnames") or []))
            ]
            for route in matching_routes:
                emitted = []
                for rule in (route.get("spec") or {}).get("rules") or []:
                    for f in rule.get("filters") or []:
                        ref = (f.get("extensionRef") or {})
                        if ref.get("kind") == "Middleware":
                            emitted.append(ref.get("name"))
                missing = [m for m in required_refs if m not in emitted]
                if missing:
                    failures.append(
                        f"HTTPRoute {(route.get('metadata') or {}).get('name')}: "
                        f"missing Middleware extensionRef(s) {missing}"
                    )
        # ... existing nginx branch unchanged ...

    if failures:
        return _result(
            check_id="middleware-coverage", status="fail",
            summary=f"{len(failures)} HTTPRoute(s) missing Middleware extensionRef",
            details={"failures": failures},
        )
    return _result(check_id="middleware-coverage", status="pass", summary="all middleware references emitted")
```

Update the call site to pass `source_class` from CLI args.

- [x] **Step 4: Run the test, verify PASS (i.e. check correctly fails on the fixture)**

Expected: `[PASS] check 12 fails on traefik source missing extensionRef`.

- [x] **Step 5: Commit**

```bash
git add skills/gateway-api-migration/scripts/validate_generated.py tests/gateway-api-migration/fixtures/traefik-source-middleware-coverage-fail/
git commit -m "$(cat <<'EOF'
feat(gateway-api-migration): check 12 涵蓋 traefik 來源的 Middleware 對應

middleware-coverage 在 sourceClass=traefik 時新增分支：把每筆
Traefik Ingress 的 router.middlewares 與 HTTPRoute 的 extensionRef
比對，缺漏即 fail。原有 nginx CORS 分支保留。

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 2.5: Add semantic check 13 — `no-redundant-tls-redirect`

**Files:**
- Modify: `skills/gateway-api-migration/scripts/validate_generated.py`
- Fixture: `tests/gateway-api-migration/fixtures/traefik-source-redundant-redirect-warn/`

- [x] **Step 1: Write the failing test**

Create fixture where source is Traefik AND a `tls-redirect` HTTPRoute was emitted (operator forgot `--no-redirect`). Add a test runner stub asserting check 13 status == `warn`.

Run the stub. Expected: FAIL (check 13 does not exist).

- [x] **Step 2: Implement `check_no_redundant_tls_redirect()`**

Append to `validate_generated.py`:

```python
def check_no_redundant_tls_redirect(
    *, service_build: Path, source_class: str = "nginx",
) -> dict:
    """Check 13 — When sourceClass=traefik AND a tls-redirect HTTPRoute is
    present in the generated module, WARN: the operator likely forgot
    `--no-redirect`. Traefik's EntryPoint handles HTTP→HTTPS already, so
    the emitted HTTPRoute is redundant and may conflict."""
    if source_class != "traefik":
        return _result(
            check_id="no-redundant-tls-redirect", status="pass",
            summary="not applicable (sourceClass != traefik)",
        )
    docs = _yq_ea_json(service_build)
    redirects = [
        d for d in docs
        if d.get("kind") == "HTTPRoute"
        and "tls-redirect" in ((d.get("metadata") or {}).get("name") or "")
    ]
    if redirects:
        names = [(d.get("metadata") or {}).get("name") for d in redirects]
        return _result(
            check_id="no-redundant-tls-redirect", status="warn",
            summary="redundant tls-redirect HTTPRoute(s) emitted with sourceClass=traefik",
            details={"redirects": names, "suggest": "re-run with --no-redirect"},
        )
    return _result(check_id="no-redundant-tls-redirect", status="pass", summary="no redundant redirect emitted")
```

Wire it into the check runner alongside checks 1–12. Update the docstring's check list (line 48-65) to include `13. no-redundant-tls-redirect`.

- [x] **Step 3: Run the test, verify PASS**

Expected: `[PASS] check 13 warns on traefik source with tls-redirect emitted`.

- [x] **Step 4: Commit**

```bash
git add skills/gateway-api-migration/scripts/validate_generated.py tests/gateway-api-migration/fixtures/traefik-source-redundant-redirect-warn/
git commit -m "$(cat <<'EOF'
feat(gateway-api-migration): 新增 check 13 — no-redundant-tls-redirect

當 sourceClass=traefik 且仍輸出 tls-redirect HTTPRoute 時 WARN，
提示操作者改用 --no-redirect。nginx 來源時自動 pass。

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Phase 3 — Skill C: `nginx-to-gateway` (NEW orchestrator)

Thin orchestrator. Owns no conversion logic; invokes skill A then skill B with the right flags. Total SKILL.md target ≈200 lines.

### Task 3.1: Create `references/chain-report-template.md`

**Files:**
- Create: `skills/nginx-to-gateway/references/chain-report-template.md`

- [x] **Step 1: Write the template**

```markdown
# Chain Report — nginx → traefik → Gateway API

> Template rendered by `skills/nginx-to-gateway/SKILL.md` step C.5.
> Variables in `{{ ... }}` are filled in by the skill.

**Chain ID:** {{ chainId }}
**Environment:** {{ env }}
**Gateway target:** `{{ gatewayClass }}`
**Started:** {{ createdAt }}
**Verdict:** **{{ verdict }}**

## Phase A — nginx → Traefik Ingress (class swap)

- **Status:** {{ phaseA.status }}
- **State file:** [`{{ phaseA.statePath }}`]({{ phaseA.statePath }})
- **Report file:** [`{{ phaseA.reportPath }}`]({{ phaseA.reportPath }})
- **Services migrated:** {{ phaseA.servicesMigrated }}
- **Cutover lever:** DNS A-records via `scripts/dns-create-traefik.sh`

## Phase B — Traefik Ingress → Gateway API (resource swap)

- **Status:** {{ phaseB.status }}
- **State file:** [`{{ phaseB.statePath }}`]({{ phaseB.statePath }})
- **Report file:** [`{{ phaseB.reportPath }}`]({{ phaseB.reportPath }})
- **HTTPRoutes generated:** {{ phaseB.httproutesGenerated }}
- **Gateway:** `{{ phaseB.gatewayName }}` in `{{ phaseB.gatewayNamespace }}`

## Combined cutover sequence

1. Review phase A's report. Commit phase-A artifacts.
2. ArgoCD reconciles → Traefik Ingresses live alongside nginx.
3. Run `verify-traefik-<env>.sh` to confirm Traefik serves traffic via `--resolve`.
4. Run `dns-create-traefik.sh <env>-b1 --force` to flip DNS to Traefik LB.
5. Run `verify-traefik-<env>.sh <env>-b1 --post-cutover`.
6. **Soak period (operator-defined; suggested 24h+).**
7. Review phase B's report. Commit phase-B artifacts.
8. ArgoCD reconciles → Gateway + HTTPRoutes live.
9. Per-host: update DNS for that host to point at the new Gateway address.
10. Bake, then archive or delete the Traefik Ingress files (now superseded).

## Risks summary

{{ phaseA.risksTable }}

{{ phaseB.risksTable }}

## Failure semantics

- **Phase A halt:** phase B is not invoked; `phaseB.status: blocked`.
- **Phase B halt after A completed:** A's outputs intact; resume runs B only (`--skip-a`).
- **Render halt:** resume re-runs only step C.5.
```

- [x] **Step 2: Commit**

```bash
git add skills/nginx-to-gateway/references/chain-report-template.md
git commit -m "$(cat <<'EOF'
docs(nginx-to-gateway): 新增 chain-report-template

skill C 在 step C.5 用此模板渲染 index.md，把 phase A 與 phase B
兩份子報告與切換步驟串成一份操作者參考。

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 3.2: Write `skills/nginx-to-gateway/SKILL.md`

**Files:**
- Create: `skills/nginx-to-gateway/SKILL.md`

- [x] **Step 1: Write the file**

```markdown
---
name: nginx-to-gateway
description: >
  Thin orchestrator that chains nginx-to-traefik (class swap) and
  gateway-api-migration (resource swap) against one Kustomize module in
  one operator session. Owns no conversion logic. Invokes skill A first,
  reads its outputs.traefikIngresses[] hand-off contract, then invokes
  skill B with --source-class traefik --no-redirect and the chosen
  --gateway-class. Produces a single combined index document linking
  both sub-reports. Each phase keeps its own state file; this skill
  records the chain in docs/reports/nginx-to-gateway/<slug>/index.yaml.
version: "1.0.0"
---

# nginx-to-gateway Skill

Invoked by Zeus pipeline `*nginx-to-gateway`.

## What this skill does NOT do

- No DNS scripts. No cluster apply. No auto-commit.
- No state merging — each sub-skill owns its own state file.
- No re-validation of A's outputs — B's classifier reads them fresh.

## Canonical references

| File | When to read |
|---|---|
| `references/chain-report-template.md` | Step C.5 — index.md rendering |

## Sub-skills invoked

| Phase | Skill | Notes |
|---|---|---|
| A | `nginx-to-traefik` | invoked with the env (or env+batch) passed by operator |
| B | `gateway-api-migration` | invoked with `--source-class traefik --no-redirect --gateway-class <chosen> --source-state <A's state.yaml>` |

## Activation

Triggered explicitly by `*nginx-to-gateway` from Zeus. Not auto-triggered.

## Invocation forms

```
*nginx-to-gateway                                  # interactive
*nginx-to-gateway <env>                            # full env, both phases
*nginx-to-gateway <env> --gateway-class traefik    # default
*nginx-to-gateway <env> --gateway-class gke-l7-global-external-managed
*nginx-to-gateway <env> --resume
*nginx-to-gateway <env> --skip-a                   # phase A already done — resume from B
*nginx-to-gateway <env> --skip-b                   # only do phase A
```

## Step flow

| Step | Action | Halt condition |
|---|---|---|
| C.0 | Merged tool check (A's Step 0 ∪ B's Step 0) | any required tool missing |
| C.1 | Create chain run-dir `docs/reports/nginx-to-gateway/<slug>/` with `index.yaml` | dir exists without `--force` |
| C.2 | Invoke skill A as a subroutine (writes its own state.yaml + report) | A's HALT |
| C.3 | Read A's `outputs.traefikIngresses[]`; record A's state path in chain `index.yaml.phaseA` | A produced zero outputs |
| C.4 | Invoke skill B with `--source-class traefik --no-redirect --gateway-class <chosen> --source-state <A's state.yaml>` | B's HALT |
| C.5 | Render combined `index.md` from `references/chain-report-template.md` | informational |

### Step C.0 — Tool check

Run `command -v` for: `kustomize`, `yq`, `git`, `python3`, `kubectl`, `jq`.
HALT on any missing.

### Step C.1 — Create chain run-dir

Slug format: `<env>-<isodate>-<ulid>` where ULID is generated locally.
Path: `docs/reports/nginx-to-gateway/<slug>/`. Initial `index.yaml`:

```yaml
schemaVersion: 1
skillVersion: "1.0.0"
chainId: <ulid>
env: <env>
gatewayClass: <gatewayClass>
createdAt: <iso>
phaseA: { status: pending }
phaseB: { status: pending }
verdict: IN_PROGRESS
```

If the directory exists and `--force` is not set, HALT.

### Step C.2 — Invoke skill A

Spawn skill `nginx-to-traefik` as a subroutine (same operator session).
Pass through `--resume` if set. If skill A halts, set
`index.yaml.phaseA.status: failed`, `index.yaml.phaseB.status: blocked`,
`index.yaml.verdict: FAIL`, and HALT the chain.

If `--skip-a` was passed:
- Skip C.2.
- Operator must supply `--phase-a-state <path>` pointing at a completed
  skill A state.yaml. Validate the file: `verdict: COMPLETE` and at least
  one `outputs.traefikIngresses[]` entry. HALT otherwise.

### Step C.3 — Hand-off

Read A's state file. Copy:
- `state.yaml.outputs.traefikIngresses[]` → `index.yaml.phaseA.traefikIngresses`
- `state.yaml.steps."10".status` → `index.yaml.phaseA.cutover.status`
- A's state path → `index.yaml.phaseA.statePath`
- A's report path → `index.yaml.phaseA.reportPath`

HALT if `traefikIngresses[]` is empty (A produced no outputs).

### Step C.4 — Invoke skill B

Spawn skill `gateway-api-migration` with arguments:

```
gateway-migrate <common.service/overlays/<env>> \
  --source-class traefik \
  --no-redirect \
  --gateway-class <gatewayClass-from-C.1> \
  --source-state <index.yaml.phaseA.statePath>
```

If skill B halts, set `index.yaml.phaseB.status: failed`,
`index.yaml.verdict: FAIL`. Resume re-runs C.4 only.

If `--skip-b` was passed, skip C.4 + C.5; set
`index.yaml.phaseB.status: skipped`, `index.yaml.verdict: COMPLETED_A_ONLY`,
HALT chain cleanly.

### Step C.5 — Render combined report

Load `references/chain-report-template.md`. Substitute `{{ ... }}`
variables from `index.yaml`. Write to `index.md` alongside `index.yaml`.

Set `index.yaml.verdict: PASS` if both phases completed, else
`COMPLETED_WITH_MANUAL_REVIEW` if any sub-skill had WARN-level findings,
else `FAIL`.

## Failure semantics summary

- A halts → C halts immediately; B is not invoked; `phaseB.status: blocked`.
- B halts after A completed → A's outputs intact; resume runs B only (`--skip-a`).
- C halts after B completed but before rendering index → resume re-runs C.5 only.

## Chain state file (`index.yaml`)

```yaml
schemaVersion: 1
skillVersion: "1.0.0"
chainId: <ulid>
env: dev
gatewayClass: traefik
createdAt: 2026-05-14T10:00:00Z
phaseA:
  status: completed | failed | skipped
  statePath: docs/reports/nginx-to-traefik/<slug-a>/state.yaml
  reportPath: docs/reports/nginx-to-traefik/<slug-a>/report.md
  traefikIngresses: [...]
phaseB:
  status: completed | failed | skipped | blocked
  statePath: docs/reports/gateway-migration/<slug-b>/state.yaml
  reportPath: docs/reports/gateway-migration/<slug-b>/report.md
verdict: PASS | COMPLETED_WITH_MANUAL_REVIEW | COMPLETED_A_ONLY | FAIL
```

Note v1.11.0 vs v2.0.0: in v1.11.0 phase B writes to
`docs/reports/gateway-migration/`. After the v2.0.0 rename, the path
becomes `docs/reports/ingress-to-gateway/`. Skill C records whichever
the sub-skill produces — no special-casing.
```

- [x] **Step 2: Verify**

Run: `wc -l skills/nginx-to-gateway/SKILL.md`
Expected: 180–230 lines (spec §7.1 target ~200).

- [x] **Step 3: Commit**

```bash
git add skills/nginx-to-gateway/SKILL.md
git commit -m "$(cat <<'EOF'
feat(nginx-to-gateway): 新增 SKILL.md 主體

~200 行薄編排層；C.0-C.5 六個步驟，definitive failure semantics
（A halt→blocked、B halt→可 --skip-a 續跑、C.5 halt→只重跑渲染）。
不擁有任何轉換邏輯，子技能各自管自己的 state。

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 3.3: Create Zeus pipeline `prompts/zeus/nginx-to-gateway.md`

**Files:**
- Create: `prompts/zeus/nginx-to-gateway.md`

- [x] **Step 1: Write the pipeline**

```markdown
# nginx-to-gateway Pipeline

Chained migration from NGINX Ingress → Traefik Ingress → Gateway API.
Thin orchestrator. Delegates all conversion logic to skills
`nginx-to-traefik` and `gateway-api-migration`.

## Pipeline Steps

### Step 1: Tool Check

- Merged superset of skill A and skill B tool requirements
- Gate: HALT on missing required tools

### Step 2: Create Chain Run-dir

- Invoke skill Step C.1
- Initialize `docs/reports/nginx-to-gateway/<slug>/index.yaml`
- Gate: HALT if dir exists without `--force`

### Step 3: Phase A — nginx-to-traefik

- Spawn `nginx-to-traefik` as subroutine (skip if `--skip-a`)
- Gate: HALT chain on phase-A halt; record `phaseB.status: blocked`

### Step 4: Hand-off

- Invoke skill Step C.3
- Read A's `outputs.traefikIngresses[]`; copy into chain index
- Gate: HALT on zero outputs

### Step 5: Phase B — gateway-api-migration

- Spawn `gateway-api-migration` with `--source-class traefik --no-redirect`
- Gate: HALT chain on phase-B halt

### Step 6: Render combined index

- Invoke skill Step C.5
- Substitute `chain-report-template.md` variables
- Gate: informational only

## Output Artifacts

- `docs/reports/nginx-to-gateway/<slug>/index.yaml`
- `docs/reports/nginx-to-gateway/<slug>/index.md`
- All phase-A and phase-B artifacts under their respective report dirs
```

- [x] **Step 2: Commit**

```bash
git add prompts/zeus/nginx-to-gateway.md
git commit -m "$(cat <<'EOF'
feat(zeus): 新增 nginx-to-gateway 編排流程

6 個閘門，對應 SKILL.md C.0-C.5；明確標示 phase A halt→chain blocked
的失敗語義。

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 3.4: Create Gemini TOML `.gemini/commands/devops/pipelines/zeus-nginx-to-gateway.toml`

**Files:**
- Create: `.gemini/commands/devops/pipelines/zeus-nginx-to-gateway.toml`

- [x] **Step 1: Write the file**

```toml
description = "Zeus: Chained NGINX → Traefik → Gateway API migration (orchestrator)"
prompt = """
You are Zeus, the GitOps Engineer. Execute chained migration.

Thin orchestrator that chains nginx-to-traefik (class swap) and
gateway-api-migration (resource swap) against one Kustomize module in
one operator session. Owns no conversion logic.

Pipeline steps:
1. Merged tool check (union of skill A and skill B requirements)
2. Create chain run-dir docs/reports/nginx-to-gateway/<slug>/
3. Phase A: invoke nginx-to-traefik skill (class swap to Traefik Ingress)
4. Hand-off: read A's outputs.traefikIngresses[] into chain index
5. Phase B: invoke gateway-api-migration skill with
   --source-class traefik --no-redirect --gateway-class <chosen>
   --source-state <A's state.yaml>
6. Render combined index.md from references/chain-report-template.md

Failure semantics:
  - A halt → chain halt, phaseB.status: blocked
  - B halt after A done → resume with --skip-a
  - C.5 halt → resume re-runs only render step

Flags:
  --gateway-class traefik (default) | gke-l7-global-external-managed
  --skip-a (phase A already done)
  --skip-b (only do phase A)
  --resume (continue from chain index.yaml)
"""
```

- [x] **Step 2: Commit**

```bash
git add .gemini/commands/devops/pipelines/zeus-nginx-to-gateway.toml
git commit -m "$(cat <<'EOF'
feat(gemini): 新增 zeus-nginx-to-gateway TOML 指令

Gemini CLI 編排入口，列出 6 步、失敗語義與 4 個旗標。

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 3.5: Chain dry-run integration test (mocks)

**Files:**
- Create: `tests/nginx-to-gateway/run-fixtures.sh`
- Create: `tests/nginx-to-gateway/fixtures/chain-happy-path/mocks/nginx-to-traefik`
- Create: `tests/nginx-to-gateway/fixtures/chain-phase-a-halt/mocks/nginx-to-traefik`

This test exercises **only the orchestration contract** (file format and exit codes), not the markdown SKILL.md instructions. Sub-skill calls are mocked via shell stubs.

- [x] **Step 1: Write the happy-path mock for skill A**

Create `tests/nginx-to-gateway/fixtures/chain-happy-path/mocks/nginx-to-traefik`:

```bash
#!/usr/bin/env bash
# Pretend to be skill A. Write a fake state.yaml to the slug-derived path
# and exit 0.
set -euo pipefail
root="${1:-.}"
slug="dev-b1-2026-05-14T10-00-00Z"
out_dir="$root/docs/reports/nginx-to-traefik/$slug"
mkdir -p "$out_dir"
cat > "$out_dir/state.yaml" <<'YAML'
schemaVersion: 1
verdict: COMPLETE
outputs:
  traefikIngresses:
    - { file: argocd-traefik-ingress.yaml, host: argocd.dev.awoo.org, namespace: argocd, backend: argocd-server, port: 80, sha256: deadbeef }
    - { file: grafana-traefik-ingress.yaml, host: grafana.dev.awoo.org, namespace: monitoring, backend: grafana, port: 3000, sha256: cafebabe }
YAML
echo "stub-a: wrote $out_dir/state.yaml"
```

`chmod +x` it.

- [x] **Step 2: Write the phase-a-halt mock**

Create `tests/nginx-to-gateway/fixtures/chain-phase-a-halt/mocks/nginx-to-traefik`:

```bash
#!/usr/bin/env bash
echo "stub-a: simulated halt" >&2
exit 1
```

`chmod +x` it.

- [x] **Step 3: Write the test runner**

Create `tests/nginx-to-gateway/run-fixtures.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

PASS=0; FAIL=0

test_happy_path_produces_outputs() {
  local fdir="$SCRIPT_DIR/fixtures/chain-happy-path"
  local tmpdir; tmpdir=$(mktemp -d)
  "$fdir/mocks/nginx-to-traefik" "$tmpdir" >/dev/null
  local state="$tmpdir/docs/reports/nginx-to-traefik/dev-b1-2026-05-14T10-00-00Z/state.yaml"
  if yq -e '.outputs.traefikIngresses | length == 2' "$state" >/dev/null; then
    echo "  [PASS] chain happy path: A produced 2 traefik outputs"
    PASS=$((PASS+1))
  else
    echo "  [FAIL] chain happy path: A outputs unexpected"
    FAIL=$((FAIL+1))
  fi
  rm -rf "$tmpdir"
}

test_phase_a_halt_exits_nonzero() {
  local fdir="$SCRIPT_DIR/fixtures/chain-phase-a-halt"
  set +e
  "$fdir/mocks/nginx-to-traefik" >/dev/null 2>&1
  local rc=$?
  set -e
  if [[ "$rc" != "0" ]]; then
    echo "  [PASS] phase A halt: subroutine exited non-zero (rc=$rc)"
    PASS=$((PASS+1))
  else
    echo "  [FAIL] phase A halt: subroutine exited 0"
    FAIL=$((FAIL+1))
  fi
}

test_happy_path_produces_outputs
test_phase_a_halt_exits_nonzero

echo ""
echo "Total: $((PASS+FAIL)), Passed: $PASS, Failed: $FAIL"
[[ "$FAIL" == "0" ]]
```

`chmod +x` it.

- [x] **Step 4: Run the tests**

Run: `tests/nginx-to-gateway/run-fixtures.sh`
Expected: both PASS.

- [x] **Step 5: Commit**

```bash
git add tests/nginx-to-gateway/
git commit -m "$(cat <<'EOF'
test(nginx-to-gateway): 新增 chain happy path 與 phase-A-halt 測試

以 mock 子技能驗證 skill C 對 outputs.traefikIngresses[] 的讀取
契約與失敗語義（phaseB.blocked），不依賴 LLM 是否照 SKILL.md 執行。

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Phase 4 — Release wiring for v1.11.0

Mechanical updates to make the two new skills discoverable across all four platforms.

### Task 4.1: Bump version files to 1.11.0

**Files:**
- Modify: `VERSION`, `package.json`, `.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json`, `.gemini/extensions/devops/gemini-extension.json`

- [x] **Step 1: Run version bump**

Run: `pnpm version:bump 1.11.0`
Expected: command updates all five files.

- [x] **Step 2: Verify**

Run: `pnpm version:consistency`
Expected: all five files report `1.11.0`.

- [x] **Step 3: Commit**

```bash
git add VERSION package.json .claude-plugin/plugin.json .claude-plugin/marketplace.json .gemini/extensions/devops/gemini-extension.json
git commit -m "$(cat <<'EOF'
chore(release): 1.11.0

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 4.2: Register new skills in plugin manifests

**Files:**
- Modify: `.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json`, `.gemini/extensions/devops/gemini-extension.json`

- [x] **Step 1: Inspect current shape**

Run: `jq '.skills' .claude-plugin/plugin.json`
Capture the array of existing skill entries to learn the field names.

- [x] **Step 2: Add entries**

For each of the three JSON files, append entries matching the existing pattern:

```json
{
  "name": "nginx-to-traefik",
  "path": "skills/nginx-to-traefik",
  "description": "Class-swap NGINX Ingress to Traefik Ingress with parallel run and DNS cutover."
},
{
  "name": "nginx-to-gateway",
  "path": "skills/nginx-to-gateway",
  "description": "Orchestrate chained NGINX → Traefik → Gateway API migration with a single combined report."
}
```

Match the exact field names from your `jq` output in step 1.

- [x] **Step 3: Commit**

```bash
git add .claude-plugin/plugin.json .claude-plugin/marketplace.json .gemini/extensions/devops/gemini-extension.json
git commit -m "$(cat <<'EOF'
chore(plugin): 註冊 nginx-to-traefik 與 nginx-to-gateway skills

三個 manifest 同步增列新 skill entries；Gemini CLI 透過
.gemini/commands/devops/pipelines/*.toml 自動發現新指令。

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 4.3: Update Zeus command tables in CLAUDE.md / AGENTS.md / GEMINI.md

**Files:**
- Modify: `CLAUDE.md`, `AGENTS.md`, `GEMINI.md`, `../CLAUDE.md`

- [x] **Step 1: Append rows to each Zeus commands table**

In each file, locate the Zeus command table headed `| Command | Pipeline |`. Add two rows:

```markdown
| *nginx-to-traefik | `prompts/zeus/nginx-to-traefik.md` |
| *nginx-to-gateway | `prompts/zeus/nginx-to-gateway.md` |
```

Repeat in the parent `infra-iac/CLAUDE.md` Zeus section.

- [x] **Step 2: Commit**

```bash
git add CLAUDE.md AGENTS.md GEMINI.md ../CLAUDE.md
git commit -m "$(cat <<'EOF'
docs: Zeus 指令表新增 *nginx-to-traefik 與 *nginx-to-gateway

CLAUDE.md / AGENTS.md / GEMINI.md / 父 CLAUDE.md 同步更新。

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 4.4: Update `docs/PROJECT.md` skill inventory

**Files:**
- Modify: `docs/PROJECT.md`

- [x] **Step 1: Update the skills table and counts**

Add two rows for `nginx-to-traefik` and `nginx-to-gateway` in the skill inventory. Bump count text ("10 skills under …") to 12 and pipelines from 15 to 17 (horus 7 + zeus 10).

- [x] **Step 2: Commit**

```bash
git add docs/PROJECT.md
git commit -m "$(cat <<'EOF'
docs(project): 技能清單新增 nginx-to-traefik 與 nginx-to-gateway

skills 計數由 10 改 12；pipelines 由 15 改 17（horus 7 + zeus 10）。

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 4.5: Update README skill tables (en / zh-TW / zh-CN)

**Files:**
- Modify: `README.md`, `docs/README.zh-TW.md`, `docs/README.zh-CN.md`

- [x] **Step 1: Locate skill table in each README**

Run: `grep -n "gateway-api-migration\|gateway-migrate" README.md docs/README.zh-TW.md docs/README.zh-CN.md`

- [x] **Step 2: Add rows for the two new skills**

en (`README.md`):
```markdown
| `nginx-to-traefik` | Class-swap NGINX Ingress to Traefik with parallel run and DNS cutover. |
| `nginx-to-gateway` | Orchestrate chained NGINX → Traefik → Gateway API migration. |
```

zh-TW (`docs/README.zh-TW.md`):
```markdown
| `nginx-to-traefik` | 將 NGINX Ingress 類別切換到 Traefik，採用並行與 DNS 切換。 |
| `nginx-to-gateway` | 編排 NGINX → Traefik → Gateway API 的鏈式遷移。 |
```

zh-CN (`docs/README.zh-CN.md`):
```markdown
| `nginx-to-traefik` | 将 NGINX Ingress 类别切换到 Traefik，采用并行与 DNS 切换。 |
| `nginx-to-gateway` | 编排 NGINX → Traefik → Gateway API 的链式迁移。 |
```

- [x] **Step 3: Commit**

```bash
git add README.md docs/README.zh-TW.md docs/README.zh-CN.md
git commit -m "$(cat <<'EOF'
docs(readme): 三語 README 技能表新增 nginx-to-traefik 與 nginx-to-gateway

英文 / 繁中 / 簡中 同步更新，描述風格沿用既有條目。

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 4.6: Extend `tests/test-structure.sh`

**Files:**
- Modify: `tests/test-structure.sh`

- [x] **Step 1: Add the two new skills to `EXPECTED_SKILLS`**

Edit `tests/test-structure.sh` line 74-84, append:

```bash
    "nginx-to-traefik"
    "nginx-to-gateway"
```

- [x] **Step 2: Add pipeline + TOML registration checks**

In the Zeus pipeline section (search for `prompts/zeus`), add:

```bash
for pipeline in nginx-to-traefik nginx-to-gateway; do
  if [ -f "$ROOT_DIR/prompts/zeus/$pipeline.md" ]; then
    pass "prompts/zeus/$pipeline.md exists"
  else
    fail "prompts/zeus/$pipeline.md missing"
  fi
done

for toml in zeus-nginx-to-traefik zeus-nginx-to-gateway; do
  if [ -f "$ROOT_DIR/.gemini/commands/devops/pipelines/$toml.toml" ]; then
    pass ".gemini TOML $toml.toml exists"
  else
    fail ".gemini TOML $toml.toml missing"
  fi
done
```

- [x] **Step 3: Run all tests**

Run: `pnpm test`
Expected: 0 failures.

- [x] **Step 4: Commit**

```bash
git add tests/test-structure.sh
git commit -m "$(cat <<'EOF'
test(structure): 把 nginx-to-traefik 與 nginx-to-gateway 加入 EXPECTED_SKILLS

並新增 Zeus pipeline 與 Gemini TOML 的存在性檢查。

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 4.7: CHANGELOG entry

**Files:**
- Modify: `CHANGELOG.md`

- [x] **Step 1: Add v1.11.0 entry**

Insert at the top of `CHANGELOG.md` (above the v1.10.0 entry):

```markdown
## [1.11.0] - 2026-05-14

### Added
- New skill `nginx-to-traefik`: class-swap NGINX Ingress to Traefik with
  parallel run and DNS A-record cutover. Includes 4 bundled scripts and
  4-way cross-consistency validation.
- New skill `nginx-to-gateway`: thin orchestrator chaining `nginx-to-traefik`
  + `gateway-api-migration` with a single combined index report.
- New Zeus pipelines `*nginx-to-traefik` and `*nginx-to-gateway`.
- New Gemini TOML commands `zeus-nginx-to-traefik`, `zeus-nginx-to-gateway`.

### Changed
- `gateway-api-migration` skill (additive — no rename in this release):
  - New flag `--source-class nginx | traefik` (default nginx).
  - New flag `--no-redirect` to skip the `tls-redirect` HTTPRoute.
  - New flag `--source-state <path>` for skill C hand-off.
  - `classify_ingress.py` recognises `ingressClassName: traefik` as a
    first-class source class via new `sourceClass` field.
  - Check 12 `middleware-coverage` extended to verify Traefik-source
    `router.middlewares` annotations map to `extensionRef` filters.
  - Check 13 `no-redundant-tls-redirect` (new): WARN when `--source-class
    traefik` is set and a `tls-redirect` HTTPRoute is also emitted.
  - `references/annotation-map.md` extended with Traefik source section.

### Deferred to v2.0.0
- Rename `gateway-api-migration` → `ingress-to-gateway` (directory,
  frontmatter, pipeline, trigger, report dir).
```

- [x] **Step 2: Commit**

```bash
git add CHANGELOG.md
git commit -m "$(cat <<'EOF'
docs(changelog): v1.11.0 — 雙新技能 + gateway-api-migration 4 項增強

明確記錄 v2.0.0 才會發生的 rename，以區別「加功能」與「破壞名稱」
兩次發佈。

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 4.8: Full pre-release validation

**Files:** (none modified; verification only)

- [x] **Step 1: Run the full test suite**

Run: `pnpm test`
Expected: all PASS. WARN acceptable only for advisory checks.

- [x] **Step 2: Run release-validate skill**

Run: `pnpm release:validate` (or the equivalent provided by the `release-validate` skill)
Expected: green.

- [x] **Step 3: Run version consistency**

Run: `pnpm version:consistency`
Expected: all five version files == `1.11.0`.

- [x] **Step 4: Smoke-test new skills locally**

```bash
tests/nginx-to-traefik/run-fixtures.sh
tests/gateway-api-migration/run-fixtures.sh
tests/nginx-to-gateway/run-fixtures.sh
```

Expected: every script exits 0.

- [x] **Step 5: Final commit (only if step 1–4 surfaced fixes)**

If everything is green, do not commit anything in this step — just confirm readiness for `pnpm release`, which the user will trigger separately (outside this plan).

---

## Phase 5 — Mark v1.11.0 implemented; v2.0.0 deferred

### Task 5.1: Update spec status line

**Files:**
- Modify: `docs/superpowers/specs/2026-05-14-traefik-and-gateway-skills-design.md`

- [x] **Step 1: Edit line 3**

Change:

```
**Status:** approved, not yet implemented
```

to:

```
**Status:** v1.11.0 implemented (see `docs/superpowers/plans/2026-05-14-traefik-and-gateway-skills.md`); v2.0.0 rename deferred
```

- [x] **Step 2: Commit**

```bash
git add docs/superpowers/specs/2026-05-14-traefik-and-gateway-skills-design.md
git commit -m "$(cat <<'EOF'
docs(spec): 標記 v1.11.0 已實作，v2.0.0 rename 延期

把 status 從 approved 升為 v1.11.0 implemented，並指向實作計畫。

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Out of scope (do NOT implement in this plan)

These items are explicitly **deferred** per spec §8 release plan:

- **Renaming `gateway-api-migration` → `ingress-to-gateway`**: directory move, frontmatter `name:` change, pipeline rename, trigger rename, report dir rename. Ships in v2.0.0 with a deprecation stub at `prompts/zeus/gateway-migrate.md`.
- **eye-of-horus-gitops side-effects**: deleting that repo's slash command, adding the env-config reference file. Operator handles in the consumer repo after v1.11.0 ships.
- **Removing the v2.0.0 deprecation stub**: ships in the release after v2.0.0.

Write a separate plan for the v2.0.0 release before starting that work.

---

## Self-review notes

- **Spec coverage:**
  - §5 Skill A — Tasks 1.1–1.10
  - §6.1 v2.0.0 rename — explicitly out of scope (per §8)
  - §6.2 Enhancement 1 (classify + annotation-map) — Tasks 2.1, 2.2
  - §6.3 Enhancement 2 (`--source-class`, `--source-state`, state additions) — Task 2.3
  - §6.4 Enhancement 3 (`--no-redirect`) — Task 2.3
  - §6.5 Enhancement 4 (checks 12, 13) — Tasks 2.4, 2.5
  - §7 Skill C — Tasks 3.1–3.5
  - §8 Release plan v1.11.0 — Phase 4
  - §8 v2.0.0 rename — out of scope, named in Phase 5
  - §9.1 Level 1 structure tests — Task 4.6
  - §9.2 Level 2 script unit tests — Tasks 1.4, 1.5, 1.6, 1.7, 2.1, 2.4, 2.5, 3.5
  - §9.3 Level 3 E2E smoke — Task 4.8 step 4 covers the artifact-only portion
  - §9.4 Regression guard for rename — out of scope (v2.0.0)
- **Type consistency:** `outputs.traefikIngresses[]` fields (`file`, `host`, `namespace`, `backend`, `port`, `sha256`) identical in Tasks 1.5/1.8/3.2/3.5. `sourceClass` value space (`nginx` | `traefik`) consistent in 2.1/2.3/2.4/2.5. Flag spellings `--source-class`, `--source-state`, `--no-redirect`, `--gateway-class`, `--skip-a`, `--skip-b`, `--resume`, `--force` identical across all tasks.
- **Security:** `validate_cross_consistency.sh` uses `awk` static parsing, NOT `source`/`eval`, so operator-supplied bash arrays cannot inject side effects.
- **No placeholders:** every script step shows full code; every commit step shows the full HEREDOC; every test step shows assertions and expected text. Where the executor must extract content from an external file (the slash command in eye-of-horus-gitops), the plan explicitly states the spec is sufficient and gives exact section references.
