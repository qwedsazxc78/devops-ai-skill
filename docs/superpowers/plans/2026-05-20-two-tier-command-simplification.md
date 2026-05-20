# Two-Tier Command Simplification Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Reduce visible `/devops` commands from 17 to 12 by hiding 5 Horus-internal pipeline components (terraform-validate, terraform-security, helm-scaffold, cicd-enhancer, repo-detect) that users never invoke directly.

**Architecture:** Claude Code plugin discovers skills by scanning `skills/*/SKILL.md` at exactly one directory depth. Renaming those 5 files from `SKILL.md` → `GUIDE.md` removes them from the command palette. All Python scripts, references, and relative paths stay intact. Horus pipeline files switch from `Skill:` notation to `Read skills/<name>/GUIDE.md` for those 5 only. All migration/ingress/traefik skills keep `SKILL.md` so natural-language triggers still work.

**Tech Stack:** Bash, Markdown, Claude Code plugin system, `pnpm test:structure`

---

## Final Skill Classification

### Keep as SKILL.md (visible in palette — 12 commands after agents)

| Skill | Reason |
|-------|--------|
| `nginx-to-traefik` | Users describe migration naturally |
| `nginx-to-gateway` | Chains traefik + gateway, user-facing operation |
| `gateway-api-migration` | Users describe Gateway API upgrade naturally |
| `ingress-controller-install` | Traefik Controller setup, user-invoked |
| `ingress-migration-advisor` | Read-only planner, user-invoked |
| `traefik-controller-decommission` | NGINX removal, user-invoked |
| `kustomize-resource-validation` | Auto-trigger on file edit |
| `yaml-fix-suggestions` | Auto-trigger on file edit |
| `helm-version-upgrade` | User may describe "upgrade helm chart" directly |
| `release-validate` | Standalone CI tool |

### Convert to GUIDE.md (hidden — Horus agent only)

| Skill | Reason |
|-------|--------|
| `terraform-validate` | Only called by Horus pipelines (validate, scaffold, cicd, upgrade, security, health) |
| `terraform-security` | Only called by Horus pipelines |
| `helm-scaffold` | Only called by Horus scaffold pipeline |
| `cicd-enhancer` | Only called by Horus cicd pipeline |
| `repo-detect` | Auto-trigger on plugin activation — users never call this |

---

## Files Modified or Renamed

| Action | Path |
|--------|------|
| Rename | `skills/terraform-validate/SKILL.md` → `GUIDE.md` |
| Rename | `skills/terraform-security/SKILL.md` → `GUIDE.md` |
| Rename | `skills/helm-scaffold/SKILL.md` → `GUIDE.md` |
| Rename | `skills/cicd-enhancer/SKILL.md` → `GUIDE.md` |
| Rename | `skills/repo-detect/SKILL.md` → `GUIDE.md` |
| Keep   | All 10 migration/ingress/validation skills as `SKILL.md` |
| Keep   | `skills/release-validate/SKILL.md` |
| Modify | `prompts/horus/validate.md` |
| Modify | `prompts/horus/scaffold.md` |
| Modify | `prompts/horus/cicd.md` |
| Modify | `prompts/horus/upgrade.md` |
| Modify | `prompts/horus/security.md` |
| Modify | `prompts/horus/health.md` |
| Modify | `.claude/agents/horus.md` |
| Modify | `tests/test-structure.sh` |

---

### Task 1: Rename SKILL.md → GUIDE.md for 5 Horus-internal skills

- [ ] **Step 1: Establish baseline**

```bash
cd /Users/MH/Documents/git_awoo/infra-iac/devops-ai-skill
pnpm test:structure 2>&1 | tail -8
```
Expected: PASS. Note the pass count.

- [ ] **Step 2: Rename the 5 skills**

```bash
cd /Users/MH/Documents/git_awoo/infra-iac/devops-ai-skill/skills
mv terraform-validate/SKILL.md terraform-validate/GUIDE.md
mv terraform-security/SKILL.md terraform-security/GUIDE.md
mv helm-scaffold/SKILL.md helm-scaffold/GUIDE.md
mv cicd-enhancer/SKILL.md cicd-enhancer/GUIDE.md
mv repo-detect/SKILL.md repo-detect/GUIDE.md
```

- [ ] **Step 3: Verify only GUIDE.md exists in those 5 directories**

```bash
find /Users/MH/Documents/git_awoo/infra-iac/devops-ai-skill/skills \
  -name "SKILL.md" | sort
```
Expected output (10 remaining SKILL.md files):
```
skills/gateway-api-migration/SKILL.md
skills/helm-version-upgrade/SKILL.md
skills/ingress-controller-install/SKILL.md
skills/ingress-migration-advisor/SKILL.md
skills/kustomize-resource-validation/SKILL.md
skills/nginx-to-gateway/SKILL.md
skills/nginx-to-traefik/SKILL.md
skills/release-validate/SKILL.md
skills/traefik-controller-decommission/SKILL.md
skills/yaml-fix-suggestions/SKILL.md
```

---

### Task 2: Update Horus pipeline files — Skill: → Read GUIDE.md

Only these 6 pipeline files reference the 5 converted skills.

- [ ] **Step 1: Update prompts/horus/validate.md**

Open the file. Replace:
```
- Skill: `terraform-validate`
```
with:
```
- Read `skills/terraform-validate/GUIDE.md` and follow its step-by-step instructions
```
Replace:
```
- Skill: `terraform-security`
```
with:
```
- Read `skills/terraform-security/GUIDE.md` and follow its step-by-step instructions
```

- [ ] **Step 2: Update prompts/horus/scaffold.md**

Replace:
```
- Skill: `helm-scaffold`
```
with:
```
- Read `skills/helm-scaffold/GUIDE.md` and follow its step-by-step instructions
```
Replace both:
```
- Skill: `terraform-validate`
```
with:
```
- Read `skills/terraform-validate/GUIDE.md` and follow its step-by-step instructions
```
Replace:
```
- Skill: `terraform-security`
```
with:
```
- Read `skills/terraform-security/GUIDE.md` and follow its step-by-step instructions
```

- [ ] **Step 3: Update prompts/horus/cicd.md**

Replace both occurrences of:
```
- Skill: `cicd-enhancer`
```
with:
```
- Read `skills/cicd-enhancer/GUIDE.md` and follow its step-by-step instructions
```
Replace:
```
- Skill: `terraform-validate`
```
with:
```
- Read `skills/terraform-validate/GUIDE.md` and follow its step-by-step instructions
```

- [ ] **Step 4: Update prompts/horus/upgrade.md**

Replace both occurrences of:
```
- Skill: `helm-version-upgrade`
```
with:
```
- Invoke the `helm-version-upgrade` skill
```
(helm-version-upgrade stays as SKILL.md — keep Skill invocation)

Replace:
```
- Skill: `terraform-validate`
```
with:
```
- Read `skills/terraform-validate/GUIDE.md` and follow its step-by-step instructions
```
Replace:
```
- Skill: `terraform-security`
```
with:
```
- Read `skills/terraform-security/GUIDE.md` and follow its step-by-step instructions
```

- [ ] **Step 5: Update prompts/horus/security.md**

Replace:
```
- Skill: `terraform-security`
```
with:
```
- Read `skills/terraform-security/GUIDE.md` and follow its step-by-step instructions
```
Replace:
```
- Skill: `terraform-validate`
```
with:
```
- Read `skills/terraform-validate/GUIDE.md` and follow its step-by-step instructions
```

- [ ] **Step 6: Update prompts/horus/health.md**

Replace:
```
- Skill: `helm-version-upgrade` (check-only mode)
```
with:
```
- Invoke the `helm-version-upgrade` skill (check-only mode)
```
(helm-version-upgrade stays as SKILL.md)

Replace:
```
- Skill: `terraform-security`
```
with:
```
- Read `skills/terraform-security/GUIDE.md` and follow its step-by-step instructions
```
Replace:
```
- Skill: `terraform-validate`
```
with:
```
- Read `skills/terraform-validate/GUIDE.md` and follow its step-by-step instructions
```

- [ ] **Step 7: Verify no stale `- Skill:` references to the 5 converted guides**

```bash
grep -rn "Skill.*terraform-validate\|Skill.*terraform-security\|Skill.*helm-scaffold\|Skill.*cicd-enhancer\|Skill.*repo-detect" \
  /Users/MH/Documents/git_awoo/infra-iac/devops-ai-skill/prompts/
```
Expected: no output

---

### Task 3: Update .claude/agents/horus.md

- [ ] **Step 1: Update the Available Skills section**

Find the section:
```
## Available Skills

You orchestrate these skills from the `skills/` directory:

| Skill | Purpose |
|-------|---------|
| helm-version-upgrade | Helm chart version management (dynamic discovery) |
| terraform-validate | Validation and linting |
| terraform-security | Security scanning |
| cicd-enhancer | CI/CD pipeline improvement |
| helm-scaffold | New module generation |

Read each skill's `SKILL.md` for its workflow before executing.
```

Replace with:
```
## Available Tools

### Skills (invokable via Skill tool)
| Skill | Purpose |
|-------|---------|
| `helm-version-upgrade` | Helm chart version management (dynamic discovery) |

### Internal Guides (read via `Read` tool — not in command palette)
| Guide | Path | Purpose |
|-------|------|---------|
| terraform-validate | `skills/terraform-validate/GUIDE.md` | Validation and linting |
| terraform-security | `skills/terraform-security/GUIDE.md` | Security scanning |
| cicd-enhancer | `skills/cicd-enhancer/GUIDE.md` | CI/CD pipeline improvement |
| helm-scaffold | `skills/helm-scaffold/GUIDE.md` | New module generation |

For skills: invoke via Skill tool. For guides: `Read` the GUIDE.md and follow its instructions.
```

---

### Task 4: Update tests/test-structure.sh

- [ ] **Step 1: Update EXPECTED_SKILLS array (Section 2, ~line 74)**

Replace:
```bash
EXPECTED_SKILLS=(
    "terraform-validate"
    "terraform-security"
    "helm-version-upgrade"
    "helm-scaffold"
    "cicd-enhancer"
    "kustomize-resource-validation"
    "yaml-fix-suggestions"
    "repo-detect"
    "release-validate"
    "gateway-api-migration"
    "nginx-to-traefik"
    "nginx-to-gateway"
)
```
With:
```bash
# User-visible skills (SKILL.md — appear in command palette)
EXPECTED_SKILLS=(
    "helm-version-upgrade"
    "kustomize-resource-validation"
    "yaml-fix-suggestions"
    "release-validate"
    "gateway-api-migration"
    "nginx-to-traefik"
    "nginx-to-gateway"
    "ingress-controller-install"
    "ingress-migration-advisor"
    "traefik-controller-decommission"
)

# Horus-internal guides (GUIDE.md — hidden from command palette)
EXPECTED_GUIDES=(
    "terraform-validate"
    "terraform-security"
    "helm-scaffold"
    "cicd-enhancer"
    "repo-detect"
)
```

- [ ] **Step 2: Add EXPECTED_GUIDES validation loop immediately after the EXPECTED_SKILLS loop**

```bash
for guide in "${EXPECTED_GUIDES[@]}"; do
    guide_dir="$ROOT_DIR/skills/$guide"
    guide_md="$guide_dir/GUIDE.md"

    if [ -d "$guide_dir" ]; then
        pass "skills/$guide/ directory exists"
    else
        fail "skills/$guide/ directory missing"
        continue
    fi

    if [ -f "$guide_md" ]; then
        pass "skills/$guide/GUIDE.md exists (hidden guide)"
    else
        fail "skills/$guide/GUIDE.md missing"
        continue
    fi

    if [ -f "$guide_dir/SKILL.md" ]; then
        fail "skills/$guide/SKILL.md still exists — would re-expose as plugin command"
    else
        pass "skills/$guide/SKILL.md absent (correctly hidden)"
    fi
done
```

---

### Task 5: Run tests and commit

- [ ] **Step 1: Run structure tests**

```bash
cd /Users/MH/Documents/git_awoo/infra-iac/devops-ai-skill
pnpm test:structure
```
Expected: PASS with no FAILs.

- [ ] **Step 2: Commit**

```bash
git add skills/terraform-validate/GUIDE.md skills/terraform-validate/SKILL.md
git add skills/terraform-security/GUIDE.md skills/terraform-security/SKILL.md
git add skills/helm-scaffold/GUIDE.md skills/helm-scaffold/SKILL.md
git add skills/cicd-enhancer/GUIDE.md skills/cicd-enhancer/SKILL.md
git add skills/repo-detect/GUIDE.md skills/repo-detect/SKILL.md
git add prompts/horus/validate.md prompts/horus/scaffold.md prompts/horus/cicd.md
git add prompts/horus/upgrade.md prompts/horus/security.md prompts/horus/health.md
git add .claude/agents/horus.md
git add tests/test-structure.sh
git add docs/superpowers/plans/2026-05-20-two-tier-command-simplification.md
git commit -m "refactor(skills): 將 5 個 Horus 內部 skill 轉為 GUIDE.md，縮減 palette 命令數

隱藏 terraform-validate / terraform-security / helm-scaffold /
cicd-enhancer / repo-detect，改由 Horus agent 透過 Read 呼叫。
遷移/Ingress/Traefik 相關 skill 全部保留 SKILL.md（支援自然語言觸發）。
Palette: 17 → 12 commands。"
```

---

## Self-Review

**Spec coverage:**
- ✅ Hide 5 Horus-internal skills → Task 1
- ✅ Migration/Ingress/Traefik skills keep SKILL.md → untouched
- ✅ Horus pipelines updated to Read GUIDE.md → Task 2
- ✅ Horus agent definition updated → Task 3
- ✅ Tests pass → Task 4 + 5

**Risk:** `ingress-controller-install`, `ingress-migration-advisor`, `traefik-controller-decommission` were NOT in the original EXPECTED_SKILLS test array but are now added. Verify they exist before running tests.
