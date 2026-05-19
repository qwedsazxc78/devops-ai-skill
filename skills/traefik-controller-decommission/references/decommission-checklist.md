# Decommission Checklist — ingress-nginx Controller Uninstall

Operator-facing manual checklist. The `traefik-controller-decommission`
skill generates `plan.md` and `commands.sh` based on this document; the
operator runs every command below by hand.

## Pre-uninstall invariants

Before touching `helm uninstall`, all of the following must be true:

1. **Zero `ingressClassName: nginx` Ingresses in the live cluster** —
   confirmed by `scripts/verify_no_nginx_class.sh --cluster`.
2. **Zero nginx Ingresses in any `kustomize build` output** — confirmed by
   `scripts/verify_no_nginx_class.sh --repo`.
3. **All `*-nginx-ingress.yaml` files are under `archive/`** and not
   referenced from any `kustomization.resources[]`.
4. **DNS bake elapsed** — every hostname has resolved to the Traefik LB IP
   for ≥72h and the nginx LB has logged zero non-monitoring traffic in that
   window.
5. **Backout plan documented** — operator knows how to re-install the
   chart from the snapshot in Section 1, Step 2.

If any invariant fails, STOP. The skill will already have refused to write
`commands.sh`; the report in `plan.md` lists what is blocking.

## Section 1 — Helm uninstall

### Step 1: Idempotency check
```bash
helm status <release> -n <namespace>
```
Expected: release found, status `deployed`. If the release is missing,
someone already uninstalled — verify nothing else points at the nginx LB
and skip to Section 2.

### Step 2: Snapshot current values (audit trail + backout)
```bash
helm get values <release> -n <namespace> -o yaml \
  > docs/reports/traefik-controller-decommission/<date>/nginx-values-snapshot.yaml
git add docs/reports/traefik-controller-decommission/<date>/nginx-values-snapshot.yaml
```
Commit this snapshot **before** uninstalling. If you ever need to roll
back, this file is the canonical `helm install -f` argument.

### Step 3: Uninstall
```bash
helm uninstall <release> -n <namespace> --wait
```
The `--wait` flag blocks until Kubernetes reaps the Service, Deployment,
ConfigMap, RBAC objects, etc. Without `--wait` the LB IP release in
Section 2 may race the reaper.

### Step 4: Drop the namespace (only if empty)
```bash
kubectl get all -n <namespace>
# If the output is empty:
kubectl delete namespace <namespace>
```
Some platforms park unrelated workloads in `ingress-nginx`. NEVER delete a
non-empty namespace.

## Section 2 — LB IP release (GKE)

### Step 1: Identify the address
```bash
gcloud compute addresses list --project <gcpProject> \
  --filter="address=<nginxLbIp>"
```
- If the address is `RESERVED` with no `users[]`, it is safe to release.
- If `IN_USE`, a forwarding rule still references it — confirm with the
  next command before deleting.

### Step 2: Find any lingering forwarding rules / target pools
```bash
gcloud compute forwarding-rules list --project <gcpProject> \
  --filter="IPAddress=<nginxLbIp>"
gcloud compute target-pools list --project <gcpProject>
```
The `helm uninstall` in Section 1 normally reaps these via the GKE
Service-controller. If anything remains here, the controller crashed
mid-reap — delete the forwarding rule first, then the target pool, then
retry the address release.

### Step 3: Release the static address (if reserved)
```bash
gcloud compute addresses delete <address-name> \
  --region <region> --project <gcpProject>
```
Skip this step if the address was ephemeral (no `addresses.create` was
ever run for it).

## Section 3 — IAM cleanup

### Step 1: Find candidate service accounts
```bash
gcloud iam service-accounts list --project <gcpProject> \
  --filter="email~ingress-nginx"
```
The chart commonly creates an SA named `ingress-nginx-controller` or
`ingress-nginx@<project>.iam.gserviceaccount.com`. Verify it was created
**for** the nginx controller before deleting — some platforms share an SA
across controllers.

### Step 2: Audit bindings before deletion
```bash
gcloud projects get-iam-policy <gcpProject> \
  --flatten="bindings[].members" \
  --filter="bindings.members:serviceAccount:<sa-email>"
```
Record every `role` returned. Each must be removed individually.

### Step 3: Remove bindings and delete SA
```bash
gcloud projects remove-iam-policy-binding <gcpProject> \
  --member=serviceAccount:<sa-email> --role=<role>
gcloud iam service-accounts delete <sa-email> --project <gcpProject>
```
Run the binding removal once per role listed in Step 2. Only after all
bindings are clean should the SA itself be deleted.

## Backout — re-installing nginx-ingress

If the post-uninstall verification surfaces traffic that still expected
nginx (e.g. a missed Ingress in a non-tracked namespace), re-install:

```bash
helm install <release> ingress-nginx/ingress-nginx \
  -n <namespace> --create-namespace \
  -f docs/reports/traefik-controller-decommission/<date>/nginx-values-snapshot.yaml
```

The snapshot from Section 1 Step 2 is the source of truth for the
restored configuration. The previous static LB IP is unrecoverable once
released — the restored Service will be assigned a new IP, and the
mis-classed Ingresses will need their DNS pointed at the new IP.

## Post-uninstall verification

```bash
kubectl get pods -n <namespace>                     # expect: not found
kubectl get ingressclass nginx                      # expect: not found
kubectl get svc -A | grep -i nginx                  # expect: empty
helm list -A | grep -i ingress-nginx                # expect: empty
gcloud compute addresses list --project <gcpProject> \
  --filter="address=<nginxLbIp>"                    # expect: empty
```

All five must return empty. If any returns a row, STOP and investigate
before closing the migration cycle.
