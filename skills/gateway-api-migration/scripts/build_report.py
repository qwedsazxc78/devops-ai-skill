#!/usr/bin/env python3
"""
build_report.py — render references/report-template.md from state.yaml.

Reads the state YAML produced during *gateway-migrate run and emits the final
report.md by substituting `{{variable}}` placeholders in the template.

Usage:
    python3 build_report.py \
        --state   docs/reports/gateway-migration/<slug>/state.yaml \
        --template references/report-template.md \
        --out     docs/reports/gateway-migration/<slug>/report.md

The substitution is intentionally simple (str.replace) — the report template
is not a full templating language. Repeating blocks (rows in a table) are
pre-rendered by this script into single strings and injected as one
placeholder each.

Variables the state.yaml is expected to carry (see SKILL.md §State schema):

    header:         module, moduleSlug, generatedModule, targetGatewayClass,
                    skillVersion, reportGeneratedAt, repoUrl, gitShaShort,
                    gitBranch, kustomizeVersion, yqVersion, kubeconformVersion,
                    ingress2gatewayVersion, kubectlContext, gcpProject,
                    operator, runId
    topology:       masterModule, masterNamespace, masterFileCount,
                    minionModuleList, serviceList, envList, nHttpRoutes,
                    nOrphanHosts, nOrphanMinions, nAmbiguous, pairingRows
    annotations:    translatedRows, translatedLossyRows, stubRows, unknownRows
    generated:      fileTree, fileRows
    modified:       fileRows, fileDiffs
    manualReview:   entries
    perHostname:    rows
    tls:            rows
    risks:          rows
    cutover:        rows
    verification:   httprouteVerifyCommands, perHostnameCurlResolve,
                    perHostnameCertCheck
    secondOpinion:  status, summary, expectedDiv, needsReviewDiv, formattingDiv
    halts:          entries
    observability:  grafanaNginxLink, grafanaGatewayLink, lbLogLink, argocdLink
    consolidation:  entries
    audit:          rows
    steps:          per-step status, started, finished, notes
    verdict:        value, numericSummary, banner

Unused placeholders are left as-is and highlighted at the top of the output
so reviewers can spot them.

Exit codes:
    0 — report written, all critical placeholders substituted
    1 — missing template or state file
    2 — unresolved critical placeholders (the report is still written)
"""
from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
from pathlib import Path

CRITICAL_PLACEHOLDERS = {
    "module",
    "module_slug",
    "generated_module",
    "target_gateway_class",
    "skill_version",
    "verdict",
    "verdict_banner",
    "topology",
    "report_generated_at",
}

PLACEHOLDER_RE = re.compile(r"\{\{([a-zA-Z0-9_]+)\}\}")


def _load_yaml_via_yq(path: Path) -> dict:
    """Load YAML via yq to avoid PyYAML dependency."""
    try:
        raw = subprocess.check_output(
            ["yq", "-o=json", ".", str(path)],
            text=True, stderr=subprocess.PIPE,
        )
    except FileNotFoundError:
        print("[build_report] yq not found on PATH", file=sys.stderr)
        sys.exit(1)
    except subprocess.CalledProcessError as e:
        print(f"[build_report] yq failed on {path}: {e.stderr}", file=sys.stderr)
        sys.exit(1)
    return json.loads(raw or "{}")


def _verdict_banner(verdict: str, numeric_summary: str) -> str:
    marker = {
        "PASS": "> [!SUCCESS]",
        "COMPLETED WITH MANUAL REVIEW REQUIRED": "> [!WARNING]",
        "FAIL": "> [!FAILURE]",
    }.get(verdict, "> [!NOTE]")
    return f"{marker}\n> **Verdict: {verdict}** — {numeric_summary}"


def _render_table_rows(rows: list[dict], columns: list[str]) -> str:
    """Render a list of dicts into markdown table rows (no header)."""
    if not rows:
        return "| _(none)_ |" + " |" * (len(columns) - 1)
    lines = []
    for row in rows:
        cells = [str(row.get(col, "—")) for col in columns]
        lines.append("| " + " | ".join(cells) + " |")
    return "\n".join(lines)


def _render_kv(d: dict) -> dict[str, str]:
    """Flatten a dict into `name → str(value)` — one level only."""
    return {k: str(v) for k, v in d.items()}


def _build_substitutions(state: dict) -> dict[str, str]:
    """Produce the full placeholder map from state.yaml content."""
    header = state.get("header", {}) or {}
    topology = state.get("topology", {}) or {}
    annotations = state.get("annotations", {}) or {}
    generated = state.get("generated", {}) or {}
    modified = state.get("modified", {}) or {}
    manual = state.get("manualReview", []) or []
    per_host = state.get("perHostname", []) or []
    tls = state.get("tls", []) or []
    risks = state.get("risks", []) or []
    cutover = state.get("cutover", []) or []
    verification = state.get("verification", {}) or {}
    second_opinion = state.get("secondOpinion", {}) or {}
    halts = state.get("halts", []) or []
    observability = state.get("observability", {}) or {}
    consolidation = state.get("consolidation", []) or []
    audit = state.get("audit", []) or []
    steps = state.get("steps", {}) or {}
    verdict = state.get("verdict", {}) or {}

    subs: dict[str, str] = {}

    # Header
    subs.update(_render_kv(header))

    # Verdict
    verdict_value = verdict.get("value", "UNKNOWN")
    numeric_summary = verdict.get("numericSummary", "no summary")
    subs["verdict"] = verdict_value
    subs["verdict_numeric_summary"] = numeric_summary
    subs["verdict_banner"] = _verdict_banner(verdict_value, numeric_summary)

    # Topology
    subs.update(_render_kv(topology))
    subs["pairing_rows"] = _render_table_rows(
        topology.get("pairingRows", []),
        ["env", "hostname", "masterListener", "minionFile", "minionService",
         "backendPort", "namespace"],
    )
    subs["orphan_host_rows"] = _render_table_rows(
        topology.get("orphanHostRows", []),
        ["hostname", "inMasterFile", "certKind", "action"],
    )

    # Annotations
    subs["translated_rows"] = _render_table_rows(
        annotations.get("translated", []),
        ["row", "annotation", "category", "target", "sourceFileLine", "count"],
    )
    subs["translated_lossy_rows"] = _render_table_rows(
        annotations.get("translatedLossy", []),
        ["row", "annotation", "category", "target", "sourceFileLine", "caveat"],
    )
    subs["stub_rows"] = _render_table_rows(
        annotations.get("stubbed", []),
        ["row", "annotation", "category", "stubLocation", "sourceFileLine", "pattern"],
    )
    subs["unknown_rows"] = _render_table_rows(
        annotations.get("unknown", []),
        ["annotation", "sourceFileLine", "action", "notes"],
    )

    # Generated
    subs["generated_file_tree"] = generated.get("fileTree", "(empty)")
    subs["generated_file_rows"] = _render_table_rows(
        generated.get("fileRows", []), ["path", "sha256", "size"],
    )

    # Modified
    subs["modified_file_rows"] = _render_table_rows(
        modified.get("fileRows", []), ["path", "change", "preEditBackup"],
    )
    subs["modified_file_diffs"] = modified.get("fileDiffs", "_(no modifications recorded)_")

    # Manual review — richer structure
    if manual:
        entries = []
        for i, mr in enumerate(manual, start=1):
            block = (
                f"### MR-{i} — {mr.get('annotation','?')} "
                f"(row {mr.get('row','?')}, pattern `{mr.get('pattern','?')}`)\n\n"
                f"**Source:** `{mr.get('file','?')}:{mr.get('line','?')}` "
                f"in `{mr.get('module','?')}`\n\n"
                f"**Stub location:** `{mr.get('stubFile','?')}` "
                f"line {mr.get('stubLine','?')}\n"
                f"(`# TODO(gateway-migrate): {mr.get('reason','?')}`)\n\n"
                f"**Why it could not be auto-translated:** {mr.get('why','?')}\n\n"
                f"**Recommended remediation:** {mr.get('remediation','?')}\n\n"
                f"**Reference:** "
                f"`references/manual-review-patterns.md#{mr.get('patternAnchor','')}`\n"
            )
            entries.append(block)
        subs["manual_review_entries"] = "\n---\n".join(entries)
    else:
        subs["manual_review_entries"] = "_(no manual-review items — happy path!)_"

    # Per-hostname
    subs["per_hostname_rows"] = _render_table_rows(
        per_host,
        ["env", "hostname", "oldTlsSource", "newTlsSource", "oldPaths",
         "newHttpRoute", "newBackend", "currentDns", "newGatewayIp", "status"],
    )

    # TLS
    subs["tls_rows"] = _render_table_rows(
        tls,
        ["hostname", "certKind", "certName", "certNamespace", "listener",
         "provisioningWait", "status"],
    )

    # Risks
    subs["risk_rows"] = _render_table_rows(
        risks,
        ["severity", "sourceStep", "description", "fileLine", "mitigation"],
    )

    # Cutover checklist
    subs["cutover_checklist_rows"] = _render_table_rows(
        cutover,
        ["env", "hostname", "tested", "dnsFlipped", "soaked", "errorRateOk", "status"],
    )

    # Verification commands
    subs["httproute_verify_commands"] = verification.get("httprouteVerifyCommands", "# none")
    subs["per_hostname_curl_resolve"] = verification.get("perHostnameCurlResolve", "# none")
    subs["per_hostname_cert_check"] = verification.get("perHostnameCertCheck", "# none")

    # Second-opinion
    subs["second_opinion_summary"] = second_opinion.get("summary", "_(Step 4c was not run)_")
    subs["expected_div"] = str(second_opinion.get("expectedDivergence", 0))
    subs["needs_review_div"] = str(second_opinion.get("needsReviewDivergence", 0))
    subs["formatting_div"] = str(second_opinion.get("formattingDivergence", 0))

    # Halts
    if halts:
        subs["halt_entries"] = "\n\n".join(
            f"- **Step {h.get('step','?')}**: {h.get('error','?')}\n"
            f"  - State: `{h.get('state','?')}`\n"
            f"  - Resume: {h.get('resume','?')}\n"
            f"  - Force: {h.get('force','n/a')}"
            for h in halts
        )
    else:
        subs["halt_entries"] = "_(no halts — run completed end to end)_"

    # Observability
    subs.update(_render_kv(observability))

    # Consolidation
    if consolidation:
        subs["consolidation_entries"] = "\n".join(
            f"- **{c.get('title','?')}** — {c.get('notes','?')}"
            for c in consolidation
        )
    else:
        subs["consolidation_entries"] = "_(none surfaced by this migration)_"

    # Audit
    subs["audit_rows"] = _render_table_rows(
        audit, ["event", "timestamp", "actor", "notes"],
    )

    # Steps — each step maps to 5 placeholders (status/started/finished/notes + itself)
    step_defs = {
        "0": "tool_check",
        "0b": "cluster_preflight",
        "1": "discover",
        "2": "analyze",
        "3A": "generate_gateway",
        "3B": "generate_httproutes",
        "4a": "kustomize_build",
        "4b": "kubeconform",
        "4c": "second_opinion",
        "4d": "semantic_diff",
        "5": "render_report",
        "6": "emit_runbook",
        "7": "precommit_hints",
    }
    for step_id, step_key in step_defs.items():
        step = steps.get(step_id, {}) or {}
        prefix = f"s{step_id.lower()}"
        subs[f"{prefix}_status"]   = step.get("status", "not-run")
        subs[f"{prefix}_started"]  = step.get("started", "—")
        subs[f"{prefix}_finished"] = step.get("finished", "—")
        subs[f"{prefix}_notes"]    = step.get("notes", "")

    return subs


def _substitute(template: str, subs: dict[str, str]) -> tuple[str, set[str]]:
    """Replace every `{{name}}` with `subs[name]`. Return (text, unresolved_set)."""
    unresolved: set[str] = set()

    def repl(match: re.Match) -> str:
        key = match.group(1)
        if key in subs:
            return str(subs[key])
        unresolved.add(key)
        return match.group(0)

    return PLACEHOLDER_RE.sub(repl, template), unresolved


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--state", required=True)
    parser.add_argument("--template", required=True)
    parser.add_argument("--out", required=True)
    args = parser.parse_args()

    state_path = Path(args.state)
    template_path = Path(args.template)
    out_path = Path(args.out)

    if not state_path.is_file():
        print(f"[build_report] state file not found: {state_path}", file=sys.stderr)
        return 1
    if not template_path.is_file():
        print(f"[build_report] template not found: {template_path}", file=sys.stderr)
        return 1

    state = _load_yaml_via_yq(state_path)
    template = template_path.read_text(encoding="utf-8")
    subs = _build_substitutions(state)
    text, unresolved = _substitute(template, subs)

    # Prepend a warning about unresolved critical placeholders
    critical_missing = unresolved & CRITICAL_PLACEHOLDERS
    if critical_missing:
        warning = (
            "> [!WARNING]\n"
            "> The following **critical** placeholders were not substituted "
            "from `state.yaml`:\n"
            f"> `{'`, `'.join(sorted(critical_missing))}`\n\n"
        )
        text = warning + text

    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text(text, encoding="utf-8")
    print(f"[build_report] wrote {out_path}", file=sys.stderr)

    if unresolved:
        print(f"[build_report] {len(unresolved)} unresolved placeholder(s): "
              f"{sorted(unresolved)}", file=sys.stderr)
    if critical_missing:
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())
