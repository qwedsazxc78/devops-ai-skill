#!/usr/bin/env python3
"""score_services.py — Apply scoring rubric + decision matrix.

Two modes:
  default: read inventory.json + tier-map.yaml → emit scores
  --decide: read scores.json + inventory.json → emit decisions

Scoring rubric is read from references/scoring-model.md.
Decision matrix is read from references/decision-matrix.md.

Usage:
    # Score
    python3 score_services.py --inventory inv.json --tier-map docs/ingress-tier-map.yaml > scores.json

    # Decide
    python3 score_services.py --decide --scores scores.json --inventory inv.json [--target-path two-step] > decisions.json
"""
from __future__ import annotations

import argparse
import json
import shutil
import subprocess
import sys
from pathlib import Path


# Decision bands (mirrors decision-matrix.md §2). Editable here without code
# change is overkill for an MVP — the markdown is canonical for humans, this
# is the runtime mirror.
SCORE_BANDS = [
    (4, 7, "direct-gateway"),
    (8, 10, "two-step"),
    (11, 13, "swap-only"),
    (14, 14, "defer"),
]

SUGGESTED_COMMAND = {
    ("nginx", "direct-gateway"): "*gateway-migrate {module} --source-class nginx --gateway-class traefik",
    ("nginx", "two-step"): "*nginx-to-gateway {env} --gateway-class traefik",
    ("nginx", "swap-only"): "*nginx-to-traefik {env} {service}",
    ("traefik", "direct-gateway"): "*gateway-migrate {module} --source-class traefik --gateway-class traefik --no-redirect",
}


def _die(msg: str, code: int = 2) -> None:
    print(f"[score_services] {msg}", file=sys.stderr)
    sys.exit(code)


def _read_tier_map(path: Path) -> dict[str, str]:
    if not path.exists():
        _die(f"tier map not found: {path}", code=3)
    try:
        result = subprocess.run(
            ["yq", "-o=json", str(path)], check=True, capture_output=True, text=True,
        )
    except FileNotFoundError:
        _die("yq not found on PATH")
    except subprocess.CalledProcessError as e:
        _die(f"yq failed on {path}: {e.stderr.strip()}")
    try:
        data = json.loads(result.stdout)
    except json.JSONDecodeError as e:
        _die(f"non-JSON output from yq for {path}: {e}")
    services = (data or {}).get("services") or {}
    for svc, tier in services.items():
        if tier not in ("critical", "standard", "low"):
            _die(f"invalid tier '{tier}' for service '{svc}' (valid: critical|standard|low)", code=3)
    return services


def _score_annotations(entry: dict) -> int:
    total = entry["annotations"]["total"]
    unknown = entry["annotations"]["unknownLikely"]
    if total <= 5 and unknown == 0:
        return 1
    if total > 15 or unknown > 2:
        return 3
    return 2


def _score_tls(entry: dict) -> int:
    mode = entry.get("tlsMode") or "none"
    return {"secret": 1, "managed-cert": 2, "mixed": 3, "none": 3}.get(mode, 3)


def _score_hostnames(entry: dict) -> int:
    max_hosts = max((len(v) for v in entry["hostsPerEnv"].values()), default=0)
    if max_hosts <= 1:
        return 1
    if max_hosts <= 3:
        return 2
    return 3


def _score_traffic_tier(tier: str) -> int:
    return {"low": 1, "standard": 2}.get(tier, 2)


def _score_security(entry: dict) -> int:
    a = entry["annotations"]
    cats = sum(1 for k in ("cors", "authPresent", "securityHeadersPresent", "wafPresent") if a.get(k))
    if cats == 0:
        return 1
    if cats == 1:
        return 2
    return 3


def _build_rationale(svc: dict, dim: dict, tier: str) -> str:
    a = svc["annotations"]
    sec_cats = []
    if a.get("cors"): sec_cats.append("CORS")
    if a.get("authPresent"): sec_cats.append("auth")
    if a.get("securityHeadersPresent"): sec_cats.append("sec-headers")
    if a.get("wafPresent"): sec_cats.append("waf")
    sec_str = ", ".join(sec_cats) if sec_cats else "none"
    max_hosts = max((len(v) for v in svc["hostsPerEnv"].values()), default=0)
    return (
        f"{a['total']} annotations, {a['unknownLikely']} unknown; "
        f"{svc.get('tlsMode') or 'none'}; "
        f"{max_hosts} host(s) max; "
        f"{tier} tier; "
        f"{sec_str} security"
    )


def _score_one(svc: dict, tier_map: dict) -> dict:
    name = svc["service"]
    tier = tier_map.get(name, "standard")
    if tier == "critical":
        return {
            "service": name,
            "vetoed": True,
            "vetoReason": "critical-tier",
            "tier": tier,
            "dimensions": {},
            "total": None,
            "rationale": f"critical-tier veto (advisory: see decision step)",
        }
    if svc.get("sourceClass") == "foreign":
        return {
            "service": name,
            "vetoed": True,
            "vetoReason": "foreign-class",
            "tier": tier,
            "dimensions": {},
            "total": None,
            "rationale": f"non-nginx, non-traefik class — out of scope",
        }
    dims = {
        "annotationComplexity": _score_annotations(svc),
        "tlsMode": _score_tls(svc),
        "hostnameCount": _score_hostnames(svc),
        "trafficTier": _score_traffic_tier(tier),
        "securityAnnotations": _score_security(svc),
    }
    return {
        "service": name,
        "vetoed": False,
        "vetoReason": None,
        "tier": tier,
        "dimensions": dims,
        "total": sum(dims.values()),
        "rationale": _build_rationale(svc, dims, tier),
    }


def _band_for_score(total: int) -> str:
    for lo, hi, path in SCORE_BANDS:
        if lo <= total <= hi:
            return path
    return "defer"


def _decide_one(score: dict, svc: dict, target_override: str | None) -> dict:
    name = score["service"]
    if score["vetoed"]:
        advisory = _band_for_score(score["total"]) if score["total"] else "defer"
        return {
            "service": name,
            "path": "defer",
            "advisoryPath": advisory,
            "vetoReason": score["vetoReason"],
            "overrideReason": None,
            "suggestedCommand": None,
        }
    source_class = svc.get("sourceClass", "nginx")
    if source_class == "traefik":
        path = "direct-gateway"
    else:
        path = _band_for_score(score["total"])
    advisory = path
    override = None
    if target_override and path != "defer":
        override = f"--target-path {target_override}"
        path = target_override
    cmd_template = SUGGESTED_COMMAND.get((source_class, path))
    suggested = None
    if cmd_template:
        envs = svc.get("envs", [])
        first_env = envs[0] if envs else "dev"
        module = svc.get("modulePathPerEnv", {}).get(first_env, "common.service/overlays/" + first_env)
        suggested = cmd_template.format(
            module=module, env=first_env, service=name,
        )
    return {
        "service": name,
        "path": path,
        "advisoryPath": advisory,
        "vetoReason": None,
        "overrideReason": override,
        "suggestedCommand": suggested,
    }


def cmd_score(args) -> int:
    with open(args.inventory) as f:
        inv = json.load(f)
    tier_map = _read_tier_map(args.tier_map)
    # Validate strict-tier-map: every entry in map must be in inventory
    inventory_names = {s["service"] for s in inv["inventory"]}
    orphan_entries = [s for s in tier_map.keys() if s not in inventory_names]
    if args.strict_tier_map and orphan_entries:
        _die(f"--strict-tier-map: tier map references services not in inventory: {orphan_entries}", code=3)
    warnings = []
    if orphan_entries:
        warnings.append({"kind": "orphan-tier-entries", "services": orphan_entries})
    missing = [s["service"] for s in inv["inventory"] if s["service"] not in tier_map]
    if missing:
        warnings.append({"kind": "missing-tier-entries", "services": missing, "defaultedTo": "standard"})
    scores = [_score_one(svc, tier_map) for svc in inv["inventory"]]
    print(json.dumps({"scores": scores, "warnings": warnings, "tierMap": tier_map}, indent=2))
    return 0


def cmd_decide(args) -> int:
    with open(args.scores) as f:
        score_data = json.load(f)
    with open(args.inventory) as f:
        inv = json.load(f)
    inv_by_name = {s["service"]: s for s in inv["inventory"]}
    decisions = [
        _decide_one(sc, inv_by_name.get(sc["service"], {}), args.target_path)
        for sc in score_data["scores"]
    ]
    print(json.dumps({"decisions": decisions}, indent=2))
    return 0


def main() -> int:
    p = argparse.ArgumentParser()
    p.add_argument("--decide", action="store_true", help="Run in decision-matrix mode")
    p.add_argument("--inventory", type=Path, required=True)
    p.add_argument("--tier-map", type=Path)
    p.add_argument("--scores", type=Path)
    p.add_argument("--target-path", choices=["direct-gateway", "two-step", "swap-only"])
    p.add_argument("--strict-tier-map", action="store_true")
    args = p.parse_args()

    if args.decide:
        if not args.scores:
            _die("--decide requires --scores")
        return cmd_decide(args)
    if not args.tier_map:
        _die("scoring mode requires --tier-map")
    return cmd_score(args)


if __name__ == "__main__":
    sys.exit(main())
