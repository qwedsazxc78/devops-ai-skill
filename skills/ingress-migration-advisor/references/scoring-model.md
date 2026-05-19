# Scoring Model — ingress-migration-advisor

Plain markdown data tables read at runtime by `scripts/score_services.py`.
Edit this file via PR to adjust weights; no code change required.

## 1. Veto rule — critical traffic tier

Any service whose tier (from `docs/ingress-tier-map.yaml`) equals
`critical` is **vetoed**: forced to `defer` regardless of any dimension
score. The planner records:

- `scores[].vetoed: true`
- `scores[].vetoReason: critical-tier`
- `decisions[].path: defer`
- `decisions[].advisoryPath: <what-score-would-say>` (for the report's
  deferred / risk-register section)

There is no `--force-critical` bypass flag. To migrate a critical
service in a given cycle, the team PRs the tier map first.

## 2. Dimensional rubric — non-vetoed services

Each dimension scores 1 (low risk), 2 (medium), or 3 (high). Weights are
equal — sum the dimensions for `scores[].total`. Total range: **4–14**.
Traffic tier caps at 2 because tier-3 = critical = veto, never reaches
the rubric.

### Dimension 1 — Annotation complexity

Counts: total annotations + estimated unknown count. Estimation uses
`gateway-api-migration/references/annotation-map.md` row presence. An
annotation is "unknown" if its key matches none of the documented rows.

| Score | Criteria |
|---|---|
| 1 | ≤ 5 total annotations AND 0 unknown |
| 2 | 6–15 total OR 1–2 unknown |
| 3 | > 15 total OR > 2 unknown |

### Dimension 2 — TLS mode

How the Ingress terminates TLS today.

| Score | Criteria |
|---|---|
| 1 | `spec.tls[].secretName` references a cert-manager Secret |
| 2 | Uses `networking.gke.io/managed-certificates` annotation (GKE ManagedCertificate) |
| 3 | Mixed (some hosts secret, some managed-cert) OR no TLS at all |

### Dimension 3 — Hostname count per env

Maximum across envs (a service with 4 hosts in prd but 1 in dev scores 3).

| Score | Criteria |
|---|---|
| 1 | 1 host |
| 2 | 2–3 hosts |
| 3 | ≥ 4 hosts |

### Dimension 4 — Traffic tier

From `docs/ingress-tier-map.yaml`. Caps at 2 — score-3 is reserved for
the veto path (§1).

| Score | Criteria |
|---|---|
| 1 | `low` |
| 2 | `standard` (also the default for unlisted services) |
| —  | `critical` → see §1 veto rule |

### Dimension 5 — Auth/CORS/security annotations

Count of distinct security-relevant annotation categories present:

- CORS (any `cors-*` or `enable-cors`)
- Auth (any `auth-*`, `basic-auth`, `whitelist-source-range`)
- Security headers (any `*-snippet` containing security header
  manipulation per `annotation-map.md` row 9a)
- WAF / cert-only (`force-ssl-redirect`, `ssl-passthrough`)

| Score | Criteria |
|---|---|
| 1 | 0 categories present |
| 2 | exactly 1 category present |
| 3 | 2+ categories present |

## 3. Score boundaries

Per-dimension: 1, 2, or 3. Five dimensions × cap of 3 each = max 15;
but traffic tier caps at 2, so effective max = 14. Minimum = 4 (all
ones except traffic tier ≥ 1).

| Range | Bucket |
|---|---|
| 4–7 | low risk |
| 8–10 | medium risk |
| 11–13 | high risk |
| 14 | very high risk |

Buckets map to migration paths via `decision-matrix.md`.

## 4. How to change the weights

To reweight a dimension:

1. Edit this file via PR. Adjust the per-dimension criteria or add a
   sixth dimension.
2. If you add a sixth dimension, update the boundaries in §3 to reflect
   the new max (e.g., five dims @ 3 + one new dim @ 3 = max 17, capped
   at 16 for traffic tier).
3. Run the advisor against a known repo and check that the per-service
   `rationale` strings in the rendered plan still read plausibly.

The script `score_services.py` parses this markdown table-by-table at
runtime. Heuristic rules and pattern lists are also read from here — no
constants live in Python source.
