{ pkgs ? import <nixpkgs> { } }:

let
  python = pkgs.python3.withPackages (ps: [
    # Round-trip YAML editing that preserves comments and key order. Used by
    # scripts/stamp_version.py, which rewrites one key in the release bundle
    # and must leave everything else byte-identical.
    ps.ruamel-yaml
  ]);
in
pkgs.mkShell {
  name = "yazio-api-specification";

  packages = [
    python
    pkgs.mitmproxy # capture the app's traffic into yazio.flows
    pkgs.mitmproxy2swagger # read that capture for `make capture-diff`
    pkgs.nodejs # `npx @redocly/cli lint`, the same check CI runs
  ];

  shellHook = ''
    echo "yazio-api-specification dev shell"
    echo
    echo "  make bundle        compose spec/ into dist/openapi.yaml"
    echo "  make lint          bundle, then validate the result"
    echo "  make capture-diff  what a yazio.flows capture adds to spec/"
  '';
}
