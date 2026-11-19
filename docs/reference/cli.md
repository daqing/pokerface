# CLI Reference

> The complete command surface (T4.10). The help text is pinned by
> `test/cli.emo`'s snapshot — when that test fails, update this page in the
> same change. Exit codes follow `docs/spec/errors.md`; environment
> variables live in `docs/reference/config.md`.

## Usage

```text
pokerface [global flags] <command> [args]
```

## Commands

| Command | Status | Description |
| --- | --- | --- |
| resolve | implemented | Print the resolution chain of a repository reference (T1.9) |
| pull | implemented | Fetch an image, verify it, and import it into the runtime (T1.14) |
| build | implemented | Build, push, and write the lock from `pokerface.yaml` (T4.1–T4.4) |
| cache | implemented | Inspect and manage the local cache (T1.15) |
| version | implemented | Print the version; `--json` prints `{"name": ..., "version": ...}` |
| config | stub | Reports "not implemented yet" on stderr and exits 1 |

## Global flags

Parsed before the first positional argument; the value form
`--config=<path>` is also accepted.

| Flag | Effect |
| --- | --- |
| `--config <path>` | Configuration file path (see docs/spec/config.md). For `build` this names the **build** file (`pokerface.yaml`) — the two are different files. |
| `--verbose` | Verbose logging: settings summary, redacted HTTP requests, import commands (docs/spec/errors.md) |
| `--json` | Machine-readable output (`version`, `resolve`, `pull`, `build`, `cache ls`/`rm`/`verify`) |
| `-h`, `--help` | Show the help text and exit 0 |

## Exit codes

| Code | Kind | Meaning |
| --- | --- | --- |
| 0 | success | The command completed. |
| 1 | failure | Unclassified failure. |
| 2 | usage | Unknown command/option, missing argument, invalid `--tag`/`--platform`, tag/platform not in the lock, `build` flag misuse. |
| 3 | git | Git ref resolution / mirror operation failed; the build's Git capture. |
| 4 | metadata | Lock, config, offline cache miss, registry 404, or a directory that is not a pokerface cache. |
| 5 | authentication | Registry 401/403 or token-flow failure. |
| 6 | network | Connect/timeout/fetch failure, 5xx, or give-up-after-retries. |
| 7 | integrity | Digest/size mismatch, truncated transfer, corrupt cache entry, unsupported layout version, a served manifest digest that disagrees with the pushed bytes. |
| 8 | runtime | No container runtime, missing skopeo, unreachable daemon, **no build tool** (neither buildx-capable docker nor podman). |

Human errors print one line plus a `hint:` remediation line on stderr. With
`--json`, failures print a single JSON object on stderr (stdout stays
clean). Full model: `docs/spec/errors.md`.

## The `build` command (T4.1–T4.4)

```text
pokerface build [options]

  --dry-run               Print the plan and exit; no build, no network
  --platform <os>/<arch>  Override the configured platforms (repeatable)
  --write-lock            Record the pushed image in pokerface.lock.yaml
  --commit                Commit the generated lock locally (requires --write-lock)
```

`pokerface.yaml` is found via `--config` (which names the **build** file)
or in the current directory. The chain: parse → context check → Git facts
from the context directory (commit, exact tag, branch, newest tag, origin)
→ tag rendering with collision detection → plan → execute → push (when the
config has a `registry` section) → lock.

- `--dry-run` prints `image / tags / platforms / [target] / dockerfile /
  context / [args] / (dry run — no build performed)`; `--json` prints the
  same fields as keys. It performs no build and no network requests.
- The real build streams buildx's log live (docker with buildx first, podman
  fallback — neither answers `runtime: no build tool found`, exit 8), lands
  the image as a validated OCI layout, and pushes it (`docs/spec/push.md`);
  every served manifest digest is verified against the local sha256.
- `--write-lock` merges the entry into `pokerface.lock.yaml` next to
  `pokerface.yaml` (sorted tags/platforms, unrelated entries preserved); it
  requires a registry section — the lock records the pushed digest.
  `--commit` records only the lock file, locally, never pushing.
- A build failure surfaces the original log and the tool's exit code.
- `--json` (real build): `tool`, `layout`, `digests`, `tags`, `platforms`,
  `pushed`, `digest`, plus `lock` / `lock_commit` when written.

Specs: `docs/spec/build-plan.md` (plan + adapter), `docs/spec/push.md`
(push), `docs/spec/pokerface-lock.md` (lock generation).

## The `resolve` command (T1.9)

```console
$ pokerface resolve github.com/acme/app:latest
ref:     github.com/acme/app:latest
commit:  0e05a2ea964dbda0ef105221ed505826c46babf8
image:   registry.example.com/acme/app
digest:  sha256:0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef
tags:    latest, sha-01234567
```

The chain: `ref → commit (git ls-remote) → pokerface.lock.yaml at that
commit (mirror cache) → image → digest`. Git failures never fall back to a
stale cache (a same-commit cache hit is fine and needs no network). A lock
listing several images is an error for now (`--image` lands later).

### Reference syntax

| Form | Example |
| --- | --- |
| Bare | `github.com/acme/app:latest` |
| https | `https://github.com/acme/app.git:v1.2.0` |
| git@ | `git@github.com:acme/app.git:main` |
| Local path | `/tmp/fixtures/origin.git:main` |

The ref defaults to `latest` and separates at the last `:` not followed by
a `/` (an earlier `:` is a host port). `.git` suffixes are stripped; `http://`
and URL credentials are rejected. The ref part resolves like git: `latest`
(default branch), `HEAD`, full/short SHAs, `refs/...` names, branch/tag
names (ambiguous when both match), annotated tags peel to the commit.

## The `pull` command (T1.14)

```text
pokerface pull <repository-reference> [options]

  --platform <os>/<arch>   Platform to pull (must be in the lock); default: the lock's first
  --tag <tag>              Image tag to import (must be in the lock); default: ref name / only tag / latest
  --keep-temp              Keep the assembled OCI layout and print its path
  --offline                Use only the local cache (reference must be a full commit SHA)
```

The chain: `ref → commit → lock → image → manifest → blobs → OCI layout →
runtime import`. Manifest fetch failures fall back to the cached manifest
(digest must match the lock); blobs are content-addressed and verified;
the temp layout is removed after the import (`--keep-temp` keeps it). The
runtime is detected in docker → podman → containerd order and imported via
skopeo. Only the Git host and the lock's registry host (plus redirects) are
contacted — never Docker Hub.

`--json` prints: `image`, `digest`, `commit`, `platform`, `runtime`,
`runtime_ref`, `manifest_cached`, `blobs_downloaded`, `blobs_cached`.

## The `cache` command (T1.15)

```text
pokerface cache ls
pokerface cache verify [--check]
pokerface cache rm [--all | --git | --manifests | --blobs | --refs]
```

`ls` reports per-section counts and sizes; `verify` checks blobs, manifest
envelopes, ref maps, and Git mirrors (`git fsck`) and **repairs by default**
(`--check` only reports, exit 7 while issues remain); `rm` clears the
selected sections (default all) and refuses a directory that is not a
pokerface cache. Limits: `POKERFACE_CACHE_TTL` and
`POKERFACE_CACHE_MAX_SIZE` (docs/reference/config.md), enforced after each
successful pull. Full behavior: `docs/spec/cache.md`.

## The `version` command

`pokerface version` prints `pokerface <version>`; `--json` prints
`{"name": "pokerface", "version": "…"}`.

## The `config` command (stub)

Reports "not implemented yet" on stderr and exits 1 — see `docs/TASKS.md`
for the plan.
