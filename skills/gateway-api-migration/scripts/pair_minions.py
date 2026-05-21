#!/usr/bin/env python3
"""
pair_minions.py — pair minions with masters by hostname for *gateway-migrate.

Consumes the JSONL output of `classify_ingress.py` and produces a structured
pairing report to stdout.

Pairing algorithm (from references/master-minion-topology.md):

    1. Build a hostname → master map from the classified masters.
    2. For each minion, take its `hosts[]`.
    3. If a minion has exactly one hostname that matches exactly one master,
       pair them.
    4. Zero matches     → orphan minion (halt-worthy).
    5. Multiple matches → ambiguous (halt-worthy).
    6. For each master hostname with no matching minion → orphan host
       (warn, don't halt).

Hostname matching is case-insensitive exact-match.

Usage:
    python3 classify_ingress.py $(find . -name '*.ingress*.yaml' -o -name '*nginx-ingress*.yaml') \
      | python3 pair_minions.py

Or with explicit file:
    python3 pair_minions.py --input classifications.jsonl

Output JSON structure:

    {
      "topology": "master-minion" | "standalone" | "none",
      "pairs": [
        {
          "hostname": "argocd.example.com",
          "master": {"file": "...", "name": "app-master", "namespace": "ingress-nginx"},
          "minion": {"file": "...", "name": "argocd-minion", "namespace": "argocd",
                     "service": "argocd-server", "port": 80}
        }
      ],
      "orphanHosts":   [{"hostname": "...", "master": {...}}],
      "orphanMinions": [{"hostname": "...", "minion": {...}}],
      "ambiguous":     [{"hostname": "...", "candidates": [...]}],
      "foreign":       [{"file": "...", "reason": "..."}],
      "standalone":    [{"file": "...", "hosts": [...]}],
      "summary": {
        "masters": 1, "minions": 5, "standalone": 0, "foreign": 2,
        "pairs": 5, "orphanHosts": 0, "orphanMinions": 0, "ambiguous": 0
      }
    }

Exit codes:
    0 — all minions paired (or only standalone topology)
    1 — orphan minion or ambiguous pairing (caller should HALT)
    2 — no classifications on input
"""
from __future__ import annotations

import json
import sys
from collections import defaultdict


def _read_input(argv: list[str]) -> list[dict]:
    """Read JSONL from stdin or --input file."""
    if "--input" in argv:
        idx = argv.index("--input")
        path = argv[idx + 1]
        with open(path, encoding="utf-8") as fh:
            return [json.loads(line) for line in fh if line.strip()]
    return [json.loads(line) for line in sys.stdin if line.strip()]


def _first_backend(minion: dict) -> tuple[str | None, int | None]:
    """Best-effort extract of first backend (service, port) from minion annotations.

    The classify_ingress.py output doesn't carry the raw spec, only extracted
    fields. For richer extraction we would re-parse the file here, but for
    this script's purpose (pairing) we only need the hostname. Backend
    details will be re-resolved by inventory_annotations.py when needed.
    """
    return None, None


def main() -> int:
    argv = sys.argv[1:]
    try:
        classifications = _read_input(argv)
    except (OSError, json.JSONDecodeError) as e:
        print(f"[pair_minions] failed to read input: {e}", file=sys.stderr)
        return 2
    if not classifications:
        print("[pair_minions] no classifications on input", file=sys.stderr)
        return 2

    masters = [c for c in classifications if c["classification"] == "master"]
    minions = [c for c in classifications if c["classification"] == "minion"]
    standalone = [c for c in classifications if c["classification"] == "standalone"]
    foreign = [c for c in classifications if c["classification"] == "foreign"]
    unknown = [c for c in classifications if c["classification"] == "unknown"]

    # Determine topology
    if masters and minions:
        topology = "master-minion"
    elif standalone and not masters and not minions:
        topology = "standalone"
    elif not masters and not minions and not standalone:
        topology = "none"
    elif masters and not minions:
        topology = "master-only"  # unusual; will produce orphan hosts
    else:
        topology = "mixed"  # mix of standalone + master/minion — unusual

    # Build host → master candidates (one master may declare many hosts;
    # one host may appear in multiple masters → ambiguous)
    host_to_masters: dict[str, list[dict]] = defaultdict(list)
    for m in masters:
        for host in m.get("hosts", []):
            host_to_masters[host.lower()].append(m)

    pairs = []
    orphan_minions = []
    ambiguous = []

    # Track which master hostnames have been paired
    matched_hostnames = set()

    for minion in minions:
        m_hosts = [h.lower() for h in minion.get("hosts", [])]
        if not m_hosts:
            orphan_minions.append({
                "reason": "no hosts declared on minion",
                "minion": {
                    "file": minion["file"],
                    "name": minion.get("name"),
                    "namespace": minion.get("namespace"),
                },
            })
            continue

        # For each host in the minion, find a matching master
        minion_paired = False
        for host in m_hosts:
            candidates = host_to_masters.get(host, [])
            if len(candidates) == 1:
                pairs.append({
                    "hostname": host,
                    "master": {
                        "file": candidates[0]["file"],
                        "name": candidates[0].get("name"),
                        "namespace": candidates[0].get("namespace"),
                    },
                    "minion": {
                        "file": minion["file"],
                        "name": minion.get("name"),
                        "namespace": minion.get("namespace"),
                    },
                })
                matched_hostnames.add(host)
                minion_paired = True
            elif len(candidates) > 1:
                ambiguous.append({
                    "hostname": host,
                    "candidates": [
                        {"file": c["file"], "name": c.get("name")}
                        for c in candidates
                    ],
                    "minion": {
                        "file": minion["file"],
                        "name": minion.get("name"),
                    },
                })
        if not minion_paired and not any(
            a["minion"]["file"] == minion["file"] for a in ambiguous
        ):
            orphan_minions.append({
                "reason": f"no master declares host(s): {', '.join(m_hosts)}",
                "minion": {
                    "file": minion["file"],
                    "name": minion.get("name"),
                    "namespace": minion.get("namespace"),
                },
            })

    # Orphan hosts: master declared the host but no minion matched it
    orphan_hosts = []
    for host, master_list in host_to_masters.items():
        if host not in matched_hostnames:
            for master in master_list:
                orphan_hosts.append({
                    "hostname": host,
                    "master": {
                        "file": master["file"],
                        "name": master.get("name"),
                    },
                })

    result = {
        "topology": topology,
        "pairs": pairs,
        "orphanHosts": orphan_hosts,
        "orphanMinions": orphan_minions,
        "ambiguous": ambiguous,
        "foreign": [
            {"file": f["file"], "reason": f.get("reason", "")} for f in foreign
        ],
        "standalone": [
            {"file": s["file"], "hosts": s.get("hosts", [])} for s in standalone
        ],
        "unknown": [
            {"file": u["file"], "reason": u.get("reason", "")} for u in unknown
        ],
        "summary": {
            "masters": len(masters),
            "minions": len(minions),
            "standalone": len(standalone),
            "foreign": len(foreign),
            "unknown": len(unknown),
            "pairs": len(pairs),
            "orphanHosts": len(orphan_hosts),
            "orphanMinions": len(orphan_minions),
            "ambiguous": len(ambiguous),
        },
    }

    print(json.dumps(result, ensure_ascii=False, indent=2))

    if orphan_minions or ambiguous:
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
