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
