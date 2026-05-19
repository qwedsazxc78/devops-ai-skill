# Decision Matrix — ingress-migration-advisor

Maps `(vetoed, sourceClass, totalScore)` → `(path, suggestedCommand)`.

Plain markdown data tables read at runtime by `scripts/score_services.py
--decide`. Edit via PR to adjust the matrix.

## 1. Decision order

The script evaluates rules in this order, returning the first match:

1. **Veto check** (from `scoring-model.md` §1) — if vetoed, return
   `path: defer` and skip the rest.
2. **sourceClass shortcut** — if `sourceClass == traefik`, return
   `path: direct-gateway` regardless of score.
3. **sourceClass == foreign** — return `path: defer` with
   `vetoReason: foreign-class` (e.g. `gce` ingress; not in scope for the
   nginx→traefik→gateway migration path).
4. **sourceClass == nginx** — apply the score-band table (§2 below).

## 2. Score-band table (nginx-source services only)

| Total score | Path | Risk bucket |
|---|---|---|
| 4–7 | `direct-gateway` | low |
| 8–10 | `two-step` | medium |
| 11–13 | `swap-only` | high |
| 14 | `defer` | very high |

## 3. Suggested command per (sourceClass, path)

| sourceClass | path | Suggested Zeus command |
|---|---|---|
| nginx | direct-gateway | `*gateway-migrate <module> --source-class nginx --gateway-class traefik` |
| nginx | two-step | `*nginx-to-gateway <env> --gateway-class traefik` |
| nginx | swap-only | `*nginx-to-traefik <env> <service>` |
| nginx | defer | _none — record in deferred section with rationale_ |
| traefik | direct-gateway | `*gateway-migrate <module> --source-class traefik --gateway-class traefik --no-redirect` |
| traefik | defer | _none — only happens if --target-path defer is forced_ |
| foreign | defer | _none — out of scope, see §1 step 3_ |

The `<module>`, `<env>`, and `<service>` placeholders are substituted at
plan-render time using values from `state.yaml.inventory[]` — typically:

- `<module>` → `common.service/overlays/<env>` (the parent of the
  HTTPRoute destination; resolved from `inventory[].modulePathPerEnv[env]`)
- `<env>` → first env where the service appears, in order
  dev → stg → prd (lowest-risk env first)
- `<service>` → `inventory[].service`

For services that span multiple envs, the plan emits **one command per
env** under the same batch, executed dev → stg → prd by the operator.

## 4. The `--target-path` override

When the operator invokes `*ingress-migration-advisor --target-path
<path>`:

- The veto in §1 step 1 still applies (critical services still defer).
- The sourceClass shortcut in §1 step 2 still applies (traefik-source
  still goes direct-gateway).
- For all other services, the override replaces the score-band lookup.
  The `advisoryPath` field still records what the score would have said,
  so the report shows both.

## 5. How to change the bands

To shift a band threshold (e.g., move the swap-only/defer boundary
from 14 to 13):

1. Edit §2 in this file via PR.
2. The script reads the table by parsing the markdown. No code change.
3. Verify with a re-run against a known repo that no service crosses
   the new boundary inappropriately.

To add a new path option (e.g., `gateway-direct-gke` for GKE Gateway
targets):

1. Add a row to §3 with the new path and command.
2. Add the path name to the SKILL.md validation list (currently
   `direct-gateway | two-step | swap-only | defer`).
3. Decide the score band in §2 that maps to it.
4. Update `scripts/render_plan.py` if the new path needs special
   formatting in the per-batch command block.
