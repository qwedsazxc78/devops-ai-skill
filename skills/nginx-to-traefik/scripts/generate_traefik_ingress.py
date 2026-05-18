#!/usr/bin/env python3
"""
generate_traefik_ingress.py — emit a Traefik Ingress from a source nginx Ingress.

Reads one Ingress document from --input, applies the translation rules from
references/annotation-translation.md, and writes the Traefik Ingress to
--output. Returns warnings on stderr (JSON lines).

Translation rules (see references/annotation-translation.md):
  Row 1  kubernetes.io/ingress.class: nginx → ingressClassName: traefik
  Row 2-3 ssl-redirect / force-ssl-redirect → DROP (info)
  Row 4  backend-protocol: HTTPS → service.serversscheme annotation
  Row 5  proxy-body-size → WARN, emit stub Middleware reference comment
  Row 6  cors-allow-origin → reuse cors@kubernetescrd Middleware if present, else stub + WARN
  Row 7  configuration-snippet → TODO comment + WARN
  Row 8-9 cert-manager.io/* → carry through
  Row 10 rewrite-target → translate single-segment; WARN otherwise

Usage:
    generate_traefik_ingress.py --input <nginx-ingress.yaml> --output <traefik-ingress.yaml>
"""
from __future__ import annotations

import argparse
import json
import subprocess
import sys
from pathlib import Path

DROP = {
    "kubernetes.io/ingress.class",
    "nginx.ingress.kubernetes.io/ssl-redirect",
    "nginx.ingress.kubernetes.io/force-ssl-redirect",
}
CARRY = {
    "cert-manager.io/cluster-issuer",
    "cert-manager.io/dns01-recursive-nameservers",
}


def _load(path: Path) -> dict:
    rc = subprocess.run(["yq", "ea", "-o=json", ".", str(path)], capture_output=True, text=True)
    if rc.returncode != 0:
        sys.stderr.write(rc.stderr)
        sys.exit(2)
    return json.loads(rc.stdout or "{}")


def _warn(msg: str) -> None:
    sys.stderr.write(json.dumps({"level": "WARN", "msg": msg}) + "\n")


def _translate_annotations(src: dict) -> tuple[dict, list[str]]:
    out: dict[str, str] = {}
    warns: list[str] = []
    for k, v in (src or {}).items():
        if k in DROP:
            continue
        if k in CARRY:
            out[k] = v
            continue
        if k == "nginx.ingress.kubernetes.io/backend-protocol" and v.upper() == "HTTPS":
            out["traefik.ingress.kubernetes.io/service.serversscheme"] = "https"
            continue
        if k == "nginx.ingress.kubernetes.io/proxy-body-size":
            warns.append(f"proxy-body-size={v} requires manual Middleware (buffering)")
            continue
        if k == "nginx.ingress.kubernetes.io/cors-allow-origin":
            warns.append(f"cors-allow-origin={v}: reuse cors@kubernetescrd Middleware (no auto-generation)")
            continue
        if k == "nginx.ingress.kubernetes.io/configuration-snippet":
            warns.append("configuration-snippet does not translate; emit Middleware manually")
            out[f"# TODO: {k}"] = v
            continue
        if k == "nginx.ingress.kubernetes.io/rewrite-target":
            if v.count("/") <= 1:
                warns.append(f"rewrite-target={v}: emit Middleware replacePathRegex manually")
            else:
                warns.append(f"rewrite-target={v}: multi-segment, manual review required")
            continue
        warns.append(f"unrecognised annotation dropped: {k}={v}")
    return out, warns


def _build_traefik(src: dict) -> dict:
    md = (src.get("metadata") or {}).copy()
    annotations, warns = _translate_annotations((md.get("annotations") or {}))
    for w in warns:
        _warn(w)
    md["annotations"] = annotations
    spec = (src.get("spec") or {}).copy()
    spec.pop("ingressClassName", None)
    new_spec = {"ingressClassName": "traefik"}
    for k in ("tls", "rules"):
        if k in spec:
            new_spec[k] = spec[k]
    return {
        "apiVersion": "networking.k8s.io/v1",
        "kind": "Ingress",
        "metadata": md,
        "spec": new_spec,
    }


def _write_yaml(doc: dict, out: Path) -> None:
    rc = subprocess.run(
        ["yq", "-P", "."],
        input=json.dumps(doc), capture_output=True, text=True,
    )
    if rc.returncode != 0:
        sys.stderr.write(rc.stderr)
        sys.exit(2)
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(rc.stdout)


def main() -> int:
    p = argparse.ArgumentParser()
    p.add_argument("--input", required=True, type=Path)
    p.add_argument("--output", required=True, type=Path)
    args = p.parse_args()
    src = _load(args.input)
    if src.get("kind") != "Ingress":
        print("[generate_traefik_ingress] input is not an Ingress", file=sys.stderr)
        return 2
    out = _build_traefik(src)
    _write_yaml(out, args.output)
    return 0


if __name__ == "__main__":
    sys.exit(main())
