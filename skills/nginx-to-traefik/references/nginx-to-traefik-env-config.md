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
