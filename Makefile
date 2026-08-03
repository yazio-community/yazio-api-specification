# Everything here expects the nix-shell: `nix-shell --run "make lint"`.
#
# The source of truth is the spec/ tree: one file per path, one per schema,
# with spec/openapi.yaml holding info, servers and tags. It is edited by hand.
# Nothing in this Makefile writes into spec/ — the bundle is a build output and
# the capture is only ever a source of suggestions.

SOURCE  ?= spec/openapi.yaml
BUNDLE  ?= dist/openapi.yaml
SCRATCH ?= dist/capture.yaml
CAPTURE ?= yazio.flows
BASE    ?= https://yzapi.yazio.com
REDOCLY ?= npx --yes @redocly/cli@latest

.PHONY: help bundle lint capture-diff clean

help:
	@echo "make bundle        compose $(SOURCE) and its \$$refs into $(BUNDLE)"
	@echo "make lint          bundle, then validate the result against the ruleset"
	@echo "make capture-diff  show what a $(CAPTURE) capture knows that spec/ does not"

bundle:
	@mkdir -p $(dir $(BUNDLE))
	$(REDOCLY) bundle $(SOURCE) -o $(BUNDLE)

# Lint the bundle, not the tree: the bundle is what ships and what the SDK
# generators consume. Line numbers in errors refer to $(BUNDLE); find the
# offending source file by searching spec/ for the path or schema name.
lint: bundle
	$(REDOCLY) lint $(BUNDLE)

# Fold a capture into a *scratch copy* of the bundle and diff it. Nothing is
# written back into spec/ — the diff is the deliverable, and you apply it by
# hand.
#
# mitmproxy2swagger must never be pointed at $(SOURCE). It does not resolve
# $refs: it reads `paths` keys, finds no `get`/`post` under a `{$ref: ...}`
# node, and injects a whole inline operation as a sibling of the $ref. Redocly
# then drops the $ref and keeps the injection, so the hand-written file is
# silently discarded from the bundle. The scratch bundle has no external refs
# at all, so the tool behaves as designed there: every write goes through
# set_key_if_not_exists, meaning it only ever fills gaps and leaves existing
# descriptions, examples and corrected types alone.
#
# A path the capture has not seen before is appended to x-path-templates with
# an `ignore:` prefix rather than generated. To pull one in: delete the prefix
# in $(SCRATCH), then run this target again — the second pass fills in its
# schemas. Re-seed from scratch with `make clean`.
capture-diff: bundle
	@test -f $(SCRATCH) || cp $(BUNDLE) $(SCRATCH)
	mitmproxy2swagger -i $(CAPTURE) -o $(SCRATCH) -p $(BASE) -f flow
	@echo
	@echo "=== what $(CAPTURE) adds to spec/ ==="
	@diff -u $(BUNDLE) $(SCRATCH) || true

clean:
	rm -rf dist
