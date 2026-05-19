# ingress-to-gateway Pipeline

Generic Ingress → Gateway API migration. Auto-detects whether the target
module is on `ingressClassName: nginx` or `ingressClassName: traefik`,
then delegates to the `gateway-api-migration` skill with the right
`--source-class` flag. Useful when the operator doesn't want to think
about source class — just "migrate this module to Gateway API".

This is **slash-command sugar** for `*gateway-migrate`. It owns no
conversion logic; the actual work happens in `gateway-api-migration`.

## When to use

- The repo has services on a mix of nginx and traefik Ingresses, and you
  don't want to track which is which per module.
- You just shipped a class-swap via `*nginx-to-traefik` and want to
  continue to the Gateway phase without remembering to pass
  `--source-class traefik --no-redirect`.

For explicit control (manual source class, manual redirect flag), use
`*gateway-migrate <module>` directly.

## Pipeline Steps

### Step 1: Tool Check

- Verify `kustomize`, `yq`, `git`, `python3`, `kubectl`, `jq`
- Gate: HALT on missing required tools

### Step 2: Pre-scan source class

Run the gateway-api-migration skill's classifier in built-overlay mode
against the target module:

```bash
mkdir -p /tmp/i2g/built
kustomize build "<module>" 2>/dev/null \
  | yq ea '[select(.kind == "Ingress")] | .[] | split_doc' - > /tmp/i2g/built.yaml

python3 skills/gateway-api-migration/scripts/classify_ingress.py \
  /tmp/i2g/built.yaml --quiet > /tmp/i2g/classified.jsonl
```

Compute the source-class distribution:

```bash
jq -r '.sourceClass' /tmp/i2g/classified.jsonl | sort | uniq -c
```

### Step 3: Route to gateway-api-migration

Decision tree based on the distribution:

| Source-class state | Action |
|---|---|
| Only `nginx` | Invoke `*gateway-migrate <module> --source-class nginx --gateway-class traefik` |
| Only `traefik` | Invoke `*gateway-migrate <module> --source-class traefik --gateway-class traefik --no-redirect` |
| Mixed (both nginx + traefik) | **WARN**. Present count breakdown. Ask operator: (a) pick one class (process other in a follow-up), (b) accept default `nginx` (skips traefik Ingresses via classifier), or (c) abort. HALT on (c). |
| Only `foreign` (gce, etc.) | HALT — out of scope for this pipeline |

Pass through any additional flags the operator supplied
(`--gateway-class`, `--force`, `--resume`, `--offline`, etc.).

### Step 4: Delegate

Hand off to the `gateway-api-migration` skill. From this point forward,
the behaviour is identical to invoking `*gateway-migrate` directly — see
that skill's report, artifacts, and halt semantics.

## Invocation Reference

```
*ingress-to-gateway <module>                                   # auto-detect
*ingress-to-gateway <module> --gateway-class gke-l7-rilb       # override target
*ingress-to-gateway <module> --resume                          # forwarded to gateway-api-migration
*ingress-to-gateway <module> --source-class nginx              # override auto-detect
```

The `--source-class` flag overrides auto-detection. Useful when the
module is mixed and you want to process one class at a time.

## Output Artifacts

Same as `*gateway-migrate` — see `prompts/zeus/gateway-migrate.md`. This
pipeline writes nothing of its own; all artifacts come from the
delegated skill.
