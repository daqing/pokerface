# CLI Reference

> Status: `resolve`, `pull`, `cache`, and `version` are implemented; `build`
> and `config` report "not implemented yet" on stderr and exit 1 until their
> tasks land. The plan lives in `docs/TASKS.md`.

## Usage

```text
pokerface [global flags] <command> [args]
```

## Commands

| Command  | Status          | Description                                                    |
| -------- | --------------- | -------------------------------------------------------------- |
| resolve  | implemented     | Print the resolution chain of a repository reference (T1.9)    |
| pull     | implemented     | Fetch an image, verify it, and import it into the runtime (T1.14) |
| build    | not implemented | Build and push the image described by `pokerface.yaml` (T4.1)  |
| config   | not implemented | Show the effective configuration (T1.8)                        |
| cache    | implemented     | Inspect and manage the local cache (T1.15)                     |
| version  | implemented     | Print the version; `--json` prints `{"name": ..., "version": ...}` |

## Global flags

Flags are parsed before the first positional argument; the value form
`--config=<path>` is also accepted.

| Flag             | Effect                                                     |
| ---------------- | ---------------------------------------------------------- |
| `--config <path>` | Configuration file path (see docs/spec/config.md)          |
| `--verbose`       | Verbose logging: settings summary, redacted HTTP requests, import commands (see docs/spec/errors.md) |
| `--json`          | Machine-readable output (`version`, `resolve`, `pull`, `cache ls`/`rm`/`verify`) |
| `-h`, `--help`    | Show the help text and exit 0                             |

## Exit codes

| Code | Kind | Meaning |
| ---- | --- | --- |
| 0 | success | The command completed. |
| 1 | failure | Unclassified failure, including "not implemented yet". |
| 2 | usage | Unknown command/option, missing argument, invalid `--tag`/`--platform`, tag/platform not in the lock. |
| 3 | git | Git ref resolution / mirror operation failed. |
| 4 | metadata | Lock, config, offline cache miss, registry 404, or a directory that is not a pokerface cache. |
| 5 | authentication | Registry 401/403 or token-flow failure. |
| 6 | network | Connect/timeout/fetch failure, 5xx, or give-up-after-retries. |
| 7 | integrity | Digest/size mismatch, truncated transfer, corrupt cache entry, unsupported layout version. |
| 8 | runtime | No container runtime, missing skopeo, unreachable daemon, or socket permission failure. |

Human errors print one line plus a `hint:` remediation line on stderr. With
`--json`, failures print a single JSON object on stderr (stdout stays clean):

```json
{"error": {"kind": "network", "message": "…", "hint": "…", "exit_code": 6}}
```

Full model: `docs/spec/errors.md`.

## Repository reference syntax

A repository reference names a Git repository and an optional ref (decision
D3). The parser (`src/ref.emo`, task T1.3) accepts three forms:

```text
github.com/acme/app:latest                  # bare form
https://github.com/acme/app.git:v1.2.0      # https:// form
git@github.com:acme/app.git:main            # git@ form
```

- The ref defaults to `latest`. It separates at the last `:` that is not
  followed by a `/`; an earlier `:` is a host port
  (`gitea.example.com:3000/acme/app`).
- The `.git` suffix is stripped from the repo, whatever the input form.
- The normalized result carries `host`, `owner`, `repo`, `git_url`, and
  `ref`; `git_url` is always `https://<host>[:<port>]/<owner>/<repo>.git`.
- `http://` and URL credentials are rejected. Refs containing `/` and path
  shapes other than `<owner>/<repo>` after the host are rejected with an
  error naming the offending field.
- **Local path form (T1.9)**: a reference starting with `/`, `./`, or `../`
  is a filesystem path git uses directly (`/tmp/fixtures/origin.git:main`).
  `host` is the path itself, `owner`/`repo` come from the last two segments,
  and `git_url` stays the raw path — this is what local e2e fixtures run on.

### The `resolve` command (T1.9)

```console
$ pokerface resolve github.com/acme/app:latest
ref:     github.com/acme/app:latest
commit:  0e05a2ea964dbda0ef105221ed505826c46babf8
image:   registry.example.com/acme/app
digest:  sha256:0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef
tags:    latest, sha-01234567
```

`--json` prints the same fields in a stable, script-friendly order:

```json
{"ref": "github.com/acme/app:latest", "commit": "...", "image": "...", "digest": "sha256:...", "manifest_digest": "sha256:...", "tags": ["..."], "platforms": ["..."]}
```

Behavior:

- the chain is `ref → commit (git ls-remote) → pokerface.lock.yaml at that
  commit (mirror cache) → image → digest`;
- exit 0 on success, 2 for a missing/malformed reference argument, 1 for
  git, cache, config, or lock failures — **git failures never fall back to
  a stale cache** (a same-commit cache hit is fine and needs no network);
- `manifest_digest` is served when the lock entry carries one (the selected
  platform's manifest), else the index `digest`;
- a lock listing several images is an error for now (`--image` lands later).

The ref part of a reference resolves to a full commit SHA via
`git ls-remote` (`src/git.emo`):

| Wanted | Resolves to |
| --- | --- |
| `latest` (default) | The repository's **default branch** newest commit (`git ls-remote --symref`) |
| `HEAD` | The advertised HEAD commit |
| 40 lowercase hex chars | Taken as the commit SHA; existence is checked when the commit is fetched (T1.7) |
| 4–39 lowercase hex chars | Short SHA, matched against the advertised refs; ambiguous prefixes are rejected |
| `refs/...` | An exact refname (`refs/tags/v1.2.0`, `refs/heads/main`) |
| anything else | A branch or tag name; a name matching both is rejected as ambiguous, and an annotated tag resolves to its peeled `^{}` commit |

All git subprocesses run with an argv array (never a shell) and enforce a
timeout via a double-fork watchdog.

### The `pull` command (T1.14)

```console
$ pokerface pull github.com/acme/app:latest
image:    127.0.0.1:64401/acme/app:latest
digest:   sha256:b6998b8a881e7dc925961202762d8a0ff7fc339f7d7c03ad6f24087536bc9d0e
commit:   731d22dfb2616d011fd1508ce00e0b689f78dd5b
platform: linux/amd64
runtime:  docker (127.0.0.1:64401/acme/app:latest)
```

```text
pokerface pull <repository-reference> [options]

  --platform <os>/<arch>   Platform to pull (must be in the lock); default: the lock's first
  --tag <tag>              Image tag to import (must be in the lock); default: ref name / only tag / latest
  --keep-temp              Keep the assembled OCI layout and print its path
  --offline                Use only the local cache (reference must be a full commit SHA)
```

The chain is `ref → commit → lock → image → manifest → blobs → OCI layout →
runtime import`. Behavior:

- a Git failure is a hard error and never uses a stale cache;
- a manifest fetch failure falls back to the cached manifest, whose digest
  must match the lock (a warning names the original failure);
- blobs are content-addressed and verified; a cached blob is reused, a
  transient download is retried per blob, and corrupted bytes never reach the
  layout;
- the assembled temp layout is removed after the import, success or failure;
  `--keep-temp` keeps it and prints the path;
- the runtime is detected in docker → podman → containerd order and imported
  with skopeo's local transports (see `docs/spec/runtime-import.md`);
- only the Git host and the registry host from the lock (plus its redirects)
  are contacted — never Docker Hub.

`--json` prints a stable object:

```json
{"image": "registry/acme/app:latest", "digest": "sha256:…", "commit": "…", "platform": "linux/amd64", "runtime": "docker", "runtime_ref": "…", "manifest_cached": false, "blobs_downloaded": 2, "blobs_cached": 0}
```

Exit codes: 0 success; 2 for a missing/malformed reference or an invalid
option value (unknown tag/platform); otherwise the category code from
`docs/spec/errors.md` (Git 3, metadata 4, authentication 5, network 6,
integrity 7, runtime 8).

### The `cache` command (T1.15)

```console
$ pokerface cache ls
cache: /Users/me/.cache/pokerface
  git        1 entries  27.4 KiB
  manifests  1 entries  719 B
  blobs      2 entries  29.3 MiB
  refs       1 entries  41 B
  total      5 entries  29.3 MiB
  limits     ttl=(unset) max_size=(unset)
```

```text
pokerface cache ls
pokerface cache verify [--check]
pokerface cache rm [--all | --git | --manifests | --blobs | --refs]
```

- `ls` reports per-section entry counts and sizes; `--json` gives the same
  data plus the configured limits.
- `verify` checks blobs, manifest envelopes, ref maps, and Git mirrors
  (`git fsck`). It **repairs by default** — corrupt entries and temp debris
  are evicted; `--check` only reports and exits with the integrity code (7)
  while issues remain.
- `rm` clears the selected sections (default: all) and recreates them empty.
  It never removes the cache root, the marker, or anything outside the known
  section directories, and refuses a directory that is not a pokerface cache.
  A missing cache is a no-op.

Limits come from the environment:

| Variable | Example | Effect |
| --- | --- | --- |
| `POKERFACE_CACHE_TTL` | `7d` | Evict entries older than this. |
| `POKERFACE_CACHE_MAX_SIZE` | `2G` | Evict oldest entries until the total fits (1024-based). |

Limits are enforced after each successful pull. Full behavior:
`docs/spec/cache.md`.
