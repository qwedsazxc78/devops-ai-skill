# gateway-api-migration — NGINX Ingress → Gateway API (Traefik default, GKE opt-in)

Direct-entry slash command for the one-time migration from NGINX Ingress
(master/minion or standalone) to Gateway API. **Dual-target since v1.2.0**:
the default GatewayClass is `traefik` (Traefik v3.1+); pass
`--gateway-class gke-l7-global-external-managed` (or any other class
prefix) to opt into GKE Gateway or other controllers. Equivalent to
invoking Zeus and running `*gateway-migrate` — same pipeline, same skill,
same safety rules, but without the Zeus greeting and `*help` menu.

## Activation

1. **Silently adopt Zeus operational rules** (do NOT greet, do NOT show
   `*help`, do NOT introduce yourself as Zeus). Load these sections from
   `.claude/agents/zeus.md` as in-context rules for this command only:
   - Core Principles (Validate Before Deploy, Graceful Degradation,
     Pipeline-First, Fail Safe)
   - Critical Rules (1–7)
   - Error Recovery (halt-and-ask on blockers, continue on warnings,
     per-environment isolation)
   - Communication Style (lead with action + result, tables for
     summaries, bold blockers, numbered choices)
2. Load the migration pipeline from `prompts/zeus/gateway-migrate.md` —
   this is the 8-step orchestrator.
3. Load the skill from `skills/gateway-api-migration/SKILL.md` — this is
   the logic referenced by every pipeline step.
4. Parse `$ARGUMENTS` for the invocation form (see below) and jump
   straight into **Step 1: Tool Check**. No greeting, no menu.
5. Run the pipeline step by step, gating at every halt point defined in
   the skill. On any blocker, use the Error Recovery protocol from
   `.claude/agents/zeus.md` — report findings, then offer
   `(a) fix and retry`, `(b) skip and continue`, `(c) abort`.

## Invocation forms

`$ARGUMENTS` is forwarded verbatim to the pipeline — the four accepted
shapes are:

```
/devops:gateway-api-migration                         # interactive discovery mode
/devops:gateway-api-migration <module-path>           # explicit target
/devops:gateway-api-migration <module-path> --resume  # resume from state.yaml
/devops:gateway-api-migration <module-path> --force   # bypass never-clobber
```

These are intentionally identical to Zeus's `*gateway-migrate <args>`
forms so the two entry points stay compatible.

## Compatibility with Zeus `*gateway-migrate`

| Entry point | Identity | Greeting | `*help` menu | Pipeline | Skill |
|---|---|---|---|---|---|
| `/devops:zeus` → `*gateway-migrate` | Full Zeus persona | Yes | Yes | `prompts/zeus/gateway-migrate.md` | `skills/gateway-api-migration/` |
| `/devops:gateway-api-migration` | Zeus rules only (silent) | No | No | `prompts/zeus/gateway-migrate.md` | `skills/gateway-api-migration/` |

Both paths execute the same pipeline, delegate to the same skill, apply
the same Critical Rules, and halt at the same gates. The only difference
is ceremony — the slash command skips the persona boot so CI or
muscle-memory users can go straight to work.

## Output contract

- Start with the pipeline's Step 1 output, not a greeting.
- Use tables for the Step 2 annotation summary and Step 4 validation
  results.
- Bold every blocker.
- End with the Step 7 pre-commit hints block (commit message draft + the
  `git add` commands). **Never auto-commit** — the user drives git.

## Reference

See `skills/gateway-api-migration/SKILL.md` for the full halt/resume
semantics, state YAML schema, annotation classification rules, and the
master/minion topology detector.
