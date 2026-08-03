# Contributing

## Before anything else: what must never be committed

A mitmproxy capture contains OAuth tokens, your email, and your logged weight
and meals. So does any response you save while checking a shape against the live
API. `*.flows`, `*.har` and `.env` are gitignored; if you find yourself adding
`-f` to a `git add`, stop.

If you have already pushed a capture, the file has to be purged from history and
the account's password changed — a `git rm` does not help.

## Fixing the spec

The source of truth is the `spec/` tree, and it is meant to be edited by hand.
`dist/openapi.yaml` is a build output — never edit it, it is gitignored.

- **A description, an example, a tag, a corrected type** → edit the route's file
  under `spec/paths/`, or the model under `spec/components/schemas/`.
- **A new shared model** → a new file in `spec/components/schemas/`. Its
  **filename becomes the generated class name**, so rename one only when you
  mean to break every SDK.
- **A wrong or missing schema** → the capture did not cover it. Call the
  endpoint against your own account, confirm the real shape, and write it in
  directly.
- **Title, servers, tag descriptions** → `spec/openapi.yaml`.

Never point mitmproxy2swagger at `spec/openapi.yaml`. It does not resolve
`$ref`, so it injects an inline operation next to the `$ref`, and bundling then
keeps the injection and drops the file — silently. Use `make capture-diff`,
which runs it against a scratch copy of the bundle instead.

Never write real examples out of a capture or a probe: they are your own weight,
meals, email and tokens. This is also why nothing here passes mitmproxy2swagger's
`--examples` flag — it truncates but does not redact. Write examples by hand
with made-up values.

Prefer `description:` over a `#` comment where the note is about the API rather
than about the file. A description reaches whoever reads the generated SDK; a
comment only reaches whoever opens this repo.

## Checks

```bash
nix-shell --run "make lint"
```

That bundles `spec/` into `dist/openapi.yaml` and validates the result. Lint
errors carry bundle line numbers, so find the source file by searching `spec/`
for the path or schema name in the message.

**Run it before you tag.** There is no PR-time CI: the release workflow is the
only automation in the repo, and it lints the same bundle. A lint failure there
costs you a tag, since a pushed tag cannot be reused.

Nothing checks that the spec actually *generates*. The Python generator is
stricter than the linter about several things (duplicate model titles, unnamed
inline enums), so a spec can lint cleanly and still fail in the SDK repo after
the dispatch. To check by hand before releasing:

```bash
make bundle
pip install openapi-python-client==0.29.0
openapi-python-client generate --path dist/openapi.yaml --meta none \
  --output-path /tmp/yazio_api --overwrite
```

## Adding an endpoint the capture missed

1. Capture it: run mitmproxy, do the thing in the app, then `make capture-diff`.
   The route shows up in `x-path-templates` with an `ignore:` prefix and its
   concrete ids intact. Rewrite it as an `{id}` template, drop the prefix in
   `dist/capture.yaml`, and run the target again to get its schemas.
2. If the app has no UI for it, call it yourself against your own account. The
   client credentials and the User-Agent you need are in the spec — see
   `OAuthTokenRequest` and `info.description`.
3. Either way, write the result by hand: a new file under `spec/paths/`, plus a
   `$ref` for it in the `paths:` block of `spec/openapi.yaml`. Forgetting the
   `$ref` is the easy mistake — the file exists, and the endpoint is simply
   absent from the bundle.
4. Give it a tag that already exists unless the endpoint really is a new area,
   and only one — the Python generator groups by the first tag only.

## Releasing

```bash
git tag v0.2.0
git push origin v0.2.0
```

That bundles `spec/` into a single `openapi.yaml`, stamps `info.version` from
the tag, lints it, attaches it to a GitHub release, and dispatches to every SDK
repo.

### Version by impact on consumers

Plain semver, judged by what a change does to *generated code* — not by which
part of the document you edited:

- **patch** — descriptions, examples, tags; generated code is identical
- **minor** — new endpoints or fields; generated code gains API surface
- **major** — a changed or removed endpoint or field; generated code breaks

A removed endpoint is a major bump even though it is "just a path", and a
retyped field is a major bump even though it is "just a parameter". Consumers
write `yazio-sdk ^1.2.0` and the solver acts on that number, so it has to mean
compatibility rather than describe what kind of edit happened.

The YAZIO API version — the `22` in every path — is **not** part of this number.
It lives in `info.x-api-version` and in the description. A move to `/v23` would
be a new document, not a major bump here, because consumers will want one
version's surface rather than a union of two.

### Every SDK ships the version of the spec it was generated from

Spec `1.4.2` produces `yazio-sdk==1.4.2`. There is no separate SDK version line,
so "which spec is this client built from" is answerable from the package version
alone.

The one case this does not cover is an SDK rebuild with no spec change — a
generator upgrade, a template fix. Release that as a PEP 440 post-release of the
same spec version (`1.4.2.post1`) rather than tagging a spec that did not
change. The release workflow accepts `vMAJOR.MINOR.PATCH[.postN]` and rejects
anything else, since the SDKs publish under this exact string.

The `v` on the git tag is a git convention and never reaches a package manager.
The workflow strips it exactly once and hands both forms downstream:

| payload field | example | used for |
| --- | --- | --- |
| `spec_version` | `1.4.2` | the SDK's published version; equals `info.version` |
| `spec_tag` | `v1.4.2` | the asset URL, `…/releases/download/v1.4.2/openapi.yaml` |

An SDK repo should use each as given and never derive one from the other — that
is exactly how a stray `v` ends up in a published package version.

Check the SDK PRs the dispatch opens before merging them. A spec change that
looked cosmetic can rename a generated class — and since nothing runs the
generator before release, that PR is where you find out.
