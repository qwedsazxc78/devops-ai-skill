#!/usr/bin/env python3
"""render_plan.py — Substitute references/plan-template.md with state.yaml data.

Reads state.yaml (machine-readable plan state) and renders the human-readable
plan.md by replacing every {{placeholder}} with data from state.

Unresolved placeholders are surfaced as a banner at the top of the output —
informational, not a failure (skill continues, but the operator should
investigate any unresolved fields).

Usage:
    python3 render_plan.py --state state.yaml --template plan-template.md --out plan.md
"""
from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
from datetime import date, timedelta
from pathlib import Path


PLACEHOLDER_RE = re.compile(r"\{\{([a-zA-Z][a-zA-Z0-9_]*)\}\}")


def _die(msg: str, code: int = 2) -> None:
    print(f"[render_plan] {msg}", file=sys.stderr)
    sys.exit(code)


def _read_yaml(path: Path) -> dict:
    try:
        result = subprocess.run(
            ["yq", "-o=json", str(path)], check=True, capture_output=True, text=True,
        )
    except FileNotFoundError:
        _die("yq not found on PATH")
    except subprocess.CalledProcessError as e:
        _die(f"yq failed on {path}: {e.stderr.strip()}")
    return json.loads(result.stdout)


def _gantt_section(batches: list[dict], path_filter: str) -> str:
    rows = []
    for b in batches:
        if b.get("path") != path_filter:
            continue
        start = b.get("targetWeek")
        if not start:
            continue
        dur = b.get("estimatedDuration", "1 week")
        days = 7 if "1" in dur else 14
        end = (date.fromisoformat(start) + timedelta(days=days)).isoformat()
        services = ", ".join(b.get("services", []))
        rows.append(f"    Batch {b.get('id')} ({services}) :{start}, {end}")
    return "\n".join(rows) if rows else f"    (no {path_filter} batches)"


def _per_service_rows(scores: list[dict], decisions: list[dict], inventory: list[dict]) -> str:
    inv_by_name = {s["service"]: s for s in inventory}
    scores_by_name = {s["service"]: s for s in scores}
    rows = []
    for d in decisions:
        name = d["service"]
        svc = inv_by_name.get(name, {})
        sc = scores_by_name.get(name, {})
        rows.append(
            f"| {name} | {svc.get('sourceClass', '?')} | {sc.get('tier', '?')} | "
            f"{sc.get('total', '—')} | {d['path']} | {sc.get('rationale', '—')} |"
        )
    return "\n".join(rows) if rows else "| _no services_ | | | | | |"


def _batch_blocks(batches: list[dict]) -> str:
    blocks = []
    for b in batches:
        services = b.get("services", [])
        commands = b.get("commands", [])
        cmd_block = "\n".join(commands) if commands else "(no commands generated)"
        blocks.append(
            f"### Batch `{b.get('id')}` — `{b.get('path')}` (week of {b.get('targetWeek')})\n\n"
            f"**Services**: {', '.join(services)}  \n"
            f"**Estimated duration**: {b.get('estimatedDuration', '1 week')}\n\n"
            f"```bash\n{cmd_block}\n```\n"
        )
    return "\n".join(blocks) if blocks else "_No batches scheduled._"


def _deferred_blocks(deferred: list[dict]) -> str:
    if not deferred:
        return "_No deferred services._"
    rows = [
        f"| {d.get('service')} | {d.get('reason', '—')} | {d.get('advisoryPath', '—')} | "
        f"{d.get('tier', '—')} |"
        for d in deferred
    ]
    return (
        "| Service | Reason | Advisory path | Tier |\n"
        "|---|---|---|---|\n" + "\n".join(rows)
    )


def _warning_list(warnings: list) -> str:
    if not warnings:
        return "_None._"
    items = []
    for w in warnings:
        if isinstance(w, dict):
            items.append(f"- **{w.get('kind', 'warning')}**: {json.dumps({k: v for k, v in w.items() if k != 'kind'})}")
        else:
            items.append(f"- {w}")
    return "\n".join(items)


def _path_counts(decisions: list[dict]) -> dict:
    out = {"direct-gateway": 0, "two-step": 0, "swap-only": 0, "defer": 0}
    for d in decisions:
        out[d["path"]] = out.get(d["path"], 0) + 1
    return out


def _batch_count_by_path(batches: list[dict]) -> dict:
    out = {"direct-gateway": 0, "two-step": 0, "swap-only": 0}
    for b in batches:
        out[b["path"]] = out.get(b["path"], 0) + 1
    return out


def _final_cutover_date(batches: list[dict], bake_days: int) -> tuple[str, int, str]:
    """Return (final-cutover-date, margin-days, overflow-banner)."""
    if not batches:
        return ("—", 0, "")
    latest = max(date.fromisoformat(b["targetWeek"]) for b in batches if b.get("targetWeek"))
    final = latest + timedelta(days=14)  # assume 2-week tail per batch
    return (final.isoformat(), 0, "")


def main() -> int:
    p = argparse.ArgumentParser()
    p.add_argument("--state", type=Path, required=True)
    p.add_argument("--template", type=Path, required=True)
    p.add_argument("--out", type=Path, required=True)
    args = p.parse_args()

    state = _read_yaml(args.state)
    template = args.template.read_text()

    inputs = state.get("inputs", {})
    deadline = inputs.get("deadline", "—")
    bake_days = inputs.get("bakeBufferDays", 30)
    batches = state.get("batches", [])
    decisions = state.get("decisions", [])
    deferred = state.get("deferred", [])
    scores = state.get("scores", [])
    inventory = state.get("inventory", [])
    warnings = state.get("warnings", [])

    path_counts = _path_counts(decisions)
    batch_counts = _batch_count_by_path(batches)
    final_date, margin, overflow = _final_cutover_date(batches, bake_days)

    try:
        margin_days = (date.fromisoformat(deadline) - date.fromisoformat(final_date)).days
    except (ValueError, TypeError):
        margin_days = 0

    overflow_banner = ""
    if margin_days < 0:
        overflow_banner = (
            f"> **WARNING**: Schedule overflows deadline by {abs(margin_days)} day(s). "
            "Shrink scope, extend deadline, or shrink bake buffer."
        )

    substitutions = {
        "deadline": str(deadline),
        "runId": state.get("runId", "—"),
        "createdAt": state.get("createdAt", "—"),
        "skillVersion": state.get("skillVersion", "1.0.0"),
        "schemaVersion": str(state.get("schemaVersion", 1)),
        "overflowBanner": overflow_banner,
        "totalServices": str(len(decisions)),
        "directGatewayCount": str(path_counts.get("direct-gateway", 0)),
        "directGatewayBatches": str(batch_counts.get("direct-gateway", 0)),
        "twoStepCount": str(path_counts.get("two-step", 0)),
        "twoStepBatches": str(batch_counts.get("two-step", 0)),
        "swapOnlyCount": str(path_counts.get("swap-only", 0)),
        "swapOnlyBatches": str(batch_counts.get("swap-only", 0)),
        "deferCount": str(path_counts.get("defer", 0)),
        "bakeBufferDays": str(bake_days),
        "finalCutoverDate": final_date,
        "deadlineMarginDays": str(margin_days),
        "ganttDirectGateway": _gantt_section(batches, "direct-gateway"),
        "ganttTwoStep": _gantt_section(batches, "two-step"),
        "ganttSwapOnly": _gantt_section(batches, "swap-only"),
        "perServiceRows": _per_service_rows(scores, decisions, inventory),
        "batchBlocks": _batch_blocks(batches),
        "deferredBlocks": _deferred_blocks(deferred),
        "riskRows": "| — | — | — | — |",
        "warningList": _warning_list(warnings),
        "operator": state.get("operator", "—"),
        "batchSizeCap": str(inputs.get("batchSizeCap", 5)),
        "targetPathOverride": str(inputs.get("targetPathOverride") or "—"),
        "strictTierMap": str(inputs.get("strictTierMap", False)),
        "tierMapServiceCount": str(len(inputs.get("tierMap", {}))),
        "inventoryMode": state.get("inventoryMode", "built"),
        "statePath": str(args.state),
    }

    unresolved: list[str] = []

    def replace(match):
        key = match.group(1)
        if key in substitutions:
            return substitutions[key]
        unresolved.append(key)
        return match.group(0)

    rendered = PLACEHOLDER_RE.sub(replace, template)

    if unresolved:
        banner = (
            "> **Unresolved placeholders**: " + ", ".join(sorted(set(unresolved)))
            + ". State.yaml is missing these fields — please report as a skill bug.\n\n"
        )
        rendered = banner + rendered

    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(rendered)
    print(f"[render_plan] wrote {args.out}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
