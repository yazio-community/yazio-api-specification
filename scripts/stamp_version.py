#!/usr/bin/env python3
"""Write `info.version` into a bundled spec.

`spec/openapi.yaml` carries `0.0.0-dev` between releases, so the artifact
attached to a GitHub release has to be told which tag produced it. This is the
only thing the release pipeline changes about the bundle — title, description
and license live in `spec/openapi.yaml` and are not touched here.

Requires ruamel.yaml, which preserves comments and key order:
  nix-shell --run "python3 scripts/stamp_version.py FILE --version 0.2.0"

Usage: stamp_version.py <file.yaml> --version VERSION [--dry-run]
"""

import argparse
import sys
from pathlib import Path

try:
    from ruamel.yaml import YAML
except ImportError:
    sys.exit(
        "error: ruamel.yaml is required\n"
        "       nix-shell --run 'python3 scripts/stamp_version.py FILE --version X'"
    )


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("file", type=Path)
    parser.add_argument("--version", required=True)
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()

    yaml = YAML()
    yaml.preserve_quotes = True
    spec = yaml.load(args.file)

    if "info" not in spec:
        sys.exit(f"error: {args.file} has no info block")

    before = spec["info"].get("version")
    spec["info"]["version"] = args.version
    print(f"info.version: {before} -> {args.version}")

    if args.dry_run:
        return 0

    yaml.dump(spec, args.file)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
