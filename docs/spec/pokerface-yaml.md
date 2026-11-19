# `pokerface.yaml` v0.1 Specification

> Status: v0.1, implemented by `src/config.emo` (task T1.4). `pokerface.yaml`
> lives at the root of the application repository and describes how the
> project's image is built and pushed (decision D2). The CI-generated
> companion file is `pokerface.lock.yaml` (T1.5,
> `docs/spec/pokerface-lock.md`).

## Example

```yaml
version: 1
image: registry.example.com/acme/app
build:
  context: "."
  dockerfile: Dockerfile
  target: runtime
  platforms:
    - linux/amd64
  args:
    NODE_ENV: production
tags:
  - latest
  - "{{ commit.short }}"
registry:
  url: https://registry.example.com
```

A copy lives at `examples/pokerface.yaml`; `test/config.emo` parses it on
every run.

## Field table

| Field | Type | Required | Default | Description |
| --- | --- | --- | --- | --- |
| `version` | integer | yes | — | Must be exactly `1`. A future version of the file bumps this number; v0.1 rejects anything else. |
| `image` | string | yes | — | The registry image name, lowercase, `<host>[:<port>]/<owner>/<repo>` — e.g. `registry.example.com/acme/app`. No scheme, no tag, no digest; tags come from the `tags` section. |
| `build` | mapping | yes | — | How the image is built. |
| `build.context` | string | yes | — | The build context directory, relative to the repository root. **Quote a bare `.`** — YAML's core schema reads `.` as a float, and the parser rejects a number here with a hint. |
| `build.dockerfile` | string | no | `Dockerfile` | The Dockerfile path, relative to the build context. Must not be empty when present. |
| `build.target` | string | no | *(none)* | The Dockerfile stage to build; empty means the final stage. |
| `build.platforms` | list of strings | no | `[linux/amd64]` | Target platforms, each `<os>/<arch>`. Supported os: `linux`, `windows`, `darwin`, `freebsd`. Supported arch: `amd64`, `arm64`, `arm`, `386`, `riscv64`. At least one is required when present. |
| `build.args` | mapping of string → string | no | `{}` | Build args passed to the builder. Values must be YAML strings — quote numbers (`FOO: "123"`), a plain `FOO: 123` is rejected. |
| `tags` | list of strings | no | `[latest]` | Tag rules; see the next section. At least one is required when present; duplicates are rejected. |
| `registry` | mapping | no | *(absent)* | Where `build --push` uploads. Absent is valid for pull-only repositories; T4.1 requires it for pushes. |
| `registry.url` | string | (required when `registry` is present) | — | The registry base URL, starting `https://` (or `http://` for a local development registry). Trailing slashes are stripped. |

## Unknown fields

While `version` is `1`, unknown fields at any level are rejected with an
error naming the field's path (`pokerface.yaml: build.bogus: unknown field …`).
A future file version may relax this for forward compatibility.

## Tag rules

A tag rule is a string of at most 128 characters, either:

- a **literal tag** — lowercase `[a-z0-9._-]+` (the OCI tag charset), e.g.
  `latest`, `stable`, `sha-01234567`; or
- a **template** containing one or more `{{ placeholder }}` holes, with any
  literal prefix or suffix in the same charset, e.g. `sha-{{ commit.short }}`
  or `v{{ version }}`.

Supported placeholders:

| Placeholder | Renders to (see [build-plan.md](build-plan.md)) | Example |
| --- | --- | --- |
| `{{ commit.short }}` | The 8-character commit SHA the image was built from | `sha-01234567` |
| `{{ git.tag }}` | The Git tag that triggered the build; empty when the build was not tag-triggered | `v1.2.0` |
| `{{ branch }}` | The Git branch the image was built from | `main` |
| `{{ version }}` | The project's version string | `1.4.2` |

Validation rejects, with the tag's position (`tags[1]`) in the error:

- an unterminated placeholder (`"{{ commit.short"`);
- an unknown placeholder name (`"{{ nope }}"`);
- characters outside the literal charset outside the holes
  (`"Bad Tag"` — uppercase and space).

Two tag rules that are identical strings are rejected as duplicates.
Two distinct *templates* that render to the same tag at build time collide
there — [build-plan.md](build-plan.md) has the check.

## Error format

Every parse or validation failure is a single-line reason:

```text
pokerface.yaml: <path>: <message>
```

`<path>` is the dotted field path, with indexes for list items
(`tags[1]`, `build.platforms[0]`). Examples:

```text
pokerface.yaml: version: missing required field
pokerface.yaml: build.context: a number is not a valid context — YAML reads a bare '.' as a float; quote it: context: "."
pokerface.yaml: tags[1]: duplicate tag 'latest'
pokerface.yaml: registry.url: must start with https:// or http://
```
