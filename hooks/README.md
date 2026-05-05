# Hooks — DevOps AI Skill Pack

Auto-loaded by Claude Code v2.1+ when the plugin is installed. Four hooks wire the existing skills + agents into Claude's tool-use loop, turning the skill pack from "model-driven invocation" into deterministic event-driven feedback.

## Reference repos

The hooks are designed to be demoed against these companion repos:

| Repo | Role | URL |
|---|---|---|
| `iac-template-ai-skill` | Minimal GKE Terraform template — practice IaC with **Horus** | <https://github.com/qwedsazxc78/iac-template-ai-skill> |
| `gitops-template-ai-skill` | Kustomize + ArgoCD GitOps template — practice with **Zeus** | <https://github.com/qwedsazxc78/gitops-template-ai-skill> |
| `devops-ai-skill` | This skill pack — Horus (IaC) + Zeus (GitOps) for Claude Code, Codex, Gemini CLI | <https://github.com/qwedsazxc78/devops-ai-skill> |

Workshop demo branch on the two template repos: `demo-conditioned/2026-ithome-devopsday`.

## Design philosophy

- **Read-only by default.** 3 of 4 hooks only print suggestions to stderr. They cannot block your work.
- **One gate, not many.** Only `pre-bash-destructive-guard.sh` interrupts — and it asks rather than denies. The audience learns judgment, not handcuffs.
- **Skills do the deep work; hooks fire the fast feedback.** Hooks run inline shell checks (~ms). Skills (`yaml-fix-suggestions`, `terraform-validate`, etc.) provide the full diagnostic when invoked.
- **Quiet on irrelevant repos.** All 4 hooks bail early when triggers don't apply (no DevOps signals, wrong file extension, outside Kustomize tree, etc.).

## The 4 hooks

| # | Event | Matcher | Script | Skill mapping | Mode |
|---|---|---|---|---|---|
| H1 | `SessionStart` | — | `session-start-repo-detect.sh` | `repo-detect` | advisory |
| H2 | `PostToolUse` | `Edit\|Write` | `post-edit-yaml-check.sh` | `yaml-fix-suggestions` | advisory |
| H3 | `PostToolUse` | `Edit\|Write` | `post-edit-terraform-check.sh` | `terraform-validate` | advisory |
| H4 | `PreToolUse` | `Bash` | `pre-bash-destructive-guard.sh` | `terraform-security` (spirit) | gate (`ask`) |

### H1 — Repo detection on session start

Scans `cwd` (depth-limited) for Terraform / Kustomize / Helm / ArgoCD signals. If any are present, injects `additionalContext` telling Claude which agent to default to (`/devops:horus` for IaC, `/devops:zeus` for GitOps) and links the 3 reference repos.

**Stays silent** on non-DevOps repos — won't pollute unrelated projects.

### H2 — YAML lint after edits

Fires after `Edit` / `Write` on `.yaml` / `.yml` files **inside Kustomize-shaped trees** (parent has `kustomization.yaml`). Runs `yamllint --no-warnings` if available; falls back to basic tab/trailing-whitespace checks otherwise.

Skips `.claude/`, `.bmad-*/`, `node_modules/`, `.git/`, `.terraform/`.

### H3 — Terraform fmt + tflint after edits

Fires after `Edit` / `Write` on `.tf` / `.tfvars`. Runs `terraform fmt -check` and (if `.tflint.hcl` exists in the tree) `tflint`. Both are read-only.

Skips `.terraform/` (state cache) and the usual noise paths.

### H4 — Destructive Bash guard

Fires before any `Bash` tool call. Matches these patterns with proper word boundaries:

- `terraform apply`
- `terraform destroy`
- `helm uninstall`
- `kubectl delete`
- `argocd app delete`

Returns `permissionDecision: "ask"` with a per-pattern dry-run suggestion (e.g., for `terraform apply` → "Consider: `terraform plan -out=tfplan` first, then `terraform apply tfplan`"). User can confirm or cancel from the Claude Code UI.

False-positives mitigated: `kubectl deletex` does **not** match. Chained commands (`echo hi && kubectl delete pod`) **do** match.

## Testing the hooks manually

```bash
# H1 — should print SessionStart JSON when run inside a Terraform / Kustomize repo
bash hooks/session-start-repo-detect.sh

# H2 — feed a fake Edit event
echo '{"tool_input":{"file_path":"/path/to/edited.yaml"}}' | bash hooks/post-edit-yaml-check.sh

# H3 — feed a fake Edit event on .tf
echo '{"tool_input":{"file_path":"/path/to/main.tf"}}' | bash hooks/post-edit-terraform-check.sh

# H4 — should output ask JSON
echo '{"tool_input":{"command":"terraform apply"}}' | bash hooks/pre-bash-destructive-guard.sh
```

## Disabling

To disable an individual hook, remove its entry from `hooks.json`. To disable all hooks, rename `hooks.json` → `hooks.json.disabled` (Claude Code only auto-loads files literally named `hooks.json`).

To override per project, add a project-level `.claude/settings.json` with `"hooks": { ... }` — project hooks layer on top of plugin hooks.

## Dependencies

| Tool | Used by | Required? |
|---|---|---|
| `python3` | All hooks (JSON parsing) | Yes — ships with macOS, standard on Linux dev images |
| `yamllint` | H2 | Optional — falls back to grep-based checks |
| `terraform` | H3 | Optional — H3 silently skips if missing |
| `tflint` | H3 | Optional — H3 silently skips if missing |
| `jq` | — | Not used (avoided to reduce dep surface) |

## Related

- Plugin manifest: [`.claude-plugin/plugin.json`](../.claude-plugin/plugin.json)
- Agents: [`.claude/agents/horus.md`](../.claude/agents/horus.md), [`.claude/agents/zeus.md`](../.claude/agents/zeus.md)
- Full skill list: [`skills/`](../skills/)
