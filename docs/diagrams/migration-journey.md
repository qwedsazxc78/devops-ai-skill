# Migration Journey — ingress-nginx → Traefik → Gateway API

The Zeus migration commands move a cluster through four states. ingress-nginx EOL
(2025) is the forcing function; the journey is gradual and DNS-reversible.

```mermaid
stateDiagram-v2
  [*] --> S0
  S0: S0 · only ingress-nginx
  S1: S1 · both controllers
  S2: S2 · mixed classes
  S3: S3 · only Traefik

  S0 --> S1: *install-traefik
  S1 --> S1: *ingress-migration-advisor<br/>(whole-repo plan)
  S1 --> S2: *nginx-to-traefik &lt;env&gt;<br/>(class swap)
  S1 --> S2: *nginx-to-gateway &lt;env&gt;<br/>(full chain)
  S2 --> S2: *ingress-to-gateway &lt;module&gt;<br/>(auto-detect source)
  S2 --> S3: (DNS cutover complete)
  S3 --> [*]: *decommission-nginx
```

**7 commands:** `*install-traefik`, `*ingress-migration-advisor`, `*nginx-to-traefik`,
`*nginx-to-gateway`, `*ingress-to-gateway`, `*decommission-nginx`, plus
`*migration-quickstart` for orientation. See [diagrams-guide.md](../diagrams-guide.md).
