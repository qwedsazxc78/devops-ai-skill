#!/usr/bin/env python3
"""
classify_ingress.py — classify a Kubernetes Ingress manifest for *gateway-migrate.

Given a path to a YAML file containing one or more `kind: Ingress` documents,
emit one JSON line per Ingress to stdout with:

    {
      "file": "common.ingress/base/app.ingress.yaml",
      "documentIndex": 0,
      "name": "app-master",
      "namespace": "ingress-nginx",
      "classification": "master" | "minion" | "standalone" | "foreign" | "unknown",
      "reason": "<one-line justification>",
      "ingressClass": "nginx" | "traefik" | "gce" | null,
      "sourceClass": "nginx" | "traefik",
      "hosts": ["argocd.awoo.org", ...],
      "hasPaths": true | false,
      "hasTls": true | false,
      "mergeableIngressType": "master" | "minion" | null,
      "annotations": {"<key>": "<value>", ...}
    }

Classification rules (from references/master-minion-topology.md, mirrored in
SKILL.md Step 1):

  1. `nginx.ingress/mergeable-ingress-type: master` → master (strong)
  2. `spec.rules[].host` present AND no `spec.rules[].http.paths` anywhere → master (heuristic)
  3. `spec.rules[].http.paths[]` present AND no `spec.tls` AND ingress.class: nginx → minion
  4. `spec.rules[].host` + `spec.rules[].http.paths[]` + `spec.tls` → standalone
  5. `kubernetes.io/ingress.class` not in {nginx, traefik} (e.g. gce) → foreign (skipped by migration)
  6. Otherwise → unknown

Dependencies: Python 3 stdlib + `yq` on PATH (yq >= 4.x, shell syntax).

Usage:
    python3 classify_ingress.py <path-to-ingress.yaml> [--quiet]

Exit codes:
    0 — at least one Ingress classified
    1 — no `kind: Ingress` documents found in file
    2 — yq invocation failed (malformed YAML or yq missing)
"""
from __future__ import annotations

import json
import shutil
import subprocess
import sys
from pathlib import Path


def _die(msg: str, code: int = 2) -> None:
    print(f"[classify_ingress] {msg}", file=sys.stderr)
    sys.exit(code)


def _load_docs(path: Path) -> list[dict]:
    """Load all YAML documents from *path* as a list of dicts, via yq eval-all.

    Uses `yq ea '[.]' path` which emits a single JSON array containing
    every document in a multi-doc YAML stream. This is the idiomatic
    multi-doc collection pattern for yq v4+.
    """
    try:
        raw = subprocess.check_output(
            ["yq", "ea", "-o=json", "[.]", str(path)],
            text=True, stderr=subprocess.PIPE,
        )
    except FileNotFoundError:
        _die("yq not found on PATH — install with `brew install yq`")
    except subprocess.CalledProcessError as e:
        _die(f"yq failed on {path}: {e.stderr.strip()}")
    try:
        data = json.loads(raw or "[]")
    except json.JSONDecodeError as e:
        _die(f"yq produced non-JSON output for {path}: {e}")
    if isinstance(data, list):
        # yq ea '[.]' always returns a flat array of docs.
        return [d for d in data if isinstance(d, dict)]
    return [data] if isinstance(data, dict) else []


def _classify(doc: dict) -> tuple[str, str]:
    """Return (classification, reason)."""
    if doc.get("kind") != "Ingress":
        return "unknown", f"kind={doc.get('kind')!r} not Ingress"

    annotations = (doc.get("metadata") or {}).get("annotations") or {}
    ingress_class = annotations.get("kubernetes.io/ingress.class")
    # `spec.ingressClassName` is the modern field; honour it if present.
    spec = doc.get("spec") or {}
    if not ingress_class:
        ingress_class = spec.get("ingressClassName")

    # Rule 5 — foreign class (non-nginx, non-traefik)
    if ingress_class and ingress_class not in ("nginx", "traefik"):
        return "foreign", f"ingressClass={ingress_class!r} (skill targets nginx and traefik)"

    rules = spec.get("rules") or []
    has_host = any("host" in r for r in rules)
    has_paths = any(
        (r.get("http") or {}).get("paths") for r in rules
    )
    has_tls = bool(spec.get("tls"))
    mergeable = annotations.get("nginx.ingress/mergeable-ingress-type")

    # Rule 1 — strong master signal
    if mergeable == "master":
        return "master", "mergeable-ingress-type=master annotation"
    if mergeable == "minion":
        return "minion", "mergeable-ingress-type=minion annotation"

    # Rule 4 — standalone (path + tls in one resource)
    if has_host and has_paths and has_tls:
        return "standalone", "host+paths+tls in single Ingress"

    # Rule 2 — heuristic master
    if has_host and not has_paths:
        return "master", "host-only (heuristic; no paths anywhere)"

    # Rule 3 — minion
    if has_paths and not has_tls and (ingress_class == "nginx" or ingress_class is None):
        return "minion", "paths + no tls + nginx class"

    return "unknown", "no classification rule matched"


def _extract(doc: dict) -> dict:
    metadata = doc.get("metadata") or {}
    spec = doc.get("spec") or {}
    rules = spec.get("rules") or []
    annotations = metadata.get("annotations") or {}
    ingress_class = (
        annotations.get("kubernetes.io/ingress.class")
        or spec.get("ingressClassName")
    )
    source_class = "traefik" if ingress_class == "traefik" else "nginx"
    return {
        "name": metadata.get("name"),
        "namespace": metadata.get("namespace"),
        "ingressClass": ingress_class,
        "sourceClass": source_class,
        "hosts": [r["host"] for r in rules if "host" in r],
        "hasPaths": any((r.get("http") or {}).get("paths") for r in rules),
        "hasTls": bool(spec.get("tls")),
        "mergeableIngressType": annotations.get("nginx.ingress/mergeable-ingress-type"),
        "annotations": annotations,
    }


def main() -> int:
    args = sys.argv[1:]
    quiet = "--quiet" in args
    paths = [Path(a) for a in args if not a.startswith("--")]
    if not paths:
        print(__doc__, file=sys.stderr)
        return 2
    if not shutil.which("yq"):
        _die("yq not found on PATH")

    total = 0
    for path in paths:
        if not path.is_file():
            if not quiet:
                print(f"[classify_ingress] skip (not a file): {path}", file=sys.stderr)
            continue
        docs = _load_docs(path)
        for idx, doc in enumerate(docs):
            if doc.get("kind") != "Ingress":
                continue
            total += 1
            classification, reason = _classify(doc)
            row = {
                "file": str(path),
                "documentIndex": idx,
                "classification": classification,
                "reason": reason,
                **_extract(doc),
            }
            print(json.dumps(row, ensure_ascii=False))
    if total == 0:
        if not quiet:
            print("[classify_ingress] no Ingress resources found", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
