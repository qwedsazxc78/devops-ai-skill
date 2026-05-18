#!/usr/bin/env python3
"""
update_kustomization.py — idempotent kustomization.yaml edits for skill A.

Two operations:

  --replace OLD=NEW   In `resources:`, replace entry OLD with NEW. If NEW is
                      already present (and OLD is absent), no-op.
  --drop-patch FILE   Drop FILE from `patches:`. If absent, no-op.
  --add-host HOST     Append HOST to common.traefik/overlays/<env>/app.ingress.yaml
                      managed-cert host list. If HOST already present, no-op.

Usage:
    update_kustomization.py --overlay-dir <path> [--replace OLD=NEW]... [--drop-patch FILE]
    update_kustomization.py --app-ingress <path> [--add-host HOST]...
"""
from __future__ import annotations

import argparse
import sys
from pathlib import Path
import subprocess


def _yq(expr: str, file: Path) -> None:
    rc = subprocess.run(["yq", "-i", expr, str(file)], capture_output=True, text=True)
    if rc.returncode != 0:
        sys.stderr.write(rc.stderr)
        sys.exit(2)


def _yq_read(expr: str, file: Path) -> str:
    rc = subprocess.run(["yq", "-r", expr, str(file)], capture_output=True, text=True)
    if rc.returncode != 0:
        sys.stderr.write(rc.stderr)
        sys.exit(2)
    return rc.stdout.strip()


def replace_resource(kfile: Path, old: str, new: str) -> None:
    has_new = _yq_read(f'.resources // [] | contains(["{new}"])', kfile) == "true"
    has_old = _yq_read(f'.resources // [] | contains(["{old}"])', kfile) == "true"
    if has_new and not has_old:
        return
    _yq(f'(.resources[] | select(. == "{old}")) |= "{new}"', kfile)
    _yq('.resources |= unique', kfile)


def drop_patch(kfile: Path, fname: str) -> None:
    has_patch = _yq_read(f'(.patches // []) | map(.path // "") | contains(["{fname}"])', kfile) == "true"
    if not has_patch:
        return
    _yq(f'(.patches //= []) | del(.patches[] | select(.path == "{fname}"))', kfile)


def add_host(app_ingress: Path, host: str) -> None:
    has_host = _yq_read(
        f'(.spec.rules // []) | map(.host) | contains(["{host}"])', app_ingress
    ) == "true"
    if has_host:
        return
    _yq(f'.spec.rules += [{{"host": "{host}"}}]', app_ingress)


def main() -> int:
    p = argparse.ArgumentParser()
    p.add_argument("--overlay-dir", type=Path)
    p.add_argument("--app-ingress", type=Path)
    p.add_argument("--replace", action="append", default=[])
    p.add_argument("--drop-patch", action="append", default=[])
    p.add_argument("--add-host", action="append", default=[])
    args = p.parse_args()

    if args.overlay_dir:
        kfile = args.overlay_dir / "kustomization.yaml"
        if not kfile.is_file():
            print(f"[update_kustomization] not found: {kfile}", file=sys.stderr)
            return 2
        for spec in args.replace:
            if "=" not in spec:
                print(f"[update_kustomization] --replace expects OLD=NEW, got {spec!r}", file=sys.stderr)
                return 2
            old, new = spec.split("=", 1)
            replace_resource(kfile, old, new)
        for fname in args.drop_patch:
            drop_patch(kfile, fname)

    if args.app_ingress:
        if not args.app_ingress.is_file():
            print(f"[update_kustomization] not found: {args.app_ingress}", file=sys.stderr)
            return 2
        for host in args.add_host:
            add_host(args.app_ingress, host)

    return 0


if __name__ == "__main__":
    sys.exit(main())
