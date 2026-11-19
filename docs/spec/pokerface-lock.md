# `pokerface.lock.yaml` v0.1 Specification

> Status: v0.1, implemented by `src/lockfile.emo` (tasks T1.5 and T4.4). CI
> writes this file back to the application repository after a successful
> build and push (decision D2), so the pull side can resolve
> `tag → commit → digest` from Git alone. The build-side input is
> `pokerface.yaml` (`docs/spec/pokerface-yaml.md`).

## Example

```yaml
version: 1
commit: "0123456789abcdef0123456789abcdef01234567"
source: github.com/acme/app
generated_at: "2026-11-18T08:30:00Z"
images:
  - image: registry.example.com/acme/app
    tags: [latest, sha-01234567]
    digest: sha256:0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef
    manifest_digest: sha256:fedcba9876543210fedcba9876543210fedcba9876543210fedcba9876543210
    platforms: [linux/amd64]
    builder: buildkit
```

A copy lives at `examples/pokerface.lock.yaml`; `test/lockfile.emo` parses it
on every run.

## Field table

| Field | Type | Required | Default | Description |
| --- | --- | --- | --- | --- |
| `version` | integer | yes | — | Must be exactly `1`; any other value — including a string or float — is rejected as an unknown version. |
| `commit` | string | yes | — | The **full** 40-character lowercase hex commit SHA the images were built from. Short SHAs are rejected. |
| `source` | string | yes | — | The repository the images were built from, in any D3 form (`github.com/acme/app`, `https://github.com/acme/app.git`, `git@github.com:acme/app`). Normalized to the bare `<host>/<owner>/<repo>` shape when parsed. A ref in the source is rejected — `commit` carries that information. |
| `generated_at` | string | no | *(absent)* | RFC 3339 timestamp of when CI wrote the file. Informational only — see "Digest verification" below. Quoted in the canonical encoding. |
| `images` | list of mappings | yes | — | One entry per pushed image; at least one, and no two entries may name the same `image`. |

Each `images` entry:

| Field | Type | Required | Default | Description |
| --- | --- | --- | --- | --- |
| `image` | string | yes | — | The registry image name, validated like `pokerface.yaml`'s `image` (lowercase, no tag, no digest). |
| `tags` | list of strings | yes | — | The tags this build pushed for the image, each already **rendered**: lowercase `[a-z0-9._-]`, at most 128 characters, no duplicates, no `{{ placeholder }}` syntax. |
| `digest` | string | yes | — | `sha256:` followed by 64 lowercase hex characters — the top-level index digest for a multi-platform build, or the single-platform manifest digest. |
| `manifest_digest` | string | no | *(absent)* | The selected platform's manifest digest, `sha256:` + 64 hex. Absent means "same as `digest`" — consumers fall back to `digest`. |
| `platforms` | list of strings | no | `[linux/amd64]` | Platforms covered by the build, each `<os>/<arch>` with the same os/arch vocabulary as `pokerface.yaml`. |
| `builder` | string | no | *(absent)* | Which builder produced the image: `buildkit` or `podman` in v0.1. |

## Unknown fields

While `version` is `1`, unknown fields at the top level and inside an
`images` entry are rejected with the field's path in the error
(`pokerface.lock.yaml: images[0].bogus: unknown field …`).

## Deterministic encoding

`src/lockfile.emo`'s `encode` writes the canonical form, so that
`encode(load(text))` is byte-stable across repeats (and `pokerface build
--write-lock` produces idempotent diffs, T4.4):

- fields always in the order `version, commit, source, generated_at, images`,
  and inside an entry `image, tags, digest, manifest_digest, platforms, builder`;
- `tags` and `platforms` in flow style (`[latest, sha-01234567]`), sorted
  lexically when generated;
- `generated_at` quoted, and — like `manifest_digest` and `builder` — omitted
  entirely when empty.

## Generation (T4.4)

`pokerface build --write-lock` records the pushed image after a successful
build and push:

- the **entry** carries the rendered tags, the pushed digest, the plan's
  platforms, and the builder (`buildkit` for the docker/buildx adapter,
  `podman` for podman) — tags and platforms sorted lexically, the digest
  checked with the loader's own rule;
- the **document's** `commit` is the full SHA the image was built from, and
  `source` is the context repository's origin remote normalized to
  `<host>/<owner>/<repo>` (a repository without an origin is an error — the
  source is required);
- the lock is written **next to pokerface.yaml**; an existing lock is
  **merged**: the entry with the same image name is replaced in place,
  absent entries are appended, every unrelated entry is untouched, and a
  lock that does not parse is an error rather than a silent clobber;
- **no timestamp is written** — `generated_at` stays empty, so the same
  build inputs encode to the same bytes (the digest itself changes per
  build because buildx stamps `created`, but the file's shape never does);
- **no secret-bearing fields exist** — the schema is commit, source, image,
  tags, digests, platforms, builder;
- `--commit` makes the write a **local Git commit** of the lock only
  (`git add -- pokerface.lock.yaml` and
  `git commit -- pokerface.lock.yaml` with the message
  `pokerface: update pokerface.lock.yaml`); it never pushes and commits no
  other staged or modified file. `pokerface resolve` consumes the lock from
  that commit directly.

## Digest verification

**`generated_at` never participates in digest verification.** Consumers
verify images exclusively against the `digest` / `manifest_digest` fields of
the entry they resolved; the file's bytes, its timestamp, and any field other
than the digests are metadata. Two lock files that differ only in
`generated_at` resolve to the same image. `test_generated_at_not_in_digest_verification`
pins this contract.

## Error format

Every failure is a single-line reason:

```text
pokerface.lock.yaml: <path>: <message>
```

`<path>` is the dotted field path with list indexes (`images[0].digest`).
Examples:

```text
pokerface.lock.yaml: commit: must be a full 40-character commit SHA, got 39 characters
pokerface.lock.yaml: images[0].digest: must be 'sha256:' followed by 64 hex characters, got 3
pokerface.lock.yaml: images[0].tags[0]: tag 'UPPER' has invalid character 'U' (rendered tags are lowercase [a-z0-9._-]; placeholders belong in pokerface.yaml)
pokerface.lock.yaml: version: expected 1, got 2 (unknown version)
```
