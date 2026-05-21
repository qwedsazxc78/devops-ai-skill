#!/usr/bin/env python3
"""
inventory_nginx_ingresses.py — list active nginx Ingresses in an overlay.

Scans an overlay directory for `kind: Ingress` documents and emits a JSON
array (single document on stdout) with one entry per Ingress:

  [{
    "file": "argocd-nginx-ingress.yaml",
    "name": "argocd-server",
    "namespace": "argocd",
    "ingressClass": "nginx" | "traefik" | null,
    "hosts": ["argocd.dev.example.com"],
    "backendServices": [{"service": "argocd-server", "port": 80}],
    "annotations": {"key": "value", ...}
  }, ...]

Already-migrated Traefik ingresses are emitted but flagged
`ingressClass == "traefik"` so the caller can filter.

Usage:
    inventory_nginx_ingresses.py --overlay-dir <path>
"""
from __future__ import annotations

import argparse
import json
import shutil
import subprocess
import sys
from pathlib import Path


def _yq_ea_json(path: Path) -> list[dict]:
    rc = subprocess.run(
        ["yq", "ea", "-o=json", "[.]", str(path)],
        capture_output=True, text=True,
    )
    if rc.returncode != 0:
        return []
    try:
        data = json.loads(rc.stdout or "[]")
    except json.JSONDecodeError:
        return []
    out: list[dict] = []
    if isinstance(data, list):
        for elem in data:
            if isinstance(elem, list):
                out.extend(d for d in elem if isinstance(d, dict))
            elif isinstance(elem, dict):
                out.append(elem)
    elif isinstance(data, dict):
        out.append(data)
    return out


def _ingress_class(doc: dict) -> str | None:
    ann = (doc.get("metadata") or {}).get("annotations") or {}
    spec = doc.get("spec") or {}
    return ann.get("kubernetes.io/ingress.class") or spec.get("ingressClassName")


def _extract(doc: dict, file: Path) -> dict:
    md = doc.get("metadata") or {}
    spec = doc.get("spec") or {}
    rules = spec.get("rules") or []
    backends: list[dict] = []
    for rule in rules:
        for p in (rule.get("http") or {}).get("paths", []) or []:
            svc = ((p.get("backend") or {}).get("service") or {})
            if svc.get("name"):
                backends.append({
                    "service": svc.get("name"),
                    "port": (svc.get("port") or {}).get("number"),
                })
    return {
        "file": file.name,
        "name": md.get("name"),
        "namespace": md.get("namespace"),
        "ingressClass": _ingress_class(doc),
        "hosts": [r["host"] for r in rules if "host" in r],
        "backendServices": backends,
        "annotations": md.get("annotations") or {},
    }


def main() -> int:
    p = argparse.ArgumentParser()
    p.add_argument("--overlay-dir", required=True, type=Path)
    args = p.parse_args()
    if not shutil.which("yq"):
        print("[inventory_nginx_ingresses] yq not found on PATH", file=sys.stderr)
        return 2
    if not args.overlay_dir.is_dir():
        print(f"[inventory_nginx_ingresses] not a directory: {args.overlay_dir}", file=sys.stderr)
        return 2
    rows: list[dict] = []
    for yaml in sorted(args.overlay_dir.glob("*.yaml")):
        for doc in _yq_ea_json(yaml):
            if doc.get("kind") == "Ingress":
                rows.append(_extract(doc, yaml))
    json.dump(rows, sys.stdout, ensure_ascii=False, indent=2)
    sys.stdout.write("\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
