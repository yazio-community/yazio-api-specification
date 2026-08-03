# yazio-api-specification

An OpenAPI 3.0 description of the private API behind the [YAZIO](https://www.yazio.com)
food-diary app, at `https://yzapi.yazio.com`.

This is the source of truth for the `yazio-community` organisation. Every SDK is
generated from the released `openapi.yaml`; nothing downstream is edited by hand.

> [!IMPORTANT]
> Unofficial and unaffiliated. YAZIO does not publish, endorse or support this
> description, and the API it describes is private: it can change without
> notice, and using it is subject to YAZIO's terms of service. The spec was
> produced by observing one account's own traffic. Treat it as a field guide,
> not a contract.

## What is in here

| Path                             | What it is                                                                   |
| -------------------------------- | ---------------------------------------------------------------------------- |
| `spec/openapi.yaml`              | The root document: `info`, `servers`, `tags`, and a `$ref` per path.         |
| `spec/paths/**.yaml`             | One file per route, nested by URL. All verbs for a route live together.      |
| `spec/components/schemas/*.yaml` | One file per model. These filenames become the generated class names.        |
| `dist/openapi.yaml`              | The bundle. Build output, gitignored, and the only artifact consumers need.  |
| `scripts/stamp_version.py`       | Writes `info.version` into the bundle at release time. The only script left. |

Nothing writes into `spec/`. Edit it directly — descriptions, examples,
corrected types and tags all belong in these files.

## Consuming it

Releases are tagged `vMAJOR.MINOR.PATCH` and attach the bundled `openapi.yaml`
as an asset:

```bash
curl -sSLO https://github.com/yazio-community/yazio-api-specification/releases/latest/download/openapi.yaml
```

Pin a tag rather than tracking `main`. `main` is a working branch — a spec edit
lands there long before anyone has checked that a generator still accepts it.

Versions are plain semver, judged by what a change does to generated code:
patch leaves it identical, minor adds surface, major breaks callers. The YAZIO
API version is _not_ in that number — it is `22`, it is in `info.x-api-version`
and in every path, and it moves only if YAZIO ships a new API version, which
would be a separate document.

**Each SDK carries the version of the spec it was generated from.** Spec `1.4.2`
is `yazio-sdk==1.4.2`, so the package version alone tells you which description
produced the client. A `.postN` suffix means the SDK was rebuilt without a spec
change.

### Generated SDKs

- [yazio-sdk-python](https://github.com/yazio-community/yazio-sdk-python) — `pip install yazio-sdk`

Tagging a release here dispatches to each SDK repo, which regenerates itself,
opens a PR with the diff, and publishes once that PR is merged. See
[`.github/workflows/release.yml`](.github/workflows/release.yml).

## How the spec is maintained

The tree was **originally inferred from captured traffic**, and the consequence
is still visible throughout: an endpoint the app never called during the
recording does not exist here, and a field that happened to be `null` throughout
is typed from that null. Coverage is a function of what the app was made to do
while mitmproxy was in front of it.

From here it is maintained **by hand**. Editing `spec/` is the workflow; nothing
writes into it.

```bash
nix-shell            # mitmproxy, mitmproxy2swagger, node, python + ruamel.yaml
make bundle          # spec/ -> dist/openapi.yaml
make lint            # bundle, then validate
make capture-diff    # what a new capture knows that spec/ does not
```

### Folding in a new capture

`make capture-diff` never touches `spec/`. It copies the bundle to a scratch
file, lets mitmproxy2swagger fill the gaps in _that_, and diffs the result. You
read the diff and write the parts worth keeping into `spec/` yourself.

That indirection is not fussiness. **mitmproxy2swagger does not resolve
`$ref`.** Pointed at `spec/openapi.yaml` it reads the `paths` keys, finds no
`get` under a `{$ref: …}` node, and injects a whole inline operation as a
sibling of the `$ref`. Redocly then drops the `$ref` and keeps the injection, so
the hand-written route file vanishes from the bundle — with no error, and no
lint rule that catches it. The scratch bundle has no external refs, so the tool
behaves as designed there: every write goes through `set_key_if_not_exists`, so
it only fills gaps and leaves existing descriptions and corrected types alone.

The flip side of gap-filling is that it can never _correct_ an existing schema
either. Once a response shape is in `spec/`, a changed API will not appear in
the diff. Confirm suspected drift by calling the endpoint yourself.

A path the capture has not seen before is appended to `x-path-templates` with an
`ignore:` prefix rather than generated, and concrete ids are not collapsed for
you — `/v22/user/recipes/8f3e…` arrives verbatim. To pull one in, rewrite it as
a `{id}` template and delete the prefix in `dist/capture.yaml`, then run the
target again; the second pass fills in its schemas. `make clean` re-seeds the
scratch file.

### Things that used to be scripts

Tag assignment, date-map collapsing and schema hoisting were post-processors.
They are hand edits now, because the tree makes them local: a tag is a line in a
route file, and a shared model is a file in `spec/components/schemas/` whose
**filename becomes the generated class name**. Keep one tag per operation — the
Python generator groups endpoints by the first tag only, and a second tag just
scatters an endpoint across directories.

`info` is not generated either; it lives in `spec/openapi.yaml`, and only
`info.version` is rewritten, at release time, from the tag.

### Capturing traffic

```bash
mitmproxy --set confdir=.mitmproxy -w yazio.flows
```

Point the phone at the proxy, install its CA, then use the app: open each tab,
log an item, remove it, create a recipe. Endpoints you do not exercise will not
appear. `*.flows` is gitignored and must stay that way — a capture contains your
OAuth tokens and your health data.

## Things the API does not document

Established against the live API and folded into the spec. These are the ones
that cost real debugging time:

- **The client version is checked, and it lives in the User-Agent.** Anything
  unrecognised gets `403 {"error":"version_blocked"}` on every endpoint except
  the token exchange. The string the captured app sent:

  ```
  YAZIO/26.30.1 (com.yazio.ios.YAZIO; build:2607271240; iOS 27.0.0) Ktor
  ```

  It needs bumping whenever YAZIO retires that app version. A sudden wall of
  403s from everywhere but `/v22/oauth/token` is the symptom.

- **Product search is ranked by `Accept-Language`.** The same query answers
  differently for a German and an English client.
- **Product search requires `sex` and `countries`**, even though every search
  parameter is optional in the inferred spec. Omitting either answers 400.
- **Removing a diary entry** is `DELETE /v22/user/consumed-items` with a JSON
  body naming the bucket, whose value is a single id _string_:
  `{"products": "<uuid>"}`. A list is rejected. The endpoint also accepts an
  `?id=` query parameter, answers `204`, and does nothing — so read the day back
  rather than trusting the status code.
- **A consumed item's `date` is a full timestamp** (`2026-08-02 16:02:48`), even
  though the `date` query parameter that reads a day back out is a plain date.
- **`/v22/user/bodyvalues/weight/last` requires a `date`**; "last" means the
  latest entry on or before that day.
- **Product nutrients are per one base unit, not per 100.** Olive oil reads 8.84
  kcal per gram. Getting this wrong scales every computed total by 100.
- **A recipe needs two or more ingredients**, and an integer `portion_count` —
  not merely integral in value, it has to serialise without a decimal point.
  `2` is accepted; `2.0` and `2.5` are both answered with a bare `500`.
- **A meal in the daily summary is `{energy_goal, nutrients}`** — the nutrients
  are a level down, and each meal carries its own slice of the energy budget.

### Checking a shape against the live API

There is no probe script any more. Call the endpoint yourself with `curl` or
`httpx` against your own account, and write what you see into `spec/`. Never
commit the response — it is your own health data — and put credentials in
`.env`, which is gitignored, rather than in a shell history.

## Authentication

`POST /v22/oauth/token` exchanges a username and password for a bearer token.
The OAuth client credentials are the ones the mobile app ships with: they
identify the app rather than the user, every install sends the same pair, and
they are therefore not secret. Both are in the request schema as examples —
[`spec/components/schemas/OAuthTokenRequest.yaml`](spec/components/schemas/OAuthTokenRequest.yaml)
— so a generated SDK and a reader of the published spec both have them.

```
client_id      3_5rbw4kehpugw8ogsc8ck8oo4ogswgckcskc04gcg8kk8k48ssw
client_secret  25gdtt1hvdi8gwowoww4oo88sgsw0oo04o0og0kkgwwks8k0k
```

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md). Short version: edit the files under
`spec/`, run `make lint`, and never commit a capture, a `.env`, or a response
from a real account.

## Licence

[MIT](LICENSE). The specification describes an API owned by YAZIO GmbH; the
licence covers this description of it, not the service.
