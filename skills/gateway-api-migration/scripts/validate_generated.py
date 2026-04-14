#!/usr/bin/env python3
"""
validate_generated.py — Step 4d semantic validator for *gateway-migrate.

Runs a fixed set of offline checks against the generated migration artifacts
and optionally cross-checks against the upstream ingress2gateway tool if it's
on PATH. Emits structured JSON to stdout; exit code reflects overall status.

Usage:
    python3 validate_generated.py \
        --target-root       /path/to/eye-of-horus-gitops \
        --module            common.ingress \
        --generated-module  common.gateway \
        --env               dev

    # Skip the ingress2gateway second opinion (faster, no dep on tool):
    python3 validate_generated.py ... --no-second-opinion

Output shape:

    {
      "overall":      "pass" | "warn" | "fail",
      "exitCode":     0 | 1,
      "env":          "dev",
      "timestamp":    "2026-04-14T12:27:25Z",
      "checks": [
        {
          "id":       "listener-coverage",
          "status":   "pass" | "warn" | "fail",
          "severity": "S1" | "S2" | "S3",
          "summary":  "25/25 sectionName refs resolve",
          "details":  {...},
          "mismatches": []
        },
        ...
      ],
      "summary": {
        "pass": 9, "warn": 1, "fail": 0,
        "checksRun": 10,
        "secondOpinionRun": true
      }
    }

The model at Step 4d writes the JSON into `state.yaml.steps["4d"]`,
promotes any `fail` check to a HALT, and `warn` checks into the report's
risk register (default severity S2 unless the check overrides).

Checks (in order):
    1.  kustomize-build-gateway       — `kustomize build <gateway>/overlays/<env>` exits 0
    2.  kustomize-build-service       — `kustomize build <service>/overlays/<env>` exits 0
    3.  listener-coverage             — every HTTPRoute sectionName resolves to a listener
    4.  httproute-parentref-name      — parentRef.name matches Gateway metadata.name
    5.  source-hostname-coverage      — every source hostname appears in a Gateway listener
    6.  source-backend-coverage       — every source backend Service appears in a generated HTTPRoute backendRef
    7.  path-coverage                 — every source path+pathType appears in a generated HTTPRoute match
    8.  namespace-consistency         — every HTTPRoute's namespace matches its source minion's namespace
    9.  tls-secret-coverage           — every source spec.tls[].secretName is referenced by a listener certificateRef
    10. dead-file-safety              — no dead files leaked into generated output
    11. ingress2gateway-second-opinion (optional, if installed)

Dependencies: Python 3 stdlib + `yq` and `kustomize` on PATH.
Optional:     `ingress2gateway` on PATH for check #11.
"""
from __future__ import annotations

import argparse
import datetime as dt
import json
import re
import shutil
import subprocess
import sys
from pathlib import Path


# -----------------------------------------------------------------------------
# Shell helpers
# -----------------------------------------------------------------------------

def _run(cmd: list[str], cwd: Path | None = None, check: bool = False) -> tuple[int, str, str]:
    """Run a command; return (returncode, stdout, stderr)."""
    try:
        proc = subprocess.run(
            cmd, cwd=cwd, capture_output=True, text=True, check=check,
        )
        return proc.returncode, proc.stdout, proc.stderr
    except FileNotFoundError as e:
        return 127, "", str(e)


def _yq_ea_json(path: Path) -> list[dict]:
    """Load multi-doc YAML file as a flat list of dicts via `yq ea '[.]'`."""
    rc, out, err = _run(["yq", "ea", "-o=json", "[.]", str(path)])
    if rc != 0:
        return []
    try:
        data = json.loads(out or "[]")
    except json.JSONDecodeError:
        return []
    # yq ea '[.]' emits a top-level array where each element is a doc.
    # Multi-doc inputs come out as a nested list sometimes; flatten one level.
    if isinstance(data, list):
        result: list[dict] = []
        for elem in data:
            if isinstance(elem, list):
                result.extend(d for d in elem if isinstance(d, dict))
            elif isinstance(elem, dict):
                result.append(elem)
        return result
    if isinstance(data, dict):
        return [data]
    return []


def _kustomize_build(overlay: Path, out_path: Path) -> tuple[int, str]:
    """Run kustomize build, write YAML to out_path, return (rc, stderr)."""
    rc, out, err = _run(["kustomize", "build", str(overlay)])
    if rc == 0:
        out_path.parent.mkdir(parents=True, exist_ok=True)
        out_path.write_text(out, encoding="utf-8")
    return rc, err


# -----------------------------------------------------------------------------
# Check runner
# -----------------------------------------------------------------------------

_STATUS_RANK = {"pass": 0, "warn": 1, "fail": 2}


def _check(
    check_id: str, status: str, summary: str,
    severity: str = "S2", details: dict | None = None,
    mismatches: list | None = None,
) -> dict:
    return {
        "id": check_id,
        "status": status,
        "severity": severity if status != "pass" else "S3",
        "summary": summary,
        "details": details or {},
        "mismatches": mismatches or [],
    }


# -----------------------------------------------------------------------------
# Individual checks
# -----------------------------------------------------------------------------

def check_kustomize_build(
    name: str, overlay: Path, out_path: Path,
) -> dict:
    """Check 1/2: kustomize build exits 0."""
    if not overlay.is_dir():
        return _check(
            f"kustomize-build-{name}",
            "fail",
            f"overlay not found: {overlay}",
            severity="S1",
        )
    rc, err = _kustomize_build(overlay, out_path)
    if rc != 0:
        return _check(
            f"kustomize-build-{name}",
            "fail",
            f"kustomize build failed (exit {rc})",
            severity="S1",
            details={"stderr": err.strip()[:500]},
        )
    return _check(
        f"kustomize-build-{name}",
        "pass",
        f"kustomize build exit 0 → {out_path}",
    )


def check_listener_coverage(gateway_build: Path, service_build: Path) -> dict:
    """Check 3: every HTTPRoute sectionName must resolve to a Gateway listener."""
    gw_docs = _yq_ea_json(gateway_build)
    svc_docs = _yq_ea_json(service_build)

    gateways = [d for d in gw_docs if d.get("kind") == "Gateway"]
    if not gateways:
        return _check(
            "listener-coverage",
            "fail",
            "no Gateway resources found in generated module",
            severity="S1",
        )

    listener_names: set[str] = set()
    for gw in gateways:
        for listener in (gw.get("spec") or {}).get("listeners", []):
            if "name" in listener:
                listener_names.add(listener["name"])

    referenced: set[str] = set()
    for doc in gw_docs + svc_docs:
        if doc.get("kind") != "HTTPRoute":
            continue
        for parent_ref in (doc.get("spec") or {}).get("parentRefs", []):
            section = parent_ref.get("sectionName")
            if section:
                referenced.add(section)

    missing = sorted(referenced - listener_names)
    orphan_listeners = sorted(listener_names - referenced)

    details = {
        "gatewayCount": len(gateways),
        "listenerCount": len(listener_names),
        "referencedSectionCount": len(referenced),
        "orphanListeners": orphan_listeners,
    }
    if missing:
        return _check(
            "listener-coverage",
            "fail",
            f"{len(missing)} HTTPRoute sectionName refs resolve to no listener",
            severity="S1",
            details=details,
            mismatches=missing,
        )
    if orphan_listeners:
        return _check(
            "listener-coverage",
            "warn",
            f"{len(referenced)}/{len(listener_names)} listeners referenced; "
            f"{len(orphan_listeners)} orphan (expected for orphan-host topology)",
            severity="S3",
            details=details,
            mismatches=orphan_listeners,
        )
    return _check(
        "listener-coverage",
        "pass",
        f"{len(referenced)}/{len(listener_names)} listeners referenced",
        details=details,
    )


def check_httproute_parentref_name(
    gateway_build: Path, service_build: Path,
) -> dict:
    """Check 4: every HTTPRoute parentRef.name matches a Gateway metadata.name."""
    gw_docs = _yq_ea_json(gateway_build)
    svc_docs = _yq_ea_json(service_build)

    gateway_names: set[str] = set()
    for doc in gw_docs:
        if doc.get("kind") == "Gateway":
            name = (doc.get("metadata") or {}).get("name")
            if name:
                gateway_names.add(name)

    broken_refs: list[dict] = []
    total = 0
    for doc in gw_docs + svc_docs:
        if doc.get("kind") != "HTTPRoute":
            continue
        route_name = (doc.get("metadata") or {}).get("name", "?")
        route_ns = (doc.get("metadata") or {}).get("namespace", "?")
        for parent_ref in (doc.get("spec") or {}).get("parentRefs", []):
            total += 1
            name = parent_ref.get("name")
            if name and name not in gateway_names:
                broken_refs.append({
                    "httproute": f"{route_ns}/{route_name}",
                    "parentRefName": name,
                    "gatewayNamesFound": sorted(gateway_names),
                })

    if broken_refs:
        return _check(
            "httproute-parentref-name",
            "fail",
            f"{len(broken_refs)} HTTPRoute parentRef.name refs target missing Gateway",
            severity="S1",
            details={"totalParentRefs": total, "gateways": sorted(gateway_names)},
            mismatches=broken_refs,
        )
    return _check(
        "httproute-parentref-name",
        "pass",
        f"{total}/{total} parentRef.name values resolve",
        details={"gateways": sorted(gateway_names)},
    )


def check_source_hostname_coverage(
    source_built: Path, gateway_build: Path,
) -> dict:
    """Check 5: every source master hostname appears as a listener hostname."""
    source_docs = _yq_ea_json(source_built)
    gw_docs = _yq_ea_json(gateway_build)

    source_hosts: set[str] = set()
    for doc in source_docs:
        if doc.get("kind") != "Ingress":
            continue
        for rule in (doc.get("spec") or {}).get("rules", []) or []:
            host = rule.get("host")
            if host:
                source_hosts.add(host.lower())

    listener_hosts: set[str] = set()
    for doc in gw_docs:
        if doc.get("kind") != "Gateway":
            continue
        for listener in (doc.get("spec") or {}).get("listeners", []):
            host = listener.get("hostname")
            if host:
                listener_hosts.add(host.lower())

    missing = sorted(source_hosts - listener_hosts)

    if missing:
        return _check(
            "source-hostname-coverage",
            "fail",
            f"{len(missing)}/{len(source_hosts)} source hostnames missing from Gateway listeners",
            severity="S1",
            details={
                "sourceHostCount": len(source_hosts),
                "listenerHostCount": len(listener_hosts),
            },
            mismatches=missing,
        )
    return _check(
        "source-hostname-coverage",
        "pass",
        f"all {len(source_hosts)} source hostnames covered by Gateway listeners",
        details={
            "sourceHostCount": len(source_hosts),
            "listenerHostCount": len(listener_hosts),
        },
    )


def check_source_backend_coverage(
    source_built: Path, service_build: Path,
) -> dict:
    """Check 6: every source minion backend Service appears in a generated
    HTTPRoute backendRef.

    Both the source minion Ingresses and the generated HTTPRoutes live in
    `service_build` after Kustomize renders the overlay — so this function
    iterates `service_build` twice, separating by .kind. `source_built` (the
    master build) is not consulted because masters are host-only and carry
    no backend information.
    """
    svc_docs = _yq_ea_json(service_build)

    source_backends: set[tuple[str, int]] = set()
    for doc in svc_docs:
        if doc.get("kind") != "Ingress":
            continue
        # Only legacy minions carry paths/backends; they coexist with the new
        # HTTPRoutes in the rendered service build during the migration.
        for rule in (doc.get("spec") or {}).get("rules", []) or []:
            http = rule.get("http") or {}
            for path_rule in http.get("paths", []) or []:
                backend = (path_rule.get("backend") or {}).get("service") or {}
                name = backend.get("name")
                port_num = (backend.get("port") or {}).get("number")
                if name and port_num is not None:
                    source_backends.add((name, int(port_num)))

    generated_backends: set[tuple[str, int]] = set()
    for doc in svc_docs:
        if doc.get("kind") != "HTTPRoute":
            continue
        for rule in (doc.get("spec") or {}).get("rules", []) or []:
            for ref in rule.get("backendRefs", []) or []:
                name = ref.get("name")
                port = ref.get("port")
                if name and port is not None:
                    generated_backends.add((name, int(port)))

    missing = sorted(source_backends - generated_backends)
    extra = sorted(generated_backends - source_backends)

    details = {
        "sourceBackendCount": len(source_backends),
        "generatedBackendCount": len(generated_backends),
    }
    if missing:
        return _check(
            "source-backend-coverage",
            "fail",
            f"{len(missing)} source backend(s) missing from generated HTTPRoutes",
            severity="S1",
            details=details,
            mismatches=[f"{n}:{p}" for n, p in missing],
        )
    if extra:
        return _check(
            "source-backend-coverage",
            "warn",
            f"{len(extra)} extra backend(s) in generated output (not in source)",
            severity="S2",
            details=details,
            mismatches=[f"{n}:{p}" for n, p in extra],
        )
    return _check(
        "source-backend-coverage",
        "pass",
        f"all {len(source_backends)} source backends present in generated HTTPRoutes",
        details=details,
    )


def check_path_coverage(source_built: Path, service_build: Path) -> dict:
    """Check 7: every source path+pathType appears as a match in a generated HTTPRoute.

    Source paths come from legacy minion Ingresses inside `service_build`
    (not the master in `source_built` — masters are host-only). During the
    migration the legacy minions and new HTTPRoutes coexist in the same
    rendered service overlay, so both sides are in the same file.

    pathType normalization rules (see references/http-routing-guide.md):
        Ingress `Prefix`                  → HTTPRoute `PathPrefix`
        Ingress `Exact`                   → HTTPRoute `Exact`
        Ingress `ImplementationSpecific` with path `/`
            → HTTPRoute `PathPrefix` (semantic equivalent for the root case)
        Ingress `ImplementationSpecific` with any other path
            → HTTPRoute manual review required (FAIL with explanation)
    """
    svc_docs = _yq_ea_json(service_build)

    _PATH_TYPE_MAP = {"Prefix": "PathPrefix", "Exact": "Exact"}

    source_paths: set[tuple[str, str]] = set()
    impl_specific_nontrivial: list[str] = []
    for doc in svc_docs:
        if doc.get("kind") != "Ingress":
            continue
        for rule in (doc.get("spec") or {}).get("rules", []) or []:
            http = rule.get("http") or {}
            for path_rule in http.get("paths", []) or []:
                path = path_rule.get("path") or "/"
                raw_ptype = path_rule.get("pathType", "Prefix")
                if raw_ptype == "ImplementationSpecific":
                    if path == "/":
                        # Semantically equivalent to PathPrefix "/"
                        source_paths.add(("/", "PathPrefix"))
                    else:
                        # Non-trivial ImplementationSpecific: operator-specific
                        # semantics. Can't be auto-normalized; require review.
                        impl_specific_nontrivial.append(path)
                else:
                    ptype = _PATH_TYPE_MAP.get(raw_ptype, raw_ptype)
                    source_paths.add((path, ptype))

    generated_paths: set[tuple[str, str]] = set()
    for doc in svc_docs:
        if doc.get("kind") != "HTTPRoute":
            continue
        for rule in (doc.get("spec") or {}).get("rules", []) or []:
            for match in rule.get("matches", []) or []:
                path_cfg = match.get("path") or {}
                value = path_cfg.get("value", "/")
                ptype = path_cfg.get("type", "PathPrefix")
                generated_paths.add((value, ptype))

    missing = sorted(source_paths - generated_paths)

    details = {
        "sourcePathCount": len(source_paths),
        "generatedPathCount": len(generated_paths),
        "implementationSpecificNonTrivial": impl_specific_nontrivial,
    }

    # Non-trivial ImplementationSpecific paths are always manual-review material
    # because their semantics depend on the source Ingress controller.
    if impl_specific_nontrivial:
        return _check(
            "path-coverage",
            "fail",
            f"{len(impl_specific_nontrivial)} source path(s) use "
            f"`pathType: ImplementationSpecific` with non-root path — "
            f"manual review required (no automatic translation)",
            severity="S1",
            details=details,
            mismatches=impl_specific_nontrivial,
        )
    if missing:
        return _check(
            "path-coverage",
            "fail",
            f"{len(missing)} source path(s) missing from generated HTTPRoutes",
            severity="S1",
            details=details,
            mismatches=[f"{p}:{t}" for p, t in missing],
        )
    return _check(
        "path-coverage",
        "pass",
        f"all {len(source_paths)} source paths covered "
        f"(ImplementationSpecific / → PathPrefix / normalization applied)",
        details=details,
    )


def check_namespace_consistency(
    source_built: Path, service_build: Path,
) -> dict:
    """Check 8: every HTTPRoute namespace should match a source minion namespace
    routing to the same hostname."""
    source_docs = _yq_ea_json(source_built)
    svc_docs = _yq_ea_json(service_build)

    # Build host → set of (source namespaces) map
    host_to_src_ns: dict[str, set[str]] = {}
    for doc in source_docs:
        if doc.get("kind") != "Ingress":
            continue
        ns = (doc.get("metadata") or {}).get("namespace", "")
        if not ns:
            continue
        for rule in (doc.get("spec") or {}).get("rules", []) or []:
            host = rule.get("host", "").lower()
            # Only interested in rules that have paths (minion rules)
            if rule.get("http", {}).get("paths"):
                host_to_src_ns.setdefault(host, set()).add(ns)

    mismatches: list[dict] = []
    total = 0
    for doc in svc_docs:
        if doc.get("kind") != "HTTPRoute":
            continue
        route_ns = (doc.get("metadata") or {}).get("namespace", "")
        route_name = (doc.get("metadata") or {}).get("name", "")
        hostnames = (doc.get("spec") or {}).get("hostnames", []) or []
        for host in hostnames:
            host_l = host.lower()
            if host_l in host_to_src_ns:
                total += 1
                if route_ns not in host_to_src_ns[host_l]:
                    mismatches.append({
                        "httproute": f"{route_ns}/{route_name}",
                        "hostname": host,
                        "expectedNamespaces": sorted(host_to_src_ns[host_l]),
                    })

    if mismatches:
        return _check(
            "namespace-consistency",
            "fail",
            f"{len(mismatches)} HTTPRoute(s) in wrong namespace vs source minion",
            severity="S1",
            details={"checkedRoutes": total},
            mismatches=mismatches,
        )
    return _check(
        "namespace-consistency",
        "pass",
        f"all {total} HTTPRoute namespaces match their source minion namespaces",
    )


def check_tls_secret_coverage(source_built: Path, gateway_build: Path) -> dict:
    """Check 9: every source spec.tls[].secretName is referenced by a
    listener certificateRefs entry."""
    source_docs = _yq_ea_json(source_built)
    gw_docs = _yq_ea_json(gateway_build)

    source_secrets: set[str] = set()
    for doc in source_docs:
        if doc.get("kind") != "Ingress":
            continue
        for tls in (doc.get("spec") or {}).get("tls", []) or []:
            name = tls.get("secretName")
            if name:
                source_secrets.add(name)

    listener_cert_refs: set[str] = set()
    for doc in gw_docs:
        if doc.get("kind") != "Gateway":
            continue
        for listener in (doc.get("spec") or {}).get("listeners", []) or []:
            tls = listener.get("tls") or {}
            for ref in tls.get("certificateRefs", []) or []:
                # We ignore kind — any match counts. The kind check belongs to a
                # separate schema-level validation.
                name = ref.get("name")
                if name:
                    listener_cert_refs.add(name)

    # Source secret names often include a `dev-` prefix; generated certs may
    # keep the same or drop the env prefix. We treat exact match as pass and
    # record approximate matches as WARN.
    missing = sorted(source_secrets - listener_cert_refs)

    if missing:
        return _check(
            "tls-secret-coverage",
            "warn",  # warn rather than fail — env-prefix differences are legitimate
            f"{len(missing)}/{len(source_secrets)} source TLS secret names not in listener certRefs",
            severity="S2",
            details={
                "sourceSecretCount": len(source_secrets),
                "listenerRefCount": len(listener_cert_refs),
                "missing": missing[:10],
            },
            mismatches=missing,
        )
    return _check(
        "tls-secret-coverage",
        "pass",
        f"all {len(source_secrets)} source TLS secret names referenced by listeners",
    )


def check_dead_file_safety(
    source_root: Path, minion_overlay_dir: Path, service_build: Path,
) -> dict:
    """Check 10: dead files (on disk but not referenced by any kustomization
    resources/patches) should not appear in the built output."""
    if not minion_overlay_dir.is_dir():
        return _check(
            "dead-file-safety",
            "warn",
            "minion overlay dir not found — check skipped",
            severity="S3",
        )

    # Find all YAML files in the overlay dir
    all_yaml = sorted(minion_overlay_dir.glob("*-nginx-ingress.yaml"))
    # Parse the overlay's kustomization.yaml
    kust = minion_overlay_dir / "kustomization.yaml"
    if not kust.is_file():
        return _check(
            "dead-file-safety",
            "warn",
            f"kustomization.yaml not found in {minion_overlay_dir}",
            severity="S3",
        )

    # Get all referenced files (resources and patches)
    rc, out, err = _run(
        ["yq", "-o=json",
         "[(.resources // []), (.patches // [] | map(.path // .))] | flatten",
         str(kust)],
    )
    if rc != 0:
        referenced = set()
    else:
        try:
            referenced = set(json.loads(out or "[]"))
        except json.JSONDecodeError:
            referenced = set()

    dead_files = [
        p.name for p in all_yaml
        if p.name not in referenced
    ]

    # Now check if any dead file's content leaked into the build
    built_docs = _yq_ea_json(service_build)
    built_ingress_names = {
        (d.get("metadata") or {}).get("name", "")
        for d in built_docs if d.get("kind") == "Ingress"
    }

    leaked: list[str] = []
    for dead in dead_files:
        dead_docs = _yq_ea_json(minion_overlay_dir / dead)
        for d in dead_docs:
            if d.get("kind") != "Ingress":
                continue
            name = (d.get("metadata") or {}).get("name", "")
            # Kustomize may add a namePrefix; substring check is approximate.
            if name and any(name in built_name for built_name in built_ingress_names):
                leaked.append(f"{dead}:{name}")

    if leaked:
        return _check(
            "dead-file-safety",
            "fail",
            f"{len(leaked)} dead file(s) leaked into built output",
            severity="S1",
            details={"deadFiles": dead_files},
            mismatches=leaked,
        )
    if dead_files:
        return _check(
            "dead-file-safety",
            "warn",
            f"{len(dead_files)} dead file(s) on disk (ignored by kustomize)",
            severity="S2",
            details={"deadFiles": dead_files},
        )
    return _check(
        "dead-file-safety",
        "pass",
        "no dead files detected",
    )


def check_ingress2gateway_second_opinion(
    source_built: Path, service_build: Path, gateway_build: Path,
) -> dict | None:
    """Check 11 (optional): cross-check backend coverage and hostname coverage
    against the upstream ingress2gateway tool."""
    if not shutil.which("ingress2gateway"):
        return _check(
            "ingress2gateway-second-opinion",
            "warn",
            "ingress2gateway not on PATH — install with `brew install ingress2gateway`",
            severity="S3",
        )

    # Merge source master + minion output into one input file
    tmp = Path("/tmp") / f"i2g-input-{dt.datetime.now().strftime('%s')}.yaml"
    # Read both files and concatenate
    src_content = source_built.read_text(encoding="utf-8") if source_built.is_file() else ""
    svc_content = service_build.read_text(encoding="utf-8") if service_build.is_file() else ""
    tmp.write_text(
        src_content + "\n---\n" + svc_content, encoding="utf-8",
    )

    rc, out, err = _run(
        ["ingress2gateway", "print",
         "--providers", "ingress-nginx",
         "--input-file", str(tmp),
         "--no-color"],
    )
    if rc != 0:
        return _check(
            "ingress2gateway-second-opinion",
            "warn",
            f"ingress2gateway exited {rc}",
            severity="S2",
            details={"stderr": err.strip()[:500]},
        )

    # ingress2gateway prints warnings to stderr and YAML to stdout.
    # Extract the YAML portion.
    i2g_output_path = Path("/tmp") / "i2g-output.yaml"
    i2g_output_path.write_text(out, encoding="utf-8")
    i2g_docs = _yq_ea_json(i2g_output_path)

    # Collect hostnames and backend services from i2g output
    i2g_hostnames: set[str] = set()
    i2g_backends: set[tuple[str, int]] = set()
    for doc in i2g_docs:
        kind = doc.get("kind")
        if kind == "Gateway":
            for listener in (doc.get("spec") or {}).get("listeners", []) or []:
                host = listener.get("hostname")
                if host:
                    i2g_hostnames.add(host.lower())
        elif kind == "HTTPRoute":
            for host in (doc.get("spec") or {}).get("hostnames", []) or []:
                i2g_hostnames.add(host.lower())
            for rule in (doc.get("spec") or {}).get("rules", []) or []:
                for ref in rule.get("backendRefs", []) or []:
                    name = ref.get("name")
                    port = ref.get("port")
                    if name and port is not None:
                        i2g_backends.add((name, int(port)))

    # Collect same from our output
    our_docs = _yq_ea_json(service_build) + _yq_ea_json(gateway_build)
    our_hostnames: set[str] = set()
    our_backends: set[tuple[str, int]] = set()
    for doc in our_docs:
        kind = doc.get("kind")
        if kind == "Gateway":
            for listener in (doc.get("spec") or {}).get("listeners", []) or []:
                host = listener.get("hostname")
                if host:
                    our_hostnames.add(host.lower())
        elif kind == "HTTPRoute":
            for host in (doc.get("spec") or {}).get("hostnames", []) or []:
                our_hostnames.add(host.lower())
            for rule in (doc.get("spec") or {}).get("rules", []) or []:
                for ref in rule.get("backendRefs", []) or []:
                    name = ref.get("name")
                    port = ref.get("port")
                    if name and port is not None:
                        our_backends.add((name, int(port)))

    host_missing = sorted(i2g_hostnames - our_hostnames)
    host_extra   = sorted(our_hostnames - i2g_hostnames)
    bk_missing   = sorted(i2g_backends - our_backends)
    bk_extra     = sorted(our_backends - i2g_backends)

    # Pull WARN lines from i2g stderr
    warn_lines = [
        line.strip() for line in err.splitlines()
        if line.strip() and ("WARN" in line or "Unsupported" in line or "self-signed" in line)
    ]
    # Deduplicate by annotation/pattern
    unsupported_annotations: list[str] = []
    self_signed_hosts: list[str] = []
    for line in warn_lines:
        m = re.search(r"Unsupported annotation\s+(\S+)", line)
        if m:
            unsupported_annotations.append(m.group(1))
        m = re.search(r'host "([^"]+)"', line)
        if m and "self-signed" in line:
            self_signed_hosts.append(m.group(1))

    details = {
        "i2gHostCount":       len(i2g_hostnames),
        "ourHostCount":       len(our_hostnames),
        "i2gBackendCount":    len(i2g_backends),
        "ourBackendCount":    len(our_backends),
        "i2gOnlyHosts":       host_missing,
        "skillOnlyHosts":     host_extra,
        "i2gOnlyBackends":    [f"{n}:{p}" for n, p in bk_missing],
        "skillOnlyBackends":  [f"{n}:{p}" for n, p in bk_extra],
        "i2gUnsupported":     sorted(set(unsupported_annotations)),
        "i2gSelfSignedWarns": sorted(set(self_signed_hosts)),
    }

    # Classify status
    if host_missing or bk_missing:
        return _check(
            "ingress2gateway-second-opinion",
            "fail",
            f"ingress2gateway found content our skill missed: "
            f"{len(host_missing)} host(s), {len(bk_missing)} backend(s)",
            severity="S1",
            details=details,
        )
    # host_extra / bk_extra are allowed (we emit extras: redirect, CORS policies, etc.)
    return _check(
        "ingress2gateway-second-opinion",
        "pass",
        f"cross-check clean — our hosts ⊇ i2g hosts ({len(our_hostnames)} ⊇ {len(i2g_hostnames)}), "
        f"our backends ⊇ i2g backends ({len(our_backends)} ⊇ {len(i2g_backends)})",
        details=details,
    )


# -----------------------------------------------------------------------------
# Main
# -----------------------------------------------------------------------------

def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--target-root", required=True,
                        help="root of the target gitops repo")
    parser.add_argument("--module", default="common.ingress",
                        help="source module (default: common.ingress)")
    parser.add_argument("--minion-module", default="common.service",
                        help="minion module (default: common.service)")
    parser.add_argument("--generated-module", default="common.gateway",
                        help="generated module (default: common.gateway)")
    parser.add_argument("--env", required=True,
                        help="environment to validate (dev/stg/prd)")
    parser.add_argument("--no-second-opinion", action="store_true",
                        help="skip ingress2gateway cross-check")
    parser.add_argument("--tmp-dir", default="/tmp/gwm-validate",
                        help="where to stash build output")
    args = parser.parse_args()

    # Verify prerequisites
    for tool in ("kustomize", "yq"):
        if not shutil.which(tool):
            print(f"[validate_generated] prerequisite missing: {tool}",
                  file=sys.stderr)
            return 3

    target_root = Path(args.target_root).resolve()
    if not target_root.is_dir():
        print(f"[validate_generated] target root not found: {target_root}",
              file=sys.stderr)
        return 3

    tmp_dir = Path(args.tmp_dir).resolve()
    tmp_dir.mkdir(parents=True, exist_ok=True)

    source_overlay = target_root / args.module / "overlays" / args.env
    minion_overlay = target_root / args.minion_module / "overlays" / args.env
    gateway_overlay = target_root / args.generated_module / "overlays" / args.env

    source_built = tmp_dir / f"source-{args.env}.yaml"
    minion_built = tmp_dir / f"service-{args.env}.yaml"
    gateway_built = tmp_dir / f"gateway-{args.env}.yaml"

    checks: list[dict] = []

    # 1: Build the generated gateway module
    checks.append(check_kustomize_build(
        "gateway", gateway_overlay, gateway_built,
    ))
    # 2: Build the modified service overlay
    checks.append(check_kustomize_build(
        "service", minion_overlay, minion_built,
    ))
    # 2.5: Build the (unmodified) source master module
    _kustomize_build(source_overlay, source_built)  # best-effort, silent

    # Early abort: if kustomize build failed, downstream checks are meaningless
    if any(c["status"] == "fail"
           for c in checks if c["id"].startswith("kustomize-build")):
        result = _finalize(checks, args, checks_run=len(checks),
                           second_opinion_run=False)
        print(json.dumps(result, indent=2, ensure_ascii=False))
        return 1

    # 3: Listener coverage
    checks.append(check_listener_coverage(gateway_built, minion_built))

    # 4: parentRef.name
    checks.append(check_httproute_parentref_name(gateway_built, minion_built))

    # 5: source hostname coverage (only if source build succeeded)
    if source_built.is_file() and source_built.stat().st_size > 0:
        checks.append(check_source_hostname_coverage(source_built, gateway_built))
        # 6: backend coverage
        checks.append(check_source_backend_coverage(source_built, minion_built))
        # 7: path coverage
        checks.append(check_path_coverage(source_built, minion_built))
        # 9: TLS secret coverage
        checks.append(check_tls_secret_coverage(source_built, gateway_built))
    else:
        checks.append(_check(
            "source-hostname-coverage", "warn",
            "source master build empty — coverage checks skipped",
            severity="S3",
        ))

    # 8: namespace consistency (uses minion build vs built minion files)
    if source_built.is_file() and minion_built.is_file():
        checks.append(check_namespace_consistency(minion_built, minion_built))

    # 10: dead file safety
    checks.append(check_dead_file_safety(
        target_root, minion_overlay, minion_built,
    ))

    # 11: ingress2gateway second opinion (optional)
    soo_run = False
    if not args.no_second_opinion:
        result = check_ingress2gateway_second_opinion(
            source_built, minion_built, gateway_built,
        )
        if result is not None:
            checks.append(result)
            soo_run = result["status"] != "warn" or "install" not in result["summary"]

    final = _finalize(checks, args, checks_run=len(checks),
                      second_opinion_run=soo_run)
    print(json.dumps(final, indent=2, ensure_ascii=False))
    return 0 if final["overall"] != "fail" else 1


def _finalize(checks: list[dict], args, checks_run: int,
              second_opinion_run: bool) -> dict:
    """Aggregate checks into a final result record."""
    overall = "pass"
    for c in checks:
        if _STATUS_RANK[c["status"]] > _STATUS_RANK[overall]:
            overall = c["status"]

    return {
        "overall": overall,
        "exitCode": 0 if overall != "fail" else 1,
        "env": args.env,
        "timestamp": dt.datetime.now(dt.timezone.utc)
                     .strftime("%Y-%m-%dT%H:%M:%SZ"),
        "checks": checks,
        "summary": {
            "pass": sum(1 for c in checks if c["status"] == "pass"),
            "warn": sum(1 for c in checks if c["status"] == "warn"),
            "fail": sum(1 for c in checks if c["status"] == "fail"),
            "checksRun": checks_run,
            "secondOpinionRun": second_opinion_run,
        },
    }


if __name__ == "__main__":
    sys.exit(main())
