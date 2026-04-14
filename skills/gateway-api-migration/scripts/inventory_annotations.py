#!/usr/bin/env python3
"""
inventory_annotations.py — three-bucket annotation audit for *gateway-migrate.

For every annotation on every Ingress in the migration footprint, classify
into one of three buckets by consulting `references/annotation-map.md`:

    - translated:       row in map, non-stub category
    - stubbed:          row in map, split-category(stub) — needs manual review
    - unknown:          annotation not in map at all — DROPPED silently today

The third bucket is the critical one. Today's SKILL.md never reports unknown
annotations; they vanish during generation. This script surfaces them with
file:line provenance so the migration report's Section 4.4 can list them.

Usage:
    python3 inventory_annotations.py <path1.yaml> <path2.yaml> ...
    python3 inventory_annotations.py --files-from ingress-files.txt

Output: JSON to stdout.

    {
      "translated":      [{"row": 1, "annotation": "...", "value": "...",
                           "file": "...", "line": 12, "category": "portable"}],
      "translatedLossy": [{"row": 10, ...}],
      "stubbed":         [{"row": 9, "pattern": "9b-set-cookie", ...}],
      "unknown":         [{"annotation": "nginx.ingress.kubernetes.io/proxy-body-size",
                           "value": "100m", "file": "...", "line": 7}],
      "dropInfo":        [{"row": 4, ...}],
      "summary": {
        "totalAnnotations": 47,
        "translated": 38, "translatedLossy": 2,
        "stubbed": 3, "unknown": 4, "dropInfo": 0
      }
    }

Exit codes:
    0 — inventory complete (may have unknowns — they're reported, not failed)
    1 — bad input (file unreadable, etc.)
    2 — yq missing or malformed YAML
"""
from __future__ import annotations

import json
import re
import shutil
import subprocess
import sys
from pathlib import Path


# -----------------------------------------------------------------------------
# Annotation map — mirrors references/annotation-map.md
# -----------------------------------------------------------------------------
# Each entry: (match_kind, pattern, row, category, target_description)
# match_kind: "exact"  — annotation key exactly equals pattern
#             "prefix" — annotation key starts with pattern
#             "snippet" — key is `*server-snippet*`, value inspected by _classify_snippet

ANNOTATION_MAP: list[dict] = [
    {"row": 1,  "match": "exact",  "key": "kubernetes.io/ingress.class",
     "category": "portable", "target": "Gateway.spec.gatewayClassName"},
    {"row": 2,  "match": "prefix", "key": "cert-manager.io/",
     "category": "portable", "target": "preserved on Certificate CR"},
    {"row": 3,  "match": "exact",  "key": "networking.gke.io/managed-certificates",
     "category": "portable-GKE", "target": "listener.tls.certificateRefs[kind=ManagedCertificate]"},
    {"row": 4,  "match": "exact",  "key": "nginx.ingress/mergeable-ingress-type",
     "category": "drop-info", "target": "HTTPRoute merges natively via parentRef"},
    {"row": 4,  "match": "exact",  "key": "nginx.ingress.kubernetes.io/mergeable-ingress-type",
     "category": "drop-info", "target": "HTTPRoute merges natively via parentRef"},
    {"row": 5,  "match": "exact",  "key": "nginx.ingress.kubernetes.io/enable-cors",
     "category": "convertible", "target": "GCPBackendPolicy.spec.cors enabled"},
    {"row": 6,  "match": "exact",  "key": "nginx.ingress.kubernetes.io/cors-allow-origin",
     "category": "convertible", "target": "GCPBackendPolicy.spec.cors.allowOrigins"},
    {"row": 7,  "match": "exact",  "key": "nginx.ingress.kubernetes.io/cors-allow-methods",
     "category": "convertible", "target": "GCPBackendPolicy.spec.cors.allowMethods"},
    {"row": 8,  "match": "exact",  "key": "nginx.ingress.kubernetes.io/cors-allow-headers",
     "category": "convertible", "target": "GCPBackendPolicy.spec.cors.allowHeaders"},
    {"row": 9,  "match": "snippet", "key": "server-snippet",
     "category": "split-category", "target": "auto: HTTPRoute.filters; stubs: manual review"},
    {"row": 10, "match": "prefix", "key": "nginx.org/proxy-connect-timeout",
     "category": "convertible-lossy", "target": "GCPBackendPolicy.spec.timeoutSec (max of 3)"},
    {"row": 10, "match": "prefix", "key": "nginx.org/proxy-read-timeout",
     "category": "convertible-lossy", "target": "GCPBackendPolicy.spec.timeoutSec (max of 3)"},
    {"row": 10, "match": "prefix", "key": "nginx.org/proxy-send-timeout",
     "category": "convertible-lossy", "target": "GCPBackendPolicy.spec.timeoutSec (max of 3)"},
    {"row": 10, "match": "prefix", "key": "nginx.ingress.kubernetes.io/proxy-connect-timeout",
     "category": "convertible-lossy", "target": "GCPBackendPolicy.spec.timeoutSec"},
    {"row": 10, "match": "prefix", "key": "nginx.ingress.kubernetes.io/proxy-read-timeout",
     "category": "convertible-lossy", "target": "GCPBackendPolicy.spec.timeoutSec"},
    {"row": 10, "match": "prefix", "key": "nginx.ingress.kubernetes.io/proxy-send-timeout",
     "category": "convertible-lossy", "target": "GCPBackendPolicy.spec.timeoutSec"},
]


# -----------------------------------------------------------------------------
# server-snippet sub-classification (row 9 a/b/c from annotation-map.md)
# -----------------------------------------------------------------------------

_SECURITY_HEADERS = {
    "X-Content-Type-Options",
    "X-XSS-Protection",
    "X-Frame-Options",
}

_ADD_HEADER_RE = re.compile(r"add_header\s+([^\s]+)\s+", re.IGNORECASE)

# Match any `location ~ <pattern> { ... return 404 ... }` block. The real-world
# shape has other directives between the opening `{` and `return 404` — most
# commonly `deny all;`, sometimes `access_log off;`, `error_log ...;`, etc. —
# so the body matcher is `[^}]*?` (lazy, any non-}) rather than `\s*`. Without
# this, a block like
#
#     location ~ \.(ht|env)$ {
#       deny all;
#       return 404;
#     }
#
# silently does not match and the migration report omits a manual-review item.
# Uses findall() (not search()) in _classify_snippet so every location block
# in a snippet becomes its own report entry.
_LOCATION_DENY_RE = re.compile(
    r"location\s+~\s+[^{]+\{[^}]*?return\s+404",
    re.IGNORECASE | re.DOTALL,
)


def _classify_snippet(value: str) -> list[dict]:
    """Break a server-snippet value into 9a/9b/9c sub-entries."""
    results: list[dict] = []
    if not value:
        return results

    add_headers = _ADD_HEADER_RE.findall(value)
    for name in add_headers:
        if name in _SECURITY_HEADERS:
            results.append({
                "pattern": "9a-security-header",
                "category": "split-category (auto)",
                "headerName": name,
                "stubbed": False,
            })
        elif name == "Set-Cookie":
            results.append({
                "pattern": "9b-set-cookie",
                "category": "split-category (stub)",
                "headerName": name,
                "stubbed": True,
            })
        # Other add_header values → unknown sub-pattern; track as stub with pattern "9-other"
        else:
            results.append({
                "pattern": "9-other-add-header",
                "category": "split-category (stub)",
                "headerName": name,
                "stubbed": True,
            })

    # One entry per location block — a master can declare several denylists
    # (e.g., one for file extensions, one for path prefixes).
    for _ in _LOCATION_DENY_RE.findall(value):
        results.append({
            "pattern": "9c-path-denylist",
            "category": "split-category (stub)",
            "stubbed": True,
        })

    if not results:
        results.append({
            "pattern": "9-unknown-snippet",
            "category": "split-category (stub)",
            "stubbed": True,
        })
    return results


# -----------------------------------------------------------------------------
# File parsing
# -----------------------------------------------------------------------------

def _load_docs(path: Path) -> list[dict]:
    try:
        raw = subprocess.check_output(
            ["yq", "ea", "-o=json", "[.]", str(path)],
            text=True, stderr=subprocess.PIPE,
        )
    except FileNotFoundError:
        print("[inventory_annotations] yq not found on PATH", file=sys.stderr)
        sys.exit(2)
    except subprocess.CalledProcessError as e:
        print(f"[inventory_annotations] yq failed on {path}: {e.stderr}",
              file=sys.stderr)
        sys.exit(2)
    data = json.loads(raw)
    if isinstance(data, list) and data and isinstance(data[0], list):
        return [d for d in data[0] if isinstance(d, dict)]
    if isinstance(data, list):
        return [d for d in data if isinstance(d, dict)]
    return [data] if isinstance(data, dict) else []


def _find_line(path: Path, annotation_key: str) -> int:
    """Approximate line number where the annotation key appears."""
    try:
        text = path.read_text(encoding="utf-8")
    except OSError:
        return 0
    for i, line in enumerate(text.splitlines(), start=1):
        if annotation_key in line:
            return i
    return 0


# -----------------------------------------------------------------------------
# Classification
# -----------------------------------------------------------------------------

def _match_map_entry(key: str) -> dict | None:
    """Return the first annotation-map entry matching `key`, or None."""
    for entry in ANNOTATION_MAP:
        if entry["match"] == "exact" and entry["key"] == key:
            return entry
        if entry["match"] == "prefix" and key.startswith(entry["key"]):
            return entry
        if entry["match"] == "snippet" and "server-snippet" in key:
            return entry
    return None


def _bucket(category: str) -> str:
    if category == "drop-info":
        return "dropInfo"
    if category == "convertible-lossy":
        return "translatedLossy"
    if "stub" in category:
        return "stubbed"
    return "translated"


# -----------------------------------------------------------------------------
# Main
# -----------------------------------------------------------------------------

def _collect_paths(argv: list[str]) -> list[Path]:
    paths: list[Path] = []
    i = 0
    while i < len(argv):
        if argv[i] == "--files-from":
            with open(argv[i + 1], encoding="utf-8") as fh:
                for line in fh:
                    p = line.strip()
                    if p:
                        paths.append(Path(p))
            i += 2
            continue
        if argv[i].startswith("--"):
            i += 1
            continue
        paths.append(Path(argv[i]))
        i += 1
    return paths


def main() -> int:
    argv = sys.argv[1:]
    if not argv:
        print(__doc__, file=sys.stderr)
        return 1
    if not shutil.which("yq"):
        print("[inventory_annotations] yq not found on PATH", file=sys.stderr)
        return 2

    paths = _collect_paths(argv)
    if not paths:
        print("[inventory_annotations] no input paths", file=sys.stderr)
        return 1

    buckets: dict[str, list] = {
        "translated": [],
        "translatedLossy": [],
        "stubbed": [],
        "unknown": [],
        "dropInfo": [],
    }

    for path in paths:
        if not path.is_file():
            print(f"[inventory_annotations] skip (not a file): {path}",
                  file=sys.stderr)
            continue
        docs = _load_docs(path)
        for doc in docs:
            if doc.get("kind") != "Ingress":
                continue
            metadata = doc.get("metadata") or {}
            annotations = metadata.get("annotations") or {}
            res_name = metadata.get("name", "unknown")
            res_ns = metadata.get("namespace", "")

            for key, value in annotations.items():
                line = _find_line(path, key)
                entry = _match_map_entry(key)
                if entry is None:
                    # Row 5 prefix catch-all: skip common kubernetes labels we know are benign
                    if key.startswith("kubectl.kubernetes.io/") or \
                       key.startswith("meta.helm.sh/") or \
                       key.startswith("app.kubernetes.io/"):
                        continue
                    buckets["unknown"].append({
                        "annotation": key,
                        "value": value,
                        "file": str(path),
                        "line": line,
                        "resource": res_name,
                        "namespace": res_ns,
                    })
                    continue

                # snippet — sub-classify
                if entry["match"] == "snippet":
                    sub_entries = _classify_snippet(str(value))
                    for sub in sub_entries:
                        bucket_name = "stubbed" if sub["stubbed"] else "translated"
                        buckets[bucket_name].append({
                            "row": entry["row"],
                            "pattern": sub["pattern"],
                            "annotation": key,
                            "category": sub["category"],
                            "target": entry["target"],
                            "headerName": sub.get("headerName"),
                            "file": str(path),
                            "line": line,
                            "resource": res_name,
                            "namespace": res_ns,
                        })
                    continue

                # non-snippet map hit
                bucket = _bucket(entry["category"])
                buckets[bucket].append({
                    "row": entry["row"],
                    "annotation": key,
                    "value": value,
                    "category": entry["category"],
                    "target": entry["target"],
                    "file": str(path),
                    "line": line,
                    "resource": res_name,
                    "namespace": res_ns,
                })

    total = sum(len(v) for v in buckets.values())
    result = {
        **buckets,
        "summary": {
            "totalAnnotations": total,
            **{k: len(v) for k, v in buckets.items()},
        },
    }
    print(json.dumps(result, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main())
