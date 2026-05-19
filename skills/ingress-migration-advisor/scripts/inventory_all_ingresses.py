#!/usr/bin/env python3
"""inventory_all_ingresses.py — Build every overlay, classify Ingresses, group by service.

Discovers every `*/overlays/*/kustomization.yaml` under common.* directories,
runs `kustomize build` on each, pipes the result through classify_ingress.py
(from the gateway-api-migration skill), then groups results by service name.

Output (JSON, on stdout):
{
  "mode": "built" | "raw-fallback",
  "overlaysScanned": N,
  "ingressesFound": N,
  "inventory": [
    {
      "service": "argocd-server",
      "namespace": "argocd",
      "sourceClass": "nginx" | "traefik" | "foreign",
      "envs": ["dev", "stg", "prd"],
      "modulePathPerEnv": {"dev": "common.service/overlays/dev", ...},
      "hostsPerEnv": {"dev": ["argocd.dev.awoo.org"], ...},
      "annotations": {
        "total": 12,
        "unknownLikely": 1,
        "cors": false,
        "authPresent": false,
        "securityHeadersPresent": false,
        "wafPresent": false
      },
      "tlsMode": "secret" | "managed-cert" | "none" | "mixed",
      "backendResolved": true
    },
    ...
  ]
}

Usage:
    python3 inventory_all_ingresses.py [--repo-root PATH] [--classifier PATH]

Exits 0 on success, 1 if zero Ingresses found, 2 on tooling error.
"""
from __future__ import annotations

import argparse
import json
import re
import shutil
import subprocess
import sys
import tempfile
from collections import defaultdict
from pathlib import Path

KNOWN_ANNOTATION_PREFIXES = (
    "nginx.ingress.kubernetes.io/",
    "kubernetes.io/ingress.",
    "cert-manager.io/",
    "networking.gke.io/",
    "traefik.ingress.kubernetes.io/",
)

CORS_KEYS = ("enable-cors", "cors-allow-origin", "cors-allow-methods", "cors-allow-headers", "cors-allow-credentials", "cors-expose-headers", "cors-max-age")
AUTH_KEYS = ("auth-url", "auth-signin", "auth-realm", "auth-secret", "auth-type", "auth-tls-", "basic-auth", "whitelist-source-range")
SEC_HEADER_HINTS = ("strict-transport-security", "content-security-policy", "x-frame-options", "x-content-type-options")
WAF_KEYS = ("force-ssl-redirect", "ssl-passthrough", "modsecurity")


def _die(msg: str, code: int = 2) -> None:
    print(f"[inventory_all_ingresses] {msg}", file=sys.stderr)
    sys.exit(code)


def _find_overlays(repo_root: Path) -> list[Path]:
    out: list[Path] = []
    for k in repo_root.glob("common.*/**/overlays/*/kustomization.yaml"):
        out.append(k.parent)
    return sorted(set(out))


def _build_overlay(overlay: Path, tmpdir: Path) -> Path | None:
    rel = overlay.relative_to(overlay.parents[2])  # common.X/overlays/<env>
    out = tmpdir / f"{rel.parent.parent.name}-{rel.name}.yaml"
    try:
        result = subprocess.run(
            ["kustomize", "build", str(overlay)],
            check=True, capture_output=True, text=True,
        )
    except FileNotFoundError:
        _die("kustomize not found on PATH")
    except subprocess.CalledProcessError as e:
        print(f"[inventory_all_ingresses] kustomize build failed for {overlay}: {e.stderr.strip()}", file=sys.stderr)
        return None
    out.write_text(result.stdout)
    return out


def _extract_ingresses(built_yaml: Path) -> Path:
    """Filter built YAML to only Ingress docs, write to a sibling file."""
    out = built_yaml.with_suffix(".ingress.yaml")
    try:
        result = subprocess.run(
            ["yq", "ea", "[select(.kind == \"Ingress\")] | .[] | split_doc", str(built_yaml)],
            check=True, capture_output=True, text=True,
        )
    except FileNotFoundError:
        _die("yq not found on PATH")
    except subprocess.CalledProcessError as e:
        _die(f"yq failed on {built_yaml}: {e.stderr.strip()}")
    out.write_text(result.stdout)
    return out


def _classify(ingress_yaml: Path, classifier_script: Path) -> list[dict]:
    if not ingress_yaml.exists() or ingress_yaml.stat().st_size == 0:
        return []
    try:
        result = subprocess.run(
            ["python3", str(classifier_script), str(ingress_yaml), "--quiet"],
            check=False, capture_output=True, text=True,
        )
    except FileNotFoundError:
        _die("python3 not found")
    if result.returncode not in (0, 1):
        _die(f"classify_ingress.py errored on {ingress_yaml}: {result.stderr.strip()}")
    rows: list[dict] = []
    for line in result.stdout.splitlines():
        line = line.strip()
        if not line:
            continue
        try:
            rows.append(json.loads(line))
        except json.JSONDecodeError:
            print(f"[inventory_all_ingresses] non-JSON output from classifier: {line}", file=sys.stderr)
    return rows


def _annotation_summary(annotations: dict) -> dict:
    keys = list(annotations.keys())
    total = len(keys)
    unknown = sum(1 for k in keys if not any(k.startswith(p) for p in KNOWN_ANNOTATION_PREFIXES))
    cors = any(c in k for k in keys for c in CORS_KEYS)
    auth = any(c in k for k in keys for c in AUTH_KEYS)
    sec_headers = any(any(h in (v or "").lower() for h in SEC_HEADER_HINTS) for v in annotations.values())
    waf = any(c in k for k in keys for c in WAF_KEYS)
    return {
        "total": total,
        "unknownLikely": unknown,
        "cors": cors,
        "authPresent": auth,
        "securityHeadersPresent": sec_headers,
        "wafPresent": waf,
    }


def _tls_mode(row: dict, annotations: dict) -> str:
    has_secret = row.get("hasTls")
    has_managed = any("managed-certificates" in k for k in annotations)
    if has_secret and has_managed:
        return "mixed"
    if has_managed:
        return "managed-cert"
    if has_secret:
        return "secret"
    return "none"


def _env_from_overlay(overlay: Path) -> str:
    return overlay.name


def _module_from_overlay(overlay: Path, repo_root: Path) -> str:
    """Return repo-relative path so commands are portable across machines."""
    try:
        return str(overlay.relative_to(repo_root))
    except ValueError:
        return str(overlay)


_INGRESS_FULL_SUFFIX_RE = re.compile(r"-(nginx|traefik)-ingress$")
_INGRESS_CLASS_SUFFIX_RE = re.compile(r"-(nginx|traefik)$")
_ENV_PREFIX_RE = re.compile(r"^(dev|stg|stage|staging|prd|prod|production)-")


def _service_name(row: dict) -> str:
    """Normalize Ingress resource name to a stable service key.

    Two-pass strip: first try the explicit `-<class>-ingress` suffix (always
    safe). If that doesn't match, try the bare `-<class>` suffix BUT only
    when the resulting prefix still contains a hyphen — otherwise we'd turn
    legitimate names like `ingress-nginx` (the controller's own dashboard)
    into `ingress`, a reserved-looking single word.
    """
    name = row.get("name") or "unknown"
    m = _INGRESS_FULL_SUFFIX_RE.search(name)
    if m:
        name = name[: m.start()]
    else:
        m = _INGRESS_CLASS_SUFFIX_RE.search(name)
        if m and "-" in name[: m.start()]:
            name = name[: m.start()]
    name = _ENV_PREFIX_RE.sub("", name)
    return name


def main() -> int:
    p = argparse.ArgumentParser()
    p.add_argument("--repo-root", default=".", type=Path)
    p.add_argument("--classifier", type=Path, default=None,
                   help="Path to classify_ingress.py (default: sibling skill)")
    args = p.parse_args()

    if not shutil.which("kustomize"):
        _die("kustomize not found on PATH")
    if not shutil.which("yq"):
        _die("yq not found on PATH")

    classifier = args.classifier or (Path(__file__).resolve().parent.parent.parent / "gateway-api-migration" / "scripts" / "classify_ingress.py")
    if not classifier.exists():
        _die(f"classify_ingress.py not found at {classifier}")

    repo_root = args.repo_root.resolve()
    overlays = _find_overlays(repo_root)
    if not overlays:
        print(json.dumps({"mode": "built", "overlaysScanned": 0, "ingressesFound": 0, "inventory": []}))
        return 1

    aggregator: dict[str, dict] = defaultdict(lambda: {
        "service": None,
        "namespace": None,
        "sourceClass": None,
        "_sourceClassesSeen": set(),
        "envs": [],
        "modulePathPerEnv": {},
        "hostsPerEnv": {},
        "annotations": None,
        "tlsMode": None,
        "backendResolved": True,
        "_annotations_raw": {},
    })

    tmpdir = Path(tempfile.mkdtemp(prefix="ingress-advisor-"))
    total_ingresses = 0

    for overlay in overlays:
        env = _env_from_overlay(overlay)
        module_path = _module_from_overlay(overlay, repo_root)
        built = _build_overlay(overlay, tmpdir)
        if not built:
            continue
        ing_only = _extract_ingresses(built)
        rows = _classify(ing_only, classifier)
        for row in rows:
            total_ingresses += 1
            svc = _service_name(row)
            if row.get("classification") == "foreign":
                source_class = "foreign"
            else:
                source_class = row.get("sourceClass") or "nginx"
            entry = aggregator[svc]
            entry["service"] = svc
            entry["namespace"] = row.get("namespace") or entry["namespace"]
            entry["_sourceClassesSeen"].add(source_class)
            if env not in entry["envs"]:
                entry["envs"].append(env)
            entry["modulePathPerEnv"][env] = module_path
            entry["hostsPerEnv"].setdefault(env, [])
            for h in row.get("hosts", []):
                if h not in entry["hostsPerEnv"][env]:
                    entry["hostsPerEnv"][env].append(h)
            entry["_annotations_raw"].update(row.get("annotations") or {})
            entry["tlsMode"] = _tls_mode(row, entry["_annotations_raw"])

    # Finalize annotation summary + source class per service
    inventory = []
    for entry in aggregator.values():
        entry["annotations"] = _annotation_summary(entry["_annotations_raw"])
        seen = entry.pop("_sourceClassesSeen", set())
        # Priority: foreign > nginx > traefik. If any env still has nginx, treat as
        # nginx-source (needs full migration). Only when ALL envs are traefik-only
        # do we treat the service as traefik-source (skip the swap phase).
        if "foreign" in seen:
            entry["sourceClass"] = "foreign"
        elif "nginx" in seen:
            entry["sourceClass"] = "nginx"
        elif "traefik" in seen:
            entry["sourceClass"] = "traefik"
        else:
            entry["sourceClass"] = "nginx"  # safe default
        entry.pop("_annotations_raw", None)
        entry["envs"].sort(key=lambda e: {"dev": 0, "stg": 1, "stage": 1, "staging": 1, "prd": 2, "prod": 2, "production": 2}.get(e, 99))
        inventory.append(entry)

    inventory.sort(key=lambda x: x["service"])

    print(json.dumps({
        "mode": "built",
        "overlaysScanned": len(overlays),
        "ingressesFound": total_ingresses,
        "inventory": inventory,
    }, indent=2))

    return 0 if total_ingresses else 1


if __name__ == "__main__":
    sys.exit(main())
