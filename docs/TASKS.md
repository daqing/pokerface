# PokerFace Development Task Plan

> Based on the Architecture, Pull Sequence, and Roadmap in `README.md`.
> Goal: break the plan into 1-3 hour tasks that can be completed and verified independently in spare time.

[简体中文](TASKS.zh-CN.md)

## 1. How to Use This Plan

- Each task maps to a self-contained, mergeable change. As a rule, one commit / one PR per task.
- Branch from `develop` (for example, `feat/t1.3-ref-parser`); do not commit directly to `main`.
- When a task is done, update its progress row here and mark it `[x]`.
- Every acceptance command must be copy-pasteable. At minimum, run `emo build` and the relevant `emo test` suite.
- If a task takes more than 4 hours, it is too coarse. Split it before continuing.
- ID scheme: `T<milestone>.<sequence>`, increasing in dependency order. Append new IDs; never reuse a deleted one.

### Definition of Done (DoD)

- [ ] `emo build` passes with no compilation errors.
- [ ] New behavior has tests, following the existing style under `test/`.
- [ ] CLI, configuration, or protocol changes come with updates to `docs/` or the spec named by the task.
- [ ] No dependency is added without being pinned in `package.emo`.
- [ ] Tokens, keys, and real user data never appear in the repository, logs, or test fixtures.
- [ ] The task's status and notes (actual time, gotchas, follow-ups) are updated.

## 2. Scope and Milestones

This plan covers M1, M2, and M4 only. M3 is out of scope and is intentionally left unspecified. To make `M1 + M2 + M4` a complete end-to-end path, roadmap item 5 (runtime import) is folded into M1 and item 6 (build triggers / CI) into M4.

| Milestone | Theme | README roadmap items | Exit criteria | Rough estimate |
| --- | --- | --- | --- | --- |
| M1 | Client loop: resolve + pull + import | 1, 2, 5 | `pokerface resolve` and `pokerface pull` work against a local registry, and the imported image runs with `docker run` | ~35-40h |
| M2 | Distribution MVP: registry + object storage | 3, 4 | A single `docker compose up` brings up the service; manifests and blobs can be pushed / pulled; blobs are served via presigned CDN URLs | ~45-55h |
| M4 | Build, CI, and delivery | 6, 7 | The example repository builds and pushes with `pokerface build`; CI templates are usable; the docs site and end-to-end script are complete | ~40-50h |

Budget 4-6 hours per week. At these estimates, the MVP takes roughly 5-7 months of spare-time work. Leave 30-50% slack for research and rework.

## 3. Interface Decisions to Lock Down First

These decisions affect multiple tasks. Settle them early in M1; record any later change as an ADR.

| ID | Decision | Default | Implemented by |
| --- | --- | --- | --- |
| D1 | Language and runtime | Emo, `c` target; prefer the standard library `http`, `httpd`, `yaml`, `json`, `sqlite3`, `crypto`, `os`, and `slog` | T1.2, T2.1 |
| D2 | Build metadata files | Commit `pokerface.yaml` and the CI-generated `pokerface.lock.yaml` at the repository root | T1.4, T1.5 |
| D3 | Repository reference syntax | `<host>/<owner>/<repo>[:<tag>]`, defaulting to `latest`; also accept `https://` and `git@` forms | T1.3 |
| D4 | Blob access | The registry stores manifests; blob GET returns 307 with a presigned S3/MinIO URL; the client verifies the digest after download | T2.9, T1.11 |
| D5 | Runtime import | Assemble a local OCI layout, then call `skopeo` to import into `docker-daemon` / `containers-storage`; fail clearly when skopeo is missing | T1.13 |
| D6 | Authentication | Bearer tokens with `pull` / `push` scopes; v0.1 signs tokens for pre-shared accounts from the config file; no OAuth | T2.14, T1.10 |
| D7 | Build trigger | v0.1 is CI-driven (push / tag / workflow_dispatch); no self-hosted webhook service | T4.5, T4.6 |
| D8 | Metadata storage | SQLite for repositories, manifests, tags, and upload sessions; blobs in S3/MinIO; filesystem backend for local development | T2.2, T2.6 |
| D9 | Compatibility target | Implement the necessary subset of the OCI Distribution Spec and smoke-test with `oras` / `skopeo`; full Docker client compatibility is not promised | T2.19 |
| D10 | Documentation | Start with a Markdown static site on GitHub Pages; add VitePress only when search is needed | T4.8 |

## 4. M1: Client Loop

### 4.1 Goal and Exit Criteria

Turn the first half of the README Pull Sequence into a usable CLI: parse repository references, resolve `tag -> commit -> digest`, fetch manifests and blobs, verify them, and import into the local runtime.

Exit criteria:

- `pokerface resolve github.com/acme/app:latest` prints the full resolution chain.
- `pokerface pull` fetches from a local test registry and imports into Docker / podman.
- Git resolution failures, manifest failures, blob verification failures, and import failures each have defined behavior and exit codes.
- No request ever reaches `registry-1.docker.io`.
- `emo test` passes and `scripts/e2e-m1.sh` runs in a clean environment.

### 4.2 Task Overview

| Status | ID | Task | Depends on | Estimate |
| --- | --- | --- | --- | --- |
| [x] | T1.1 | CLI skeleton and command routing | none | 1-2h |
| [x] | T1.2 | Verify Emo runtime capabilities and pin dependencies | T1.1 | 2h |
| [x] | T1.3 | Parse repository references | T1.1 | 1-2h |
| [x] | T1.4 | `pokerface.yaml` v0.1 spec and parser | T1.2 | 2-3h |
| [x] | T1.5 | `pokerface.lock.yaml` v0.1 spec and parser | T1.2 | 2h |
| [x] | T1.6 | Git ref resolution: tag / branch / commit | T1.3 | 2-3h |
| [x] | T1.7 | Read Git metadata and cache repository mirrors | T1.6, T1.5 | 3h |
| [x] | T1.8 | Configuration, credentials, and XDG paths | T1.1 | 2h |
| [x] | T1.9 | Wire up the `resolve` command | T1.4-T1.8 | 2h |
| [x] | T1.10 | Registry authentication and manifest client | T1.5, T1.8 | 3h |
| [x] | T1.11 | Blob downloader: retries, verification, resume | T1.10 | 3-4h |
| [x] | T1.12 | Assemble an OCI image layout | T1.10, T1.11 | 2-3h |
| [x] | T1.13 | Runtime import adapter | T1.12 | 3h |
| [x] | T1.14 | Wire up the `pull` command and failure fallbacks | T1.9-T1.13 | 3h |
| [x] | T1.15 | Local cache and offline mode | T1.7, T1.14 | 2-3h |
| [x] | T1.16 | Error model, exit codes, and logging | T1.1 | 2h |
| [x] | T1.17 | M1 test baseline, E2E script, and spec docs | T1.1-T1.16 | 2-3h |

### 4.3 Task Details

#### T1.1 CLI Skeleton and Command Routing

**Goal**: Create a buildable, runnable CLI with `resolve`, `pull`, `build`, `config`, `cache`, and `version` subcommands plus the global flags `--config`, `--verbose`, and `--json`.

**Deliverables**: `main.emo`, `src/cli.emo`, help text, and exit-code constants. Unimplemented subcommands return an explicit "not implemented" error instead of crashing.

**Acceptance**: `emo build` passes; `pokerface --help` and `pokerface version` work; an unknown command exits with code 2; `emo test` still passes.

**Depends on**: none · **Estimate**: 1-2h

> **Notes** (2026-11-17, ~1h): Done. `main.emo` is a thin entry point (`src.cli.route(os.argv())` + `os._exit`); `src/cli.emo` holds routing, help text, a `Flags` class, and the exit-code constants (0 ok / 1 failure / 2 usage). Unimplemented commands print "not implemented yet" to stderr and exit 1; `version` supports `--json`; no-args and unknown command/option exit 2. Gotchas: local modules are addressed by path (`src.cli`, not `cli`), and parsed-but-unused locals surface as C-level `-Wunused-but-set-variable` warnings, so parsed flags flow into handlers through `Flags`. Follow-ups: T1.8 reads `Flags.config`, T1.16 wires verbose logging and the full exit-code table, T4.10 turns `docs/cli.md` into the full reference.

#### T1.2 Verify Emo Runtime Capabilities and Pin Dependencies

**Goal**: Verify the standard-library capabilities the rest of the implementation relies on: YAML / JSON codecs, HTTPS requests, subprocesses, SHA-256, files, and temporary directories. Pay special attention to the `http` client's limits: it does not follow redirects and reads the entire response body into memory.

**Deliverables**: `test/capabilities.emo` (or an executable spike under `spike/`), dependency declarations in `package.emo`, `package.lock`, and `docs/notes/runtime-capabilities.md`.

**Acceptance**: `emo build` and `emo test` pass; the spike completes an HTTPS GET, a `git --version` subprocess, and a SHA-256 hash; the notes record a plan for large downloads and redirects (use `net` for streaming in T1.11 if necessary).

**Depends on**: T1.1 · **Estimate**: 2h

> **Notes** (2026-11-17, ~1.5h): Done. All targeted capabilities verified — SHA-256 (RFC vector), subprocess fork/execvp/waitpid with pipe capture, HTTPS GET, YAML/JSON codecs, file IO, temp directories; `emo test` 25/25. Key finding: `http` indeed never follows redirects (301 returned as-is) and buffers whole bodies — T1.10 keeps `http` for manifests/tokens, T1.11 streams blobs through `net` with manual 307 handling. Gotcha with downstream impact: a bare `.` YAML scalar decodes as `YamlFloat` (encode renders `0.0`), which hits `pokerface.yaml`'s `context: .` — T1.4 must quote it or reject float contexts. Full details in `docs/notes/runtime-capabilities.md`.

#### T1.3 Parse Repository References

**Goal**: Parse user input into a structured reference: Git URL, repository identity, tag / branch / commit, and a default `latest`. Support `github.com/acme/app:latest`, `https://github.com/acme/app.git:v1.2.0`, and `git@github.com:acme/app.git:main`.

**Deliverables**: `src/ref.emo` and table-driven tests. The normalized output must include at least `host`, `owner`, `repo`, `git_url`, and `ref`.

**Acceptance**: Cover valid and invalid inputs, `.git` suffixes, ports, and the default tag. Make no network calls. Error messages identify the offending field.

**Depends on**: T1.1 · **Estimate**: 1-2h

> **Notes** (2026-11-18, ~1h): Done. `src/ref.emo` parses all three D3 forms with zero requires; the ref separates at the last `:` not followed by `/`, so `host:port` and `:ref` coexist, and `git_url` always normalizes to `https://<host>[:<port>]/<owner>/<repo>.git`. 12 valid + 23 invalid table cases (35 total) in `test/ref.emo`; the invalid table asserts the error names the offending field. Gotchas: a class may not share its module's name case-insensitively — `class Ref` inside `src/ref.emo` made the bare `Ref` in the signature resolve differently from `Ref.new`, so the class is `Reference`; arrays take no trailing comma. Follow-ups: full git refname rules (leading `.`, `.lock`, `@{`) move to T1.6; subgroup paths (`gitlab.com/g/s/p`) are rejected by design in v0.1.

#### T1.4 `pokerface.yaml` v0.1 Spec and Parser

**Goal**: Define the build configuration stored in the application repository: image name, build context, Dockerfile, target, platforms, build args, tag rules, and registry address. Suggested shape:

```yaml
version: 1
image: registry.example.com/acme/app
build:
  context: .
  dockerfile: Dockerfile
  target: runtime
  platforms: [linux/amd64]
  args:
    NODE_ENV: production
tags:
  - latest
  - "{{ commit.short }}"
registry:
  url: https://registry.example.com
```

Tag rules must support at least the `latest`, `{{ commit.short }}`, `{{ git.tag }}`, `{{ branch }}`, and `{{ version }}` placeholders.

**Deliverables**: `docs/spec/pokerface-yaml.md`, `src/config.emo`, `examples/pokerface.yaml`, and parser / validation tests.

**Acceptance**: The example parses; missing `version`, `image`, or `build.context` produces path-aware errors; invalid platform names, duplicate tags, and unterminated placeholders are rejected; the spec includes a complete field table.

**Depends on**: T1.2 · **Estimate**: 2-3h

> **Notes** (2026-11-18, ~2h): Done. `src/config.emo` parses and validates the full v0.1 surface with path-aware errors (`pokerface.yaml: build.context: …`); unknown fields are rejected while version is 1; tags accept literals plus `{{ commit.short }}`/`{{ git.tag }}`/`{{ branch }}`/`{{ version }}` templates. The T1.2 gotcha was confirmed in practice: a bare `context: .` decodes as `YamlFloat` and is rejected with a quote hint, so `examples/pokerface.yaml` uses `context: "."`. 25 test cases (example file, minimal defaults, 7 valid variants, 25-row invalid table); `emo test` 32/32. Gotchas: `is()` narrowing only covers the `if` branch, so every parser is shaped as `if value.is(…) { …body… } return error`; `substring(start, len)` raises past the end — guard two-char windows with `i + 2 <= len`. Follow-ups: template rendering lands in T4.1; platform sets may widen with real build support.

#### T1.5 `pokerface.lock.yaml` v0.1 Spec and Parser

**Goal**: Define the metadata that CI writes back to Git so the pull side can obtain the image digest from Git alone. Suggested shape:

```yaml
version: 1
commit: 0123456789abcdef0123456789abcdef01234567
source: github.com/acme/app
generated_at: "2026-11-17T12:00:00Z"
images:
  - image: registry.example.com/acme/app
    tags: [latest, sha-01234567]
    digest: sha256:...            # top-level index or single-platform manifest
    manifest_digest: sha256:...   # selected platform manifest
    platforms: [linux/amd64]
    builder: buildkit
```

**Deliverables**: `docs/spec/pokerface-lock.md`, `src/lockfile.emo`, an example file, and parser / encoder tests.

**Acceptance**: Parse and re-encode deterministically (stable field order); `commit` must be a full SHA; validate digest format; reject duplicate tags; reject an unknown `version`; `generated_at` never participates in digest verification.

**Depends on**: T1.2 · **Estimate**: 2h

> **Notes** (2026-11-18, ~2h): Done. `src/lockfile.emo` parses and encodes the full v0.1 lock; `source` reuses `src.ref.parse` and normalizes to the bare `host/owner/repo` shape (a ref in the source is rejected); lock tags are rendered-only — `{{ placeholder }}` syntax is rejected with a pointer back to `pokerface.yaml`. The encoder emits a fixed field order and omits empty optionals, so `encode(load(text))` is byte-stable; `generated_at` is metadata only and two locks differing just there resolve to the same digest (pinned by a test). Image/platform validation is shared with T1.4 via new plain-message `config.check_image`/`check_platform`. 7 tests over ~40 cases; `emo test` 39/39. Gotcha repeat: concrete-class methods (`entries`) need the narrowed receiver, so `parse_image_entry` splits into an `is()` gate plus an inner `parse_image_object(value yaml.YamlObject, …)` taking the concrete type.

#### T1.6 Git Ref Resolution: Tag / Branch / Commit

**Goal**: Resolve a tag / branch / short SHA / full SHA to a commit SHA via `git ls-remote`. Handle annotated tags' `^{}` refs and detect the default branch.

**Deliverables**: `src/git.emo`, an injectable command runner for tests, and temporary Git repository fixtures.

**Acceptance**: Tests cover lightweight tags, annotated tags, branches, HEAD, full SHA, and short SHA; missing refs return a clear error; subprocesses have timeouts; arguments are passed as an array, never through a shell.

**Depends on**: T1.3 · **Estimate**: 2-3h

> **Notes** (2026-11-18, ~2.5h): Done. `src/git.emo` exposes `resolve(runner, git_url, wanted, timeout)` behind the injectable `CommandRunner` interface; wanted semantics are pinned in docs/cli.md — `latest` resolves the default branch HEAD (one `--symref` call), annotated tags peel to `^{}`, branch/tag name collisions are ambiguous errors, `refs/...` is the escape hatch, full SHAs pass through (existence checked at fetch time in T1.7). Big finding: **`os.waitpid` stalls the whole scheduler** — a `time.after` watchdog never fires while the parent waits, so `RealRunner` uses a double-fork watchdog (child forks a grandchild that sleeps the deadline and kills the child; parent blocks freely). Verified live: 0.3s timeout kills a 2s sleep at ~0.30s; fast commands pay no latency. Tests: 14 total — fixture repos (lightweight/annotated tags, branch, HEAD, full+short SHA, missing, ambiguous, latest) built via git subprocesses under TMPDIR (left for the OS cleaner), plus FakeRunner logic tests. Gotcha found by test: an early `return HEAD` inside the ls-remote loop matched for *every* wanted — condition must be `wanted == "HEAD" && name == "HEAD"`.

#### T1.7 Read Git Metadata and Cache Repository Mirrors

**Goal**: Maintain bare mirrors under `~/.cache/pokerface/git/<hash>`, fetch the requested ref / commit on demand, and read metadata with `git show <sha>:pokerface.lock.yaml`. If the server does not advertise a commit, fetch the corresponding ref first and then read the commit.

**Deliverables**: `src/git_cache.emo`, a cache layout description, and tests for the first fetch, offline reads, and concurrent fetches.

**Acceptance**: After the first read, the same commit's lock is readable offline; missing repositories, missing files, and invalid YAML each produce distinct errors; concurrent runs do not corrupt the cache; the user's working tree is never modified.

**Depends on**: T1.6, T1.5 · **Estimate**: 3h

> **Notes** (2026-11-18, ~2.5h): Done. `src/git_cache.emo` keeps one bare mirror per URL under `<cache_root>/git/<sha256-prefix>` with a `source-url` marker; reads go `git show <commit>:pokerface.lock.yaml` with a fetch-then-retry on miss. The offline guarantee is structural: the show fast path never runs a fetch (RecordingRunner asserts no fetch in the added log). Ref hints route fetches: full SHA → raw-SHA fetch (error mentions `uploadpack.allowAnySHA1InWant` when it fails — local transports allow it), `refs/...` → exact ref, name → branch refspec then tag refspec, unknown → all heads+tags. RealRunner now captures stderr too, so `git show`'s "does not exist" text is classifiable. Concurrency needed two bounded retries: racing `git init --bare` loses a mkdir race (re-check HEAD each round) and concurrent fetches collide on lock files (retry on "File exists"). Tests: 10, including a real forked-process race on one fresh cache and a worktree snapshot; `emo test` 63/63. Layout doc: docs/notes/git-cache-layout.md.

#### T1.8 Configuration, Credentials, and XDG Paths

**Goal**: Establish configuration precedence and credential handling. Path priority: `--config` > `POKERFACE_CONFIG` > `$XDG_CONFIG_HOME/pokerface/config.yaml` > `~/.config/pokerface/config.yaml`. Environment variables override file values.

**Deliverables**: `src/settings.emo`, `docs/spec/config.md`, precedence tests, and log-redaction tests.

**Acceptance**: CLI flags > environment > config file > defaults; tokens never appear in `--verbose` logs; warn when the config file is group- or world-readable; `POKERFACE_CACHE_DIR` overrides the cache directory.

**Depends on**: T1.1 · **Estimate**: 2h

> **Notes** (2026-11-18, ~2h): Done. `src/settings.emo` resolves the config path (`--config` > `POKERFACE_CONFIG` > XDG > `~/.config`, explicit paths must exist) and applies `POKERFACE_REGISTRY_URL` / `POKERFACE_REGISTRY_TOKEN` / `POKERFACE_CACHE_DIR` overrides over file values. Env access is behind an injectable `EnvSource` (RealEnv/FakeEnv) so tests never mutate the process environment — os.setenv would leak across tests since they share one process. Permission check runs `stat` through the runner (BSD vs GNU picked via `uname`); group/other read bits produce a warning, a failed stat is silent. `redact()` renders `<redacted:<len>>` and `summary()` is the verbose dump — token never escapes. 14 tests; `emo test` 79/79. Gotchas: a class cannot be named `Settings` (module `settings` collision, T1.3's rule again) so it is `AppSettings`; `os.mkdir` does not create parents — fixtures mkdir level by level.

#### T1.9 Wire Up the `resolve` Command

**Goal**: Connect reference parsing, Git commit resolution, and lock reading; print `ref -> commit -> image -> digest`. Support `--json`, `--platform`, and `--verbose`.

**Deliverables**: `src/commands/resolve.emo`, tests, and a `resolve` example in `docs/cli.md`.

**Acceptance**: Output is stable for fixture repositories; `--json` fields are stable and script-friendly; a missing image or platform in the lock exits non-zero; Git failures do not fall back to stale caches.

**Depends on**: T1.4-T1.8 · **Estimate**: 2h

> **Notes** (2026-11-18, ~2.5h): Done. `src/commands/resolve.emo` chains ref → commit → lock → image → digest with `--json` (stable field order) and human output; a multi-image lock is a clear error, missing refs/lock/config each exit 1 with the reason, and git failures never fall back to a stale cache (the same-commit cache hit stays offline-friendly). Two structural changes: (1) the resolve→cli reference was a module cycle, so Flags/eprint/exit codes moved to a new `src/common.emo` — command handlers depend on common, never on the router; (2) refs gained a local-path form (`/…`, `./…`, `../…` → git_url stays the raw path) because local e2e fixtures are a hard requirement for T1.17's offline script. Two loader pitfalls cost real time: a test file mirroring its subject's path (test/commands/resolve.emo) trips E5003, and so does any top-level `const X = src.<mod>.new(...)` — cross-module construction must happen inside defs (test/resolve_cmd.emo documents both). Also fixed en route: lockfile.encode now quotes `commit:` so an all-digit SHA survives round-trip. Verified end to end against a local bare origin with the real binary (human + json + not-found paths); `emo test` 90/90.

#### T1.10 Registry Authentication and Manifest Client

**Goal**: Implement the OCI registry client basics: probe `GET /v2/`, parse `WWW-Authenticate`, obtain a Bearer token, fetch manifests by tag / digest, handle an OCI Index and select a child manifest by platform, and verify `Docker-Content-Digest`.

**Deliverables**: `src/registry.emo`, mock registry tests, and a list of supported media types.

**Acceptance**: 401 -> fetch token -> retry succeeds; 404 / 5xx / timeouts produce clear errors; a multi-arch index can select the target platform; manifest bytes match the digest; all requests go only to the configured registry host; redirects are not followed automatically.

**Depends on**: T1.5, T1.8 · **Estimate**: 3h

> **Notes** (2026-11-18, ~2.5h): Done. `src/registry.emo` implements the full acceptance set against an injectable `Transport` (HttpTransport real, MockTransport offline): probe → 401 → `WWW-Authenticate` Bearer parse (realm/service/scope, percent-encoded) → token fetch → verify probe; manifest fetch by tag/digest with constant-time `Docker-Content-Digest` verification (mismatch names both digests); 401-dance-and-retry-once whose retry **rebuilds headers** (first version reused the pre-dance header array and silently re-sent no token — mock caught it); index platform selection listing available platforms on a miss; 3xx is a hard error naming the Location; every mock call asserted to stay on the registry or auth host. Media-type table lives in docs/spec/registry-client.md. Gotchas: client token mutability needs a `Box` (class fields freeze after init); Json.get raises on missing keys and Emo has no catch, so all optional members go through a scanning `json_member` helper; reverse `if !x.is(...)` guards do not narrow — positive-branch structure only; type paths in test signatures cannot use const aliases (`reg.Client` fails, `src.registry.Client` works).

#### T1.11 Blob Downloader: Retries, Verification, Resume

**Goal**: Download config and layers from the manifest descriptors with a concurrency cap, exponential backoff, Range-based resume, SHA-256 and size verification, and temp-file cleanup.

**Deliverables**: `src/blob.emo`, mock CDN tests, and progress output.

**Acceptance**: Retries recover from simulated 500s, timeouts, and interruptions; corrupted blobs are rejected and never enter the OCI layout; fall back to a full download when the server does not support Range; temp files are cleaned up on failure; large layers do not cause unacceptable memory use (if `http` cannot meet this, switch to a streaming `net` implementation in this task and record the decision).

**Depends on**: T1.10 · **Estimate**: 3-4h

> **Notes** (2026-11-18, ~3h): Done. **The recorded T1.2 decision is now executed: blobs stream through `net`** — `HttpBlobTransport` speaks HTTP/1.1 by hand (TLS or plain per scheme, Connection: close, Content-Length and chunked bodies, close-delimited rejected as the documented narrow case), so a large layer never sits in one String. Presigned redirects are followed up to 3 hops (the D4 mechanism; absolute Locations, as real CDNs issue). Retry/resume: `.part` + `.meta` offset sidecar, Range resume, automatic fallback to a full download when the server answers 200 to a Range request, exponential backoff with the retry count and base delay as parameters, 4xx classified permanent (no retry), incremental SHA-256 via `crypto.sha2.new()` Digest + size check, and `os.rename` commit — corrupted bytes never reach the layout, temp files cleaned on every failure path. **Concurrency cap deferred**: Emo's Boxes snapshot across processes so a shared semaphore needs a message-passing token process; the sequential `download_all_blobs` keeps memory bounded and ordering deterministic, and the parallel form is recorded as a follow-up (candidates: T1.14 wiring or a dedicated task). Tests: 15 — mock failure injection (open failures, mid-stream drops with exact resume offsets, Range fallback, 403 no-retry, corruption, size mismatch, cleanup) plus a REAL local httpd server leg (full download, 206 resume, 307 absolute redirect) over the live net stack; `emo test` 122/122. Gotchas: `TcpConn` is a bare builtin type (no `net.TcpConn` path); a `var` initialized from a tuple literal pins that tuple's type — initialize `var conn_result = net.connect(...)` not `(R.error, "...")`; one-line `if` expressions cannot nest inside binary operators (bind to a const first); `while true` loops need an unreachable trailing `return` to satisfy E4017.

#### T1.12 Assemble an OCI Image Layout

**Goal**: Write manifests, config, and layers into a standard OCI layout: `oci-layout`, `index.json`, and `blobs/sha256/<hex>`; add a tag annotation to `index.json`.

**Deliverables**: `src/oci.emo`, fixture manifests, and layout validation tests.

**Acceptance**: `skopeo inspect oci:<dir>` can read the layout (when skopeo is installed); every descriptor's digest / size matches the actual file; missing blobs produce a clear error; `--keep` preserves the temp directory.

**Depends on**: T1.10, T1.11 · **Estimate**: 2-3h

> **Notes** (2026-11-18, ~2h): Done. `src/oci.emo` turns downloaded manifest/config/layer bytes into `oci-layout`, `index.json` (with the `org.opencontainers.image.ref.name` tag annotation), and `blobs/sha256/<hex>`. Assembly is verify-first: the manifest bytes are checked against the advertised digest, every config/layer descriptor is paired with a `BlobSource` before anything is written (a missing source, a declared-size disagreement, or an unreferenced extra is a clear error), copies hash and count while streaming into `<dest>.part` and rename only after digest+size match, and `index.json` is written last — so an on-disk layout never references a corrupted or absent blob. Identical existing blobs are reused, making re-assembly idempotent. `validate(dir)` re-derives everything from disk (layout version, index descriptors, manifest config/layers, nested indexes) and reports unique blob/byte counts; missing, corrupted, and size-mismatched blobs each name the descriptor that referenced them. `new_temp_layout(keep)` + `TempLayout.cleanup()` provide the `--keep` behavior T1.14 wires to its option; a kept directory can therefore be inspected after a failed import. Fixtures: `test/fixtures/oci/` is a genuinely valid single-layer image (gzipped tar + config with the matching `diff_ids`), so `skopeo inspect oci:<dir>:latest` reads it and returns the manifest digest — verified manually against skopeo 1.25. Tests: 15 in `test/oci_layout.emo` (parse errors, assemble/validate, idempotency, bad manifest digest, missing/corrupt/unreferenced sources, validate catching missing/corrupt blobs and bad layout versions, temp keep/cleanup, and the skopeo leg that skips on exit 127). Docs: `docs/spec/oci-layout.md`. Gotchas: `;` is not a statement separator in Emo (`E2025`) — split statements onto lines; `json.object`/`json.array` factories take explicit tuple/array literals; `file.read` is byte-safe, so the gzip fixture round-trips as a String; `src.blob.digest_hex` is reused for digest-shape validation.

#### T1.13 Runtime Import Adapter

**Goal**: Import the OCI layout into the local runtime. Prefer `skopeo copy oci:<dir> docker-daemon:<image>:<tag>`; use `containers-storage:` for podman and `oci-archive` + `ctr images import` for containerd. Detect available tools and provide clear guidance.

**Deliverables**: `src/runtime.emo`, a support matrix, and tests for command construction and error mapping.

**Acceptance**: The Docker + skopeo path works; the podman path works; Docker without skopeo produces a clear installation hint; failed imports leave no partial image; temp files are cleaned up.

**Depends on**: T1.12 · **Estimate**: 3h

> **Notes** (2026-11-18, ~2.5h): Done. `src/runtime.emo` splits detection, planning, and execution so commands are constructible and testable without a runtime: `detect` probes `docker/podman/skopeo/ctr --version`; `select_runtime` honors an explicit choice (`ctr` as an alias for containerd) or prefers docker > podman > containerd; `plan` emits exact argv. Docker uses `skopeo copy oci:<dir>:<tag> docker-daemon:<image>:<tag>`, podman `containers-storage:<image>:<tag>`, and containerd creates `<layout>.oci-archive.tar` with skopeo then `ctr images import --base-name <image> <archive>` (a full ref cannot ride in the archive's `ref.name`: skopeo splits `oci-archive:path:tag` at the last colon). Every path requires skopeo and fails planning with a brew/apt/dnf installation hint when it is absent. `execute` records whether the tag pre-existed, runs the steps, verifies with `docker/podman image inspect` or an exact-line `ctr images ls --quiet` scan, and on failure removes the archive and — only when the tag did not exist before — the partially imported tag, so a pre-existing image is never touched. Errors are mapped from runner output (exit 127, daemon unreachable, permission denied) with the shared runner's `git:` prefix stripped. Tests: 20 in `test/runtime_import.emo` (detection, all three plans, auto/explicit selection, no-runtime/unknown/not-installed, the skopeo hint, bad requests, Docker success and failure paths including verification failure and pre-existing image preservation, permission/127 mapping, containerd archive cleanup on success/failure, keep, and prepare). **Manually verified end to end** with the real Docker daemon (29.9.3) and skopeo 1.25.2: the fixture layout imported as `pokerface-t113-check:latest`, `docker image inspect` succeeded, and the test image was removed afterwards. Podman and `ctr` are not installed on this machine, so those two paths are covered by command-construction/error-mapping tests only. Docs: `docs/spec/runtime-import.md` (support matrix). Gotchas: the runner's error text is `git: '<tool>' exited …` even for non-git tools; FakeRunner route tables are ordered, so a repeated probe (inspect before/after import) is expressed as the same prefix with `times` counts; no `stat` in `os`, so archive existence in tests is read through `file.read`.

#### T1.14 Wire Up the `pull` Command and Failure Fallbacks

**Goal**: Chain `resolve -> manifest -> blob -> verify -> OCI layout -> runtime import`. Implement the README fallbacks: a Git failure is a hard error; a manifest failure falls back to the local cache; a CDN failure retries per blob; an import failure cleans up temp files.

**Deliverables**: `src/commands/pull.emo`, integration tests against a local registry, and `--platform` / `--tag` / `--keep-temp` / `--offline` options.

**Acceptance**: An end-to-end pull followed by `docker run` succeeds; a manifest fetch failure can still complete from cache (the cached digest must match); a corrupted blob is never imported; an import failure leaves no temp directory behind; packet captures or proxy logs show no Docker Hub requests.

**Depends on**: T1.9-T1.13 · **Estimate**: 3h

> **Notes** (2026-11-18, ~3h): Done. `src/commands/pull.emo` chains Git resolution → manifest → blobs → OCI layout → runtime import, with the README fallbacks. **Manifest**: fetch by the lock's `manifest_digest` for the pinned platform (the first lock platform), otherwise by the lock's `digest` and let T1.10 select the platform from the index; every fetch verifies that the body hashes to the requested digest and that the final manifest matches the lock. A network/5xx failure falls back to a per-`(image, reference, platform)` manifest cache, re-verifying the cached digest against the lock and warning with the original error. **Blobs**: content-addressed cache under `<cache_root>/blobs/sha256`, verified on every use; T1.11 retries, Range resume, and digest checks apply; an online pull re-downloads a corrupted cache entry, offline reports it. **Auth**: the new `src.blob.RegistryBlobTransport` sends the Bearer token on the first hop only, so a 307 to a presigned CDN URL never receives it. **Cleanup**: the temp layout (T1.12) is removed on success and every failure; T1.13 removes its archive and a partially imported tag; `--keep-temp` keeps the layout (and archive) and prints/attaches the path. **Offline** (`--offline`) requires a full commit SHA and reads the lock with a plain `git show` from the mirror (never a fetch), plus cached manifests/blobs only. `run_with` injects the runtime runner for tests; `run` uses the real one. Options: `--platform`, `--tag`, `--keep-temp`, `--offline`; `--json` emits image/digest/commit/platform/runtime/runtime_ref/manifest_cached/blob counts. Docs: `docs/spec/pull.md`, `docs/cli.md`. Tests: 15 in `test/pull_cmd.emo` — full pipeline over a real local httpd registry (token-checked manifests/blobs, 307 to a CDN endpoint that rejects Authorization, digest headers), manifest-failure cache fallback, offline warm/cold cache, corrupted-cache repair online and rejection offline, import failure with and without `--keep-temp`, index platform selection and miss, tag/platform/arg/image-split helpers, and the full command against a local Git repo + fake runtime; `emo test` 174/174. A first run of the full-command test failed because it supplied the registry token only to `pull_image`'s deps, while `run_with` reads it from settings — the fake env now sets `POKERFACE_REGISTRY_TOKEN`. **Manually verified end to end**: built a runnable linux/arm64 image (`ubuntu:24.04` + `/bin/echo`), exported it to an OCI layout with skopeo, served it from a local Go registry fixture (307 blob redirects), ran the real `pull.run_with` with the real Docker/skopeo runtime — the 30,797,821-byte layer downloaded, verified, assembled, and imported — then `docker run` printed `pokerface pull ok`; a second pull through the real CLI with `--offline` and the full commit SHA (registry stopped) reused the Git mirror, cached manifest, and cached blobs and re-imported successfully; all test images were removed afterwards. Gotchas: the Emo `httpd` fixture cannot carry NUL bytes, so the integration layer body is ASCII-only (real gzip layers are covered by the manual E2E); the stdlib `http` client does reach an in-process `httpd` server; the offline Git path must not call `git_cache.load_lock` (it would fetch), hence `load_lock_offline`; `--keep-temp` sets both T1.12's layout keep and T1.13's archive keep.

#### T1.15 Local Cache and Offline Mode

**Goal**: Manage the Git mirror, manifest, and blob caches in one place; add TTL, size limits, cleanup, and verification commands; support `--offline` to use only the cache.

**Deliverables**: `src/cache.emo`, `pokerface cache ls` / `cache rm` / `cache verify`, and cache tests.

**Acceptance**: A second pull works offline; corrupted cache entries are detected and evicted; the size limit is enforced; `cache rm` never deletes non-pokerface directories; concurrent reads and writes are safe.

**Depends on**: T1.7, T1.14 · **Estimate**: 2-3h

> **Notes** (2026-11-18, ~3h): Done. `src/cache.emo` owns the whole cache: Git mirrors, manifest envelopes, content-addressed blobs, and a ref → commit map; `src/commands/cache.emo` implements `cache ls` / `rm` / `verify`. **Safety**: a `.pokerface-cache` marker names the root; `ensure_root` adopts an empty/known-only directory (the T1.14 layout) or writes the marker, and refuses anything else, so `cache rm` cannot touch an unrelated directory. Destructive operations serialize on a `<root>/.lock` directory and never follow symlinks (removals decide by the stat-reported kind). **Manifests** are one JSON envelope (body + metadata) written atomically with a per-process `.part` name, so concurrent writers never pair one body with another's metadata; the old two-file format is adopted and its leftovers are evictable debris. **Refs** are `<sha256(git_url\nref)> -> commit`, written by every online resolution (the cache layout is ensured first) and read by `--offline`, so a branch/tag pull works offline without a full SHA. **Limits**: `POKERFACE_CACHE_TTL` (seconds or `<n>s/m/h/d`) and `POKERFACE_CACHE_MAX_SIZE` (bytes or `<n>K/M/G/T`, 1024-based) are parsed in settings and enforced after each successful pull, best effort; TTL expires old entries, then the size cap evicts oldest-first. **Commands**: `cache ls` (human/JSON), `cache verify [--check]` (repairs by default, checks blob hashes, manifest envelopes, ref maps, and `git fsck` on mirrors; exits 1 while issues remain), and `cache rm [--all|--git|--manifests|--blobs|--refs]` (clears the selected sections, keeps the root/marker, a missing root is a no-op). Tests: 20 in `test/cache_cmd.emo`, 3 cache-limit cases in `test/settings.emo`, 2 cache routing cases in `test/cli.emo`, and the T1.14 full-command pull test now also pulls the same ref offline; `emo test` 199/199. **Manually verified** against a real cache populated by a real pull through the Docker/skopeo path: `cache ls` showed git/manifests/blobs/refs, `verify` was clean, a corrupted blob made `verify --check` exit 1 and `verify` evict it, `cache rm --manifests` and `cache rm` cleared the right sections while the marker stayed, and a foreign directory was refused with its sentinel intact; an offline pull by branch name succeeded with the registry stopped. Test images were removed. Docs: `docs/spec/cache.md`, `docs/spec/pull.md`, `docs/spec/config.md`, `docs/cli.md`, `docs/notes/git-cache-layout.md`. Gotchas: `else if` is not Emo syntax (nest the `else`); `os` has no stat, so the cache uses BSD `stat -f "%z %m %HT"` / GNU `stat -c "%s %Y %F"` through the runner; `write_atomic` must use a pid-suffixed part file or two writers of one key share a temp; the first online pull must `ensure_root` before `write_ref`, because the refs directory does not exist yet (the manual smoke caught this).

#### T1.16 Error Model, Exit Codes, and Logging

**Goal**: Define stable error categories and exit codes. Human-facing errors include a next step; machine-facing results are consumable via `--json`. Logs are quiet by default; `--verbose` adds request / command detail without leaking tokens.

**Deliverables**: `docs/spec/errors.md`, `src/errors.emo`, and table-driven tests.

**Acceptance**: Usage, Git, metadata, authentication, network, integrity, and runtime errors each have a fixed exit code; error output includes actionable remediation; `--verbose` redacts tokens, Authorization headers, and presigned URL query strings.

**Depends on**: T1.1 · **Estimate**: 2h

> **Notes** (2026-11-18, ~2h): Done. `src/errors.emo` defines the stable model: kinds `failure/usage/git/metadata/authentication/network/integrity/runtime` with exit codes 1, 2, 3, 4, 5, 6, 7, 8 (`src/common.emo` holds the constants). Commands report through `errors.report` / `usage_report` / `report_kind`, which print one human line plus a `hint:` remediation line, or — with `--json` — one error object on stderr while stdout stays reserved for results. Classification lowercases the message and checks in a deliberate order: `runtime:` prefix, usage phrases, integrity, network, authentication, lock/config metadata (before the generic `git:` prefix, so a missing lock read via Git is metadata), `git:`/`git cache:`, broader metadata, then `failure`. `Logger` writes only with `--verbose`, through an injectable `LogSink` (`StderrSink` production, `BufferSink` tests): redacts `Authorization`/`Proxy-Authorization`/`Cookie`/`Set-Cookie` values, URL userinfo and query strings (presigned signatures, token `service`/`scope`), URL-shaped tokens in free text, and URL arguments in logged commands; bodies are never logged. Wiring: pull logs settings/step detail, registry requests via a new `registry.LoggingTransport`, blob GETs via the logger passed to `RegistryBlobTransport`, and import argv; `cache verify` now exits with the integrity code (7) while issues remain. Tests: 20 table-driven cases in `test/error_model.emo` (classification, codes, hints, JSON escaping/redaction, sink capture, report codes), 1 cache-command integrity case, and updated resolve/cache exit-code assertions; `emo test` 220/220. Manually verified: an offline cache miss prints a metadata hint and exits 4, `--json` emits the error object on stderr, `cache rm` on a foreign directory exits 4 with its sentinel intact, an unknown option exits 2, `cache verify --check` on a corrupt blob exits 7 and the repair exits 0, and a real verbose pull logged redacted manifest/blob requests and the skopeo command with no secrets. Docs: `docs/spec/errors.md`, `docs/cli.md`, `docs/spec/cache.md`, `docs/spec/pull.md`. Gotchas: `case` patterns must be literals — a `const` name is a binding pattern, so the exit/hint tables use string literals; interface methods must declare a return type (`def write(text String) Void`); the classifier's order is the contract (runtime prefix first, lock/config before Git); error JSON goes to stderr so `--json` pipelines never mistake an error for data; redaction happens in both `report_error`/`error_json` and the logger, so no path prints an unredacted URL.

#### T1.17 M1 Test Baseline, E2E Script, and Spec Docs

**Goal**: Fill in M1's tests and docs so later changes have regression coverage. Use local fixture Git repositories plus Emo-based mock registry / CDN services to cover the full path.

**Deliverables**: `scripts/e2e-m1.sh`, the mock services, a summary of the YAML / lock / config / errors specs under `docs/spec/`, and an M1 usage example in the README (English and Chinese kept in sync).

**Acceptance**: `emo test` passes; `scripts/e2e-m1.sh` is repeatable in a clean temp directory; it does not depend on the real Docker Hub; documented commands match actual output.

**Depends on**: T1.1-T1.16 · **Estimate**: 2-3h

> **Notes** (2026-11-18, ~2h): Done. `scripts/e2e-m1.sh` is the repeatable, fully local M1 end-to-end: it builds the CLI and `mock/m1_fixture.emo`, assembles an OCI layout from `test/fixtures/oci`, creates a local Git repository whose lock names the loopback mock registry, then runs `resolve`, `pull` (importing into the detected Docker/Podman/containerd), a second `pull --offline` with the mock stopped, `cache ls`, `cache verify`, and a corruption leg (`verify --check` exits 7, repair exits 0). The mock is one loopback `httpd` server acting as both the registry (`/v2/`, manifest by digest, blob GET → 307) and the CDN (`/cdn/<hex>`), reading the prepared layout; readiness lines use raw `os.write(1, …)` so the script's poll never waits on a stdio buffer. Without skopeo plus a runtime the script still exercises resolve/manifest/blob/cache and checks that pull exits 8. `KEEP_TMP=1` keeps the temp dir and logs; by default the trap removes the temp dir, stops the mock (its accept-loop child via `pkill -P`) and the CLI's lingering scheduler workers (matched by the run's binary path), and removes the imported image. `docs/spec/README.md` indexes all M1 specs (YAML, lock, config, errors, registry client, pull, OCI layout, runtime import, cache) and summarizes the flow; the README (EN + zh-CN) gained an M1 walkthrough whose output matches the CLI, the updated failure-fallback text, and checked roadmap items. `emo test` 220/220; the E2E ran end to end against Docker 29.9.3 + skopeo 1.25.2. Gotchas: the c-target scheduler leaves idle worker processes after the CLI's main exits; they inherit stdout, so `$(...)`/pipes around the CLI hang — the script redirects every CLI invocation to a file and the trap kills the run's binary path; `httpd.serve`'s accept loop is a child process, so the mock is stopped with `pkill -P` before the main pid; the small gzip fixture is served intact by `httpd` (the earlier 29 MB failure was the large-body case, not NUL truncation); the fixture is linux/amd64 on an arm64 host, so the E2E verifies the imported image with `docker image inspect` (the runnable-image `docker run` check was T1.14's manual E2E). This closes M1 (T1.1-T1.17).

## 5. M2: Distribution MVP

### 5.1 Goal and Exit Criteria

Implement the minimum viable Distribution Layer from the README: OCI-compatible manifest / tag management, Bearer token authentication, S3/MinIO object storage, presigned blob URL redirects, and reproducible compose deployment.

Exit criteria:

- `docker compose up` starts the registry, MinIO, and the reverse proxy; health checks pass.
- Images can be pushed with `oras` / `skopeo` / `pokerface build --push`.
- `GET /v2/<repo>/manifests/<tag>` returns the correct manifest, and blob GET returns a 307 to a presigned CDN URL.
- `pokerface resolve` and `pokerface pull` work against this registry.
- Pull / push scopes are enforced; unauthorized requests are rejected.
- `scripts/e2e-m2.sh` runs in a clean environment.

### 5.2 Task Overview

| Status | ID | Task | Depends on | Estimate |
| --- | --- | --- | --- | --- |
| [x] | T2.1 | Service skeleton, configuration, and health checks | T1.2 | 2h |
| [x] | T2.2 | SQLite data layer and migrations | T2.1 | 2-3h |
| [x] | T2.3 | OCI manifest / index model and validation | T1.5 | 2-3h |
| [x] | T2.4 | BlobStore interface and local filesystem backend | T2.1 | 2h |
| [x] | T2.5 | AWS SigV4 signing and presigned URLs | T2.1 | 3h |
| [x] | T2.6 | S3 / MinIO BlobStore adapter | T2.4, T2.5 | 3h |
| [x] | T2.7 | `/v2/` base protocol and error format | T2.1, T2.2 | 1-2h |
| [x] | T2.8 | Manifest GET / HEAD and tag / digest resolution | T2.2, T2.3, T2.7 | 3h |
| [x] | T2.9 | Blob GET and 307 presigned redirect | T2.4, T2.6, T2.8 | 2-3h |
| [x] | T2.10 | Blob upload: POST / PUT | T2.4, T2.7 | 3h |
| [x] | T2.11 | Chunked upload and resumable transfers: PATCH / GET / DELETE | T2.10 | 3h |
| [x] | T2.12 | Manifest PUT and tag updates | T2.3, T2.10, T2.11 | 2-3h |
| [x] | T2.13 | Resolve / metadata API | T2.8, T2.12 | 2h |
| [x] | T2.14 | Authentication and token service | T2.7 | 3-4h |
| [x] | T2.15 | Cache headers, ETag, and CDN behavior | T2.8, T2.9 | 2h |
| [x] | T2.16 | Tag listing and pagination | T2.12 | 2h |
| [x] | T2.17 | Deployment: registry + MinIO + Caddy | T2.6, T2.14 | 3h |
| [x] | T2.18 | Observability and audit logging | T2.1 | 2-3h |
| [x] | T2.19 | Protocol smoke and conformance tests | T2.1-T2.18 | 3h |

### 5.3 Task Details

#### T2.1 Service Skeleton, Configuration, and Health Checks

**Goal**: Create the registry service entry point, register routes with `httpd`, support YAML and environment-based configuration, `/healthz`, `/readyz`, graceful shutdown, and request size limits.

**Deliverables**: `registry/main.emo`, configuration structs and validation, health checks, and `docs/spec/registry-config.md`.

**Acceptance**: `emo build` passes; `/healthz` returns 200; `/readyz` returns non-200 when the database or object store is unavailable; SIGTERM stops accepting new requests and finishes in-flight ones; missing configuration produces a clear error.

**Depends on**: T1.2 · **Estimate**: 2h

> **Notes** (2026-11-18, ~2h): Done. `registry/config.emo` loads a required YAML file (`--config` > `POKERFACE_REGISTRY_CONFIG` > `./registry.yaml`) with strict per-level unknown-field checks, env overrides, and one validated value (listen 127.0.0.1:5000, data_dir, fs/s3 store, body/header/timeout limits, shutdown file). `registry/health.emo` serves `GET /healthz` (200 ok), `GET /readyz` (writable `data_dir` + fs store root probed with a per-pid file; s3 reports not-ready until T2.6; 503 body names each failure), a `/v2/` 200 placeholder for T2.7, 405 on non-GET, 404 otherwise. `registry/main.emo` binds with `httpd.serve_with` using the configured max body/header bytes and read/idle timeouts, prints `LISTEN=`/`SHUTDOWN_FILE=` on stdout for supervisors, and serves until the shutdown marker appears. **Shutdown**: Emo has no custom signal handler, so the server ignores SIGTERM/SIGINT and polls `<shutdown_file>`; the new `scripts/run-registry.sh` owns the signals — on TERM/INT it touches the marker and waits, and the server's `stop()` closes the listener while `wait()` drains in-flight requests (idle keep-alives bounded by `idle_timeout`). `registry/registry.example.yaml` and `docs/spec/registry-config.md` document fields, env vars, endpoints, checks, and the signal constraint. Tests: 10 config cases (parse/defaults/precedence/env/unknown/invalid) + 6 health cases; `emo test` 236/236. Manually verified: the launcher starts the service, `/healthz`, `/readyz`, and `/v2/` return 200, `POST /healthz` returns 405, a file-blocking `data_dir` makes `/readyz` 503 with the path and reason, SIGTERM to the launcher logs `shutting down`/`stopped` and closes the port, and a missing config exits 1 with the path plus both remedies. Gotchas: `httpd.serve_with` needs a standalone arrow block (`const handler = -> (req httpd.Request) { … }`) because the attached form only fills the last argument; `Int64.to_float64()` feeds the timeout options; the config file is required (per the acceptance) and relative paths are cwd-relative; a signal sent directly to the server binary is ignored by design — supervisors must use the launcher or touch the marker.

#### T2.2 SQLite Data Layer and Migrations

**Goal**: Use SQLite for repositories, manifests, tags, blobs, and upload sessions; add repeatable migrations.

**Deliverables**: `registry/db.emo`, migration SQL, a `schema_version` table, and CRUD tests.

**Acceptance**: A fresh database initializes successfully; repeated migrations are idempotent; constraints on `repositories` / `manifests` / `tags` / `blobs` / `uploads` are correct; WAL and busy timeout are configured; concurrent reads do not fail.

Suggested tables:

- `repositories(id, name UNIQUE, created_at)`
- `manifests(id, repository_id, digest, media_type, size, body, created_at)`
- `tags(repository_id, tag, digest, updated_at)`
- `blobs(repository_id, digest, size, created_at)`
- `uploads(id, repository_id, state, created_at, expires_at)`

**Depends on**: T2.1 · **Estimate**: 2-3h

> **Notes** (2026-11-18, ~2.5h): Done. `registry/db.emo` wraps the stdlib `sqlite3` package (added as a `c`-target dep): `open`/`connect` apply WAL, `synchronous=NORMAL`, `busy_timeout=5000`, and `foreign_keys=ON`, then `migrate` records each version in `schema_version` inside `BEGIN IMMEDIATE`, re-checking the version so two starting servers cannot both apply one. Schema v1 is the five suggested tables with their constraints: unique repository names, `UNIQUE (repository_id, digest)` on manifests, `PRIMARY KEY (repository_id, tag)` plus a composite FK making a tag name a manifest in the same repository, `CHECK (size >= 0)`, and `CHECK (state IN ('pending','completed','cancelled'))` on uploads; deletes cascade from the repository. CRUD covers all five tables with sentinels instead of `Option` (0, -1, ""), plus `begin`/`commit`/`rollback` for the multi-row writes of T2.8. Config gained `db_path` (default `<data_dir>/registry.db`, `POKERFACE_REGISTRY_DB_PATH`), and `/readyz` gained a `db` check — `registry.db.Health` opens a short-lived connection per probe (httpd runs one process per connection, so a shared handle would be forked into every request) and reads the 16-byte header first, so a directory or garbage file answers 503 instead of dropping the connection; verified the check flips 200→503→200 without a restart. **Testing** is split because the sqlite3 package is `c`-only and `emo test` always interprets (E3009): the pure parts (migration order, table/constraint text, pragmas, path helpers, `ensure_parent`) are in `test/registry_db.emo` under `emo test`, while `registry/db_selftest.emo` + `scripts/check-registry-db.sh` cover the real database — 62 checks including every CRUD path, the FK cascade, the `CHECK` constraints, migration idempotency across reopen, and a writer/reader pair. Also verified against the system `sqlite3` CLI that the created file reports `schema_version` 1 and `journal_mode=wal`. Gotchas: Emo fields are immutable after `init` (mutate through `Box`); `PRAGMA journal_mode=WAL` needs the file on a writable path, and a `db_path` that is a directory fails start-up with SQLite's own message and exit 1; `emo build` refuses any entry under `test/`, which is why the compiled checker lives beside the code.

#### T2.3 OCI Manifest / Index Model and Validation

**Goal**: Implement parsing and encoding for OCI Image Manifest, Image Index, and Image Config; validate descriptor media type, digest, and size; support selecting a child manifest by platform.

**Deliverables**: `registry/oci.emo`, golden fixtures, and parser / validation tests.

**Acceptance**: Real image manifests parse; missing fields, bad digest formats, and size mismatches are rejected; encoded bytes are reproducible; index platform selection matches the client.

**Depends on**: T1.5 · **Estimate**: 2-3h

> **Notes** (2026-11-18, ~2h): Done. `registry/oci.emo` models `Descriptor`, `Platform`, `IndexEntry`, `ImageManifest`, `ImageIndex`, `ImageConfig`, and a `Document` wrapper (kind + both shapes, because Emo has no sum types). `parse_document` takes the media type from the `Content-Type` header (parameters stripped) or the body's `mediaType`, requires them to agree, and dispatches; `parse_manifest`/`parse_index` accept a caller-supplied type; `parse_config` reads architecture/os/rootfs diff_ids and `config.Labels`. Validation is total and answers error tuples: schemaVersion must be 2, required members and JSON kinds are checked, digests must be `sha256:` + 64 lowercase hex, media types must be `type/subtype` with no whitespace, sizes must be non-negative integers, annotations must be string-valued. `verify_body` hashes and measures a body against a descriptor and names both sides on a mismatch. Encoding uses `json.object` in a fixed field order with compact separators; a test pins byte equality against two new golden fixtures and proves encode→parse→encode is stable. `select_platform` returns the first entry matching os+arch exactly (variant ignored), mirroring `src/registry.emo`, with the same "available:" miss message. Fixtures: a multi-arch `index.json` over the existing skopeo-valid image, `manifest.docker.json`, and `manifest.canonical.json`/`index.canonical.json`. 17 tests in `test/registry_oci.emo`; `emo test` 264/264. Gotchas: the negative-guard form (`if !value.is(...) { return ... }` then use class methods) does not narrow, so every array/object parse uses the positive branch; `parse_manifest(body, "")` errors when the body itself omits `mediaType`, so tests that build minimal bodies pass the type explicitly. Encoding is documented as canonical, not lossless — unknown members are dropped and the registry still stores the client's original bytes.

#### T2.4 BlobStore Interface and Local Filesystem Backend

**Goal**: Define the blob storage abstraction: `put`, `get`, `head`, `delete`, and `presign_get`. The local filesystem backend is for development and tests, with content-addressed paths.

**Deliverables**: `registry/blobstore.emo`, the local backend, and interface tests.

**Acceptance**: Writes use a temp file plus atomic rename; reads support Range; paths cannot escape the root; data survives a restart; `presign_get` returns empty for backends without presigning, and the caller falls back to direct streaming.

**Depends on**: T2.1 · **Estimate**: 2h

> **Notes** (2026-11-18, ~2h): Done. `registry/blobstore.emo` defines `BlobStore` (`put`, `put_file`, `get`, `read_range`, `head`, `delete`, `presign_get`) and `LocalStore`, which lays blobs out as `<root>/sha256/<hex>` plus a tiny `<hex>.size` record. The size record exists because Emo's `os` has no `stat` and `file` only reads whole files — without it, HEAD/Content-Length would read a whole layer. Put streams to `.tmp-<pid>-<hex>` hashing and counting, rejects a digest mismatch (temp removed, nothing stored), writes the size record through its own temp-and-rename, then renames the blob into place; the rename is the commit point, so no reader sees a partial blob, and a crash between the renames leaves only a harmless orphan record that the next put repairs. Re-putting an existing digest is a no-op (one copy). `read_range` validates non-negative offset/length, errors past the end, and clips at EOF; `head` answers exists=false for missing and size=-1 for "bytes present, record missing"; `delete` removes both and answers whether the blob existed; `presign_get` returns "" so callers stream. Missing content is `blobstore: not found: <digest>` plus `is_not_found()`. Digest validation moved to a new `registry/digest.emo` shared with `registry/oci.emo`, and paths are built from the validated hex only — `..`, `/`, other algorithms, and uppercase are rejected before any filesystem call. `registry/main.emo` now opens the fs store at startup (creating `<root>/sha256`); a root that is a file exits 1 with the path and reason, verified manually along with `/readyz` 200 and the created layout. Tests: 14 in `test/registry_blobstore.emo` (round-trip + restart, dedup, mismatch leftovers, streamed put_file over 64 KiB, not-found, range clipping, escape attempts, delete idempotency, empty blob, missing-record repair, interface conformance, file-in-the-way root); `emo test` 278/278. Gotchas: there is no typed `const` binding, so interface conformance is exercised by passing `LocalStore` to a `BlobStore`-typed helper; `os.open_read` is the only cheap existence check (no stat), which is why existence and size live in separate files.

#### T2.5 AWS SigV4 Signing and Presigned URLs

**Goal**: Use `crypto` HMAC-SHA256 to implement AWS Signature V4 request signing and query-string presigning, compatible with MinIO path-style access.

**Deliverables**: `registry/sigv4.emo`, official test vectors, and unit tests with a fixed clock.

**Acceptance**: Signatures match the AWS test vectors; presigned URLs work within their validity window and fail after expiry; URI encoding follows SigV4; keys and signatures never appear in logs.

**Depends on**: T2.1 · **Estimate**: 3h

> **Notes** (2026-11-18, ~2h): Done. `registry/sigv4.emo` implements the whole algorithm as pure functions over an injected `time.Time`: canonical request (encoded URI, canonical query, normalized headers, signed names, payload hash), string to sign, the HMAC key chain, and the signature. Two entry points: `sign_request` adds `x-amz-date` (replacing any caller value), the session token, and `authorization` last; `presign` builds the query-string form (`UNSIGNED-PAYLOAD`, `host` signed, `X-Amz-Signature` appended last) and returns a `PresignedUrl` whose `valid_at(now)` covers exactly `[signed_at, signed_at + expires_in)`. Encoding follows SigV4 (`%20`, uppercase hex per UTF-8 byte, `/` kept in the URI but `%2F` in query values, pairs sorted by encoded name then value; headers lowercased, trimmed, whitespace-collapsed, sorted, duplicate names comma-joined). **Vectors matched on the first run**: aws-sig-v4-test-suite `get-vanilla` (`5fa00fa3…`), `get-vanilla-query-order-key` (`eedbc4e2…`), and the S3 presign example (`aeeed9bb…`), which together exercise the canonical request, encoding, date scope, and HMAC chain. 12 tests in `test/registry_sigv4.emo` cover the vectors plus encoding, query/header canonicalization, session tokens in both modes, caller date/authorization replacement, clock/secret sensitivity, the window's boundary second, and UTF-8 paths; `emo test` 290/290. The module logs nothing and the secret appears only as HMAC key material; a test pins that a presigned URL never contains the secret. Gotchas: there is no `else if`, `Bytes.get` already returns Int64 (no `to_int64`), and arrays have no sort — the canonical sorter is an insertion sort over encoded pairs (fine for the handful of parameters). Follow-ups: request retries/logging live in T2.6, which must redact Authorization and presigned URLs.

#### T2.6 S3 / MinIO BlobStore Adapter

**Goal**: Implement an S3-compatible storage backend on top of SigV4, supporting PUT / GET / HEAD / DELETE and GET presigning; configure endpoint, bucket, region, access key, secret key, TLS, and path-style.

**Deliverables**: `registry/s3_blobstore.emo`, MinIO integration tests, and configuration examples.

**Acceptance**: Upload, download, and presigned access against MinIO work; a missing bucket fails startup with a clear message; TLS and custom CAs are configurable; network errors retry with clear messages; keys are never logged.

**Depends on**: T2.4, T2.5 · **Estimate**: 3h

> **Notes** (2026-11-18, ~3h): Done, with one environment caveat below. `registry/s3_blobstore.emo` implements BlobStore over signed HTTP: path-style and virtual-host addressing, keys `[prefix/]sha256/<hex>`, an injectable transport (the real one builds TLS options from `ca_file`/`verify_tls`), and a start-up signed HEAD of the bucket that fails with the bucket name and endpoint (404) or names the credential settings without their values (403). `store.s3.*` joined the config with strict field checks, env overrides, and validation (endpoint scheme/path, bucket, region, credentials, presign ttl 1–604800); the summary prints `access_key=<set>` and never the keys. Requests sign `host` (the default port dropped so it matches the wire), `x-amz-content-sha256`, and any extra headers (`content-type`, `range`, session token); the signed Host entry is dropped before sending because the stdlib client writes it. Transport errors and 5xx retry 3× with backoff; 4xx do not. Error text carries method/URL/status and S3's `<Code>`, never the body or keys. **Gotcha found live**: `head` cannot use HEAD — the stdlib http client reads `Content-Length` bytes even on a HEAD response, while S3 announces the object size with no body (the connection dies mid-read). It now uses a ranged GET (`bytes=0-0`) and takes the total from `Content-Range`, with a 416→plain-GET fallback for empty objects and a 200 fallback for servers that ignore Range. Health now asks a backend `BlobHealth.probe()`, so /readyz works for both stores (LocalStore probes its digest dir, S3Store heads the bucket). Tests: 20 in `test/registry_s3.emo` — injected-transport protocol coverage plus a live round trip (put/get/head/range/presigned fetch/expiry 403/delete) when `POKERFACE_TEST_S3_*` is set — the mock `mock/s3_fixture.emo` verifies SigV4 and presigned expiries and stores objects on disk, run by `scripts/e2e-s3.sh`; `emo test` 314/314. Manually verified the service on the s3 backend: start-up bucket check, `/readyz` 200, summary redaction, and a missing bucket exiting 1 with the clear message. **Caveat**: Docker Hub is unreachable from this machine (`docker pull minio/minio` times out), so the MinIO binary/image could not be run; the live leg was exercised against the local SigV4-verifying fixture instead. Point the `POKERFACE_TEST_S3_*` variables at MinIO to run the identical test against it.

#### T2.7 `/v2/` Base Protocol and Error Format

**Goal**: Implement `GET /v2/` with `Docker-Distribution-API-Version: registry/2.0`; standardize OCI error JSON `{"errors":[{"code","message","detail"}]}`; cover 401 / 404 / 405 responses.

**Deliverables**: routes and middleware, error response helpers, and protocol tests.

**Acceptance**: In unauthenticated mode `GET /v2/` returns 200; with auth enabled, T2.14 covers the 401 challenge; unknown routes return 404; method mismatches return 405 with `Allow`; all errors follow the OCI error format; responses carry a request id.

**Depends on**: T2.1, T2.2 · **Estimate**: 1-2h

> **Notes** (2026-11-18, ~1.5h): Done. `registry/api.emo` owns the distribution API's outer skin: `GET /v2/` (and `/v2`) answers 200 `{}` with `Docker-Distribution-API-Version: registry/2.0`, every response — success and error — carries `X-Request-Id`, and every error is the OCI envelope via `error_body`/`error_response`/`not_found`/`bad_request`/`method_not_allowed`/`unauthorized` with the full code constant set (BLOB_UNKNOWN … TOOMANYREQUESTS). Unknown routes answer 404 `NAME_UNKNOWN` with `detail: "<METHOD> <path>"`; a method mismatch on `/v2/` answers 405 with `Allow: GET` and `UNSUPPORTED`; the 401 helper (challenge header + UNAUTHORIZED code) is ready for T2.14. Request ids echo a client `X-Request-Id` only when it is 1–64 characters of `[A-Za-z0-9._-]` (CR/LF cannot be injected through the echo) and otherwise generate `pf-<pid>-<monotonic ns>`, unique without shared mutable state in the per-connection process. Health routing moved to `handle_health` and the router dispatches it ahead of the catch-all, so `/healthz` and `/readyz` keep their plain-text bodies. Tests: 12 in `test/registry_api.emo` (probe and headers, 405/404 envelopes with detail, health dispatch, id echo and sanitization, unique generated ids, envelope shape with/without detail, 400 helper, 401 challenge, single common headers); `emo test` 326/326. Manually verified over the wire: `/v2/` shows the version header and a request id, `POST /v2/` returns the UNSUPPORTED JSON with Allow, `/nope` returns NAME_UNKNOWN, and a client `X-Request-Id` is echoed. Gotchas: no string ordering operators in Emo (the id charset check uses `index_of`), and named-argument construction of `httpd.Request` works for tests in place of a factory.

#### T2.8 Manifest GET / HEAD and Tag / Digest Resolution

**Goal**: Implement `/v2/<name>/manifests/<reference>` where `<name>` may contain `/`; reference supports tag and digest; handle `Accept` and return the raw manifest bytes with `Docker-Content-Digest`, `Content-Type`, and `Content-Length`.

**Deliverables**: routes, lookup logic, HEAD support, and tests.

**Acceptance**: Fetch by tag and digest both work; missing content returns 404 `MANIFEST_UNKNOWN`; HEAD returns no body; digest mismatches are rejected; multi-arch indexes are returned intact.

**Depends on**: T2.2, T2.3, T2.7 · **Estimate**: 3h

> **Notes** (2026-11-18, ~2.5h): Done. `registry/manifests.emo` serves `GET|HEAD /v2/<name>/manifests/<reference>`: the path splits on `/manifests/` so repository names may contain slashes, a digest-shaped reference is used directly and a tag resolves through the tags table, and a miss answers 404 `MANIFEST_UNKNOWN` with `<repo>:<reference>` as the detail. A `sha256:` reference that is not a valid digest answers 400 `DIGEST_INVALID`. Every read re-hashes the stored bytes and answers 500 `UNKNOWN` (with both digests) when they contradict the row — the registry never serves bytes that disagree with their name. `Accept` is parsed (comma list, parameters stripped, case-insensitive, `*/*`) and a mismatch is a 404 rather than serving a type the client cannot use. Responses carry `Content-Type`, `Docker-Content-Digest`, and an explicit `Content-Length`; HEAD returns the headers with no body (httpd strips it). Storage access is a `ManifestStore` interface: the handler tests use a fake, `DbManifests` is the SQLite implementation opening a short-lived connection per request (one process per connection, so no shared handle). The router moved out of `api.emo` into `registry/router.emo` with a `Service` carrying config/db/blob/manifests — `api.emo` now only holds the envelope, ids, and decoration, which avoids an api↔manifests module cycle. Tests: 13 handler tests in `test/registry_manifests.emo` (tag/digest reads, HEAD, 404s, 500s, digest mismatch, Accept variants, index intact, 400, 405, path shapes, router decoration) plus 5 checks in the compiled `db_selftest` for `DbManifests`; `emo test` 338/338, db selftest 70/70. Manually verified over the wire against a seeded SQLite file: tag and digest GET return the exact bytes with the digest header, HEAD has no body and the right length, a missing tag is the OCI 404, an Accept mismatch is a 404 with the stored type in the detail, and POST is a 405 with `Allow: GET, HEAD`. Gotchas: no `String.upper` (the Accept case-insensitive test uses a mixed-case literal), and the manifest route must be checked before the bare `/v2/` probe and the catch-all.

#### T2.9 Blob GET and 307 Presigned Redirect

**Goal**: Implement `/v2/<name>/blobs/<digest>`. With S3, return 307 plus a presigned `Location`; with the local filesystem backend, stream a 200. HEAD returns metadata and does not redirect.

**Deliverables**: blob GET / HEAD, presigned TTL configuration, and tests.

**Acceptance**: The URL in the 307 `Location` downloads directly and expires; the local backend returns the correct `Content-Length` and `Docker-Content-Digest`; missing blobs return 404 `BLOB_UNKNOWN`; the client works in both modes.

**Depends on**: T2.4, T2.6, T2.8 · **Estimate**: 2-3h

> **Notes** (2026-11-18, ~2h): Done. `registry/blobs.emo` serves `GET|HEAD /v2/<name>/blobs/<digest>`: the path splits on `/blobs/` (repository names may contain slashes), the digest is validated first (400 `DIGEST_INVALID`), and the route requires both a `blobs` row linking the digest to the repository and a present object in the backend — either miss is 404 `BLOB_UNKNOWN` with `<repo>@<digest>`. On S3, GET answers 307 with a presigned Location (no bytes proxied); on the filesystem, `presign_get` returns "" and the route falls back to the local bytes with `Content-Type`, `Docker-Content-Digest`, and `Content-Length`. HEAD never redirects and answers metadata directly, preferring the store's size record and falling back to the DB's. Both methods consult the store's head first, so a presigned URL for a missing object is a 404 here rather than at the CDN. The link lookup is a `BlobLinks` interface (`DbBlobLinks` opens a short-lived SQLite connection per request); the Service now carries the blob health probe and the full blob store separately, so `serve` takes the concrete store twice — concrete→interface passes structurally, and health stays a `BlobHealth`. Tests: 14 route tests in `test/registry_blobs.emo` plus 4 checks in the compiled `db_selftest` for `DbBlobLinks`; `emo test` 351/351, db selftest 75/75. Manually verified on the wire in both modes: fs GET/HEAD return the exact bytes/length with the digest header, missing and invalid digests are the OCI 404/400, POST is 405 with `Allow`; with the S3 fixture, GET returns a 307 whose Location (signature verified by the fixture) downloads the object on follow, and HEAD is a direct 200 without Location. Gotchas: the local path calls `presign_get` too and falls back — the fallback contract from T2.4 — so a test must expect that call; httpd prints 307 with reason phrase "Unknown" (valid HTTP; the package has no phrase for it).

#### T2.10 Blob Upload: POST / PUT

**Goal**: Implement the minimal OCI upload flow: `POST /v2/<name>/blobs/uploads/` creates a session; `PUT ...?digest=sha256:...` uploads the full blob; verify digest and size, deduplicate, and expire old sessions.

**Deliverables**: upload routes, the session table, single-blob upload tests, and a `curl` example.

**Acceptance**: A `HEAD` request finds the blob after upload; a digest mismatch returns 400 and stores nothing; duplicate blobs are stored once; expired sessions can be cleaned up; upload size limits are enforced.

**Depends on**: T2.4, T2.7 · **Estimate**: 3h

> **Notes** (2026-11-18, ~2.5h): Done. `registry/uploads.emo` serves the minimal OCI flow: `POST /v2/<name>/blobs/uploads/` opens a session (202, relative `Location` + `Docker-Upload-UUID`; the slash-less collection path accepted too), `PUT .../uploads/<id>?digest=…` hashes the body **before anything is stored** — a mismatch is 400 `DIGEST_INVALID` and neither the store nor the session changes — then stores the bytes, links the blob (`INSERT OR IGNORE`, so duplicates stay one copy), and completes the session under a `state = 'pending'` guard in one transaction (racing twin loses → 404). POST with `?digest=` is the spec's single-request monolithic upload, sharing the completion path. Sessions are an `UploadSessions` interface with `DbUploadSessions` (short-lived SQLite connection per request); every `start` first sweeps expired `pending` rows (indexed), TTL is a module constant (24h) with a config knob as follow-up. POST creates the repository row, so names are validated against the OCI grammar (per component `[a-z0-9]+` separated by `.`/`_`/`__`/`-+`, ≤255) → 400 `NAME_INVALID`. Size limits ride httpd's framing (413 over `limits.max_body_bytes`, both framings). The router checks the upload routes **before** the blob GET route (both match `/blobs/`). db.emo gained `upload_info` (state + repository name via join) and `complete_pending_upload` (the CAS). Tests: 27 in `test/registry_uploads.emo` (both path forms, monolithic POST, PUT completion, missing/invalid digests, mismatch storing nothing, unknown/completed/foreign sessions, store/lookup/complete failures, dedup against the fake store AND the real LocalStore incl. the empty blob, name tables, methods, split shapes, router dispatch) + 14 checks in the compiled db_selftest for `DbUploadSessions`; `emo test` 378/378, db selftest 89/89. Manually verified over the wire (curl): POST → 202 with Location/UUID, PUT with the right digest → 201 with `Docker-Content-Digest`, a `HEAD /v2/<name>/blobs/<digest>` then finds the blob, a wrong digest is the OCI 400 and stores nothing, `?digest=` PUT is a 400. Gotchas: `Map.get` raises on a missing key (use `has` first); `expire_uploads`/`put_blob` return scalars, not tuples; the name validator originally accepted separator-leading components (`-a`) — the grammar's leading `[a-z0-9]+` is enforced explicitly. Follow-ups: T2.11 (PATCH/GET/DELETE + concurrent-write rejection), a configurable TTL, the POST-mismatch session lingers pending until expiry (documented).

#### T2.11 Chunked Upload and Resumable Transfers: PATCH / GET / DELETE

**Goal**: Complete OCI chunked upload: `PATCH` appends data, `GET` reports the offset, and `DELETE` cancels a session; support client-side resume.

**Deliverables**: chunked upload implementation, state-machine tests, and compatibility tests with `oras` / `skopeo`.

**Acceptance**: Multi-part PATCH followed by PUT succeeds; GET mid-upload returns the correct `Range`; a deleted session is unusable; concurrent writes to the same session are rejected; abandoned sessions expire.

**Depends on**: T2.10 · **Estimate**: 3h

> **Notes** (2026-11-19, ~4h including the compiler investigation below): Done. `registry/uploads.emo` completes the OCI chunked protocol: `PATCH` appends a chunk whose `Content-Range` start must equal the session's recorded offset — out-of-order is 416 `BLOB_UPLOAD_INVALID`, an end disagreeing with the body length or a malformed range (`bytes=…` is refused; the spec pins `^[0-9]+-[0-9]+$`) is 400 — a PATCH **without** the header streams blindly (the skopeo shape); `GET` answers 204 with `Location` + `Range: 0-<last byte>` (omitted at zero bytes, since `0-0` would claim one); `DELETE` answers 204 and the session is unusable afterwards; the closing `PUT` may carry the final chunk under the same offset rules. Chunk bytes accumulate in `<data_dir>/uploads/<id>.part` (`os.open_append`) and migration 2 added `uploads.offset_bytes` as the authoritative CAS reference; every append runs inside `BEGIN IMMEDIATE`, so concurrent writers serialize and a second claimant of one offset answers 416 (the PUT finalization — `store.put_file`, blob link, completion — holds the same window: a deliberate registry-wide lock for v0.1). A digest mismatch at PUT leaves the session pending with its data; the expiry sweep inside every `start` now also removes swept sessions' part files. Interfaces grew (`append`/`cancel`/`part_path`, `UploadSession` gained `offset`), so the three T2.10 fakes and their Service constructions were updated. **The big find: the c target refuses a bare method call.** `case write_part(id, body)` inside a class — no `self.` prefix — passes the checker and the interpreter but lowers to an IR `Type_ref`, which the c emitter rejects with `the c target does not support this expression form (Type_ref)`, taking the whole package build down. Found by bisecting the registry tree in a clean copy (the failing package poisons every entry, so single-file probes only work in a pristine tree); the fix is mechanical — class methods always call through `self.` — pinned here because the checker should refuse it at the read (E5016-style) instead of letting codegen die. Tests: 27 new cases in `test/registry_uploads.emo` (streaming/ranged PATCH, 416s, 400s, GET/DELETE state machine, store/lookup/cancel failures, real-LocalStore legs for PATCH+PATCH+PUT, PUT-final-chunk, skopeo shape, mismatch keeping the session, empty blob, Content-Range parsing) + 14 more db_selftest checks (offsets, part-file bytes in order, cancel, expiry with file cleanup); `emo test` 403/403, db selftest 103/103. Manually verified over the wire with curl (chunked with Content-Range, GET resume, DELETE, 416, single-request POST) and a real `skopeo copy oci:… docker://127.0.0.1:…` push (streaming PATCH shape). Follow-ups: per-session exclusion instead of the registry-wide write lock during PUT, a configurable TTL, orphan part files from hard crashes.

#### T2.12 Manifest PUT and Tag Updates

**Goal**: Implement `PUT /v2/<name>/manifests/<tag|digest>`, verify that the manifest's config and layers exist, store the manifest, and update the tag atomically.

**Deliverables**: manifest writes, tag updates, and transaction tests.

**Acceptance**: `oras push` / `skopeo copy` succeeds; missing references return `MANIFEST_BLOB_UNKNOWN`; tag updates are atomic; the response includes `Docker-Content-Digest`; a failure does not overwrite the old tag.

**Depends on**: T2.3, T2.10, T2.11 · **Estimate**: 2-3h

> **Notes** (2026-11-19, ~2.5h): Done. `registry/manifests.emo` gained the write half: `PUT /v2/<name>/manifests/<tag|digest>` stores the bytes **verbatim** under their digest (`ManifestWriter` interface; `DbManifests.put` hashes and `INSERT OR IGNORE`s — re-push is a one-row no-op) and, for a tag reference, points the tag with a single `INSERT OR REPLACE` (atomic; a failure never disturbs the old tag). Validation runs before any write: parse via the T2.3 `parse_document` (Content-Type ↔ body `mediaType` must agree; either may stand alone → 400 `MANIFEST_INVALID`), a digest reference must match the body's hash (400 `DIGEST_INVALID` naming both), a tag must satisfy the OCI grammar `[a-zA-Z0-9_][a-zA-Z0-9._-]{0,127}` (400 `TAG_INVALID`; `/` is not a tag so the digest check runs first), and the repository name is checked because PUT creates the row (400 `NAME_INVALID`). Every reference must exist: a manifest's config + layers are checked against the repository's blob links, an index's children against stored manifests — the first miss is `404 MANIFEST_BLOB_UNKNOWN` naming the digest with nothing written. Lookup failures inside the check answer 500, distinct from misses. The `subject` descriptor is deliberately unchecked (the spec requires accepting an absent subject; the T2.3 parser drops it). Success: `201` + `Location` + `Docker-Content-Digest`. Service carries `manifest_writer` (the same `DbManifests` instance serves both interfaces), so the three T2.x test files' ctors and the GET tests' `handle` calls gained the new arguments. Tests: 22 in `test/registry_manifest_put.emo` (tag/digest puts, mismatch, parse/type/disagreement 400s, tag grammar, name grammar, missing config/layer/child → 404 with the digest, empty layers, subject accepted, tag-move sequence, store/tag/link-check 500s, 405 with `Allow: GET, HEAD, PUT`, router dispatch) + 10 db_selftest checks (verbatim round-trip, digest answer, re-put no-op, tag point/update, unknown-repository tag rejected); `emo test` 425/425, db selftest 114/114. **Manually verified: a full `skopeo copy oci:… docker://127.0.0.1:…` push now succeeds end to end** (blob uploads were T2.11; the manifest step that failed before lands here), manifest GET/HEAD by tag return the exact bytes with `Docker-Content-Digest`, and a curl PUT with an empty-layers manifest moved a tag (201, new digest served). Gotchas: the reference-check helper needed a three-way answer (present/missing/failure) — a two-tuple conflated a link-store failure with a missing blob and answered 404 where 500 belonged; caught by the tests.

#### T2.13 Resolve / Metadata API

**Goal**: Provide a read-only endpoint for CLI and operational debugging: `GET /api/v1/resolve?repository=<name>&tag=<tag>`, returning the digest, media type, platforms, and an optional commit annotation from `org.opencontainers.image.revision`.

**Deliverables**: the endpoint, JSON responses, authentication, and tests.

**Acceptance**: Existing tags return full information; missing tags return 404; unauthorized requests return 401/403; storage credentials are never exposed; `pokerface` can use it as a read-only fallback when Git metadata is missing.

**Depends on**: T2.8, T2.12 · **Estimate**: 2h

> **Notes** (2026-11-19, ~2h): Done. `registry/resolve.emo` serves `GET /api/v1/resolve?repository=<name>&tag=<tag>`: missing/empty parameters are 400, a name failing the OCI grammar is 400 `NAME_INVALID`, an unknown tag is 404 `MANIFEST_UNKNOWN` with `<repo>:<tag>`; success answers one JSON document — repository, tag, digest, media type, `platforms` (from an index's own entries, or an image manifest's **config blob** via the blob store; `variant` when set), and `revision` from the document's `org.opencontainers.image.revision` annotation (omitted when absent). No credential or store setting ever appears in a response. Auth rides the router: with auth enabled the endpoint needs `repository:<name>:pull` for the queried name (the scope is computed from the query, answered with the standard 401 challenge) — anonymous, wrong-repository, and pull-less tokens all fail; without auth it is open. The response always decorates with the API version and request id. Tests: 14 in `test/registry_resolve.emo` (full document, absent revision, index platforms with variants, 400/404/500 paths, GET-only, router dispatch without auth, the auth-enabled challenge/pass legs); `emo test` 460/460. Manually verified over the wire: a skopeo-pushed tag resolves with the amd64/linux platform, a missing tag is 404, missing parameters are 400. Gotchas: indexed-element narrowing (`items[0].is(...)` then `items[0].entries()`) does not typecheck — bind the element to a local first; a `var` holding a narrowed `JsonArray` keeps the `Json` type, so narrow again at the read site.

#### T2.14 Authentication and Token Service

**Goal**: Implement the Bearer token flow: `GET /v2/` returns 401 with `WWW-Authenticate`; `/token` exchanges Basic auth for a short-lived scoped token; middleware validates `repository:<name>:pull|push`.

**Deliverables**: token issuance / validation, scope middleware, configuration examples, and negative tests.

**Acceptance**: Anonymous pull is rejected (when auth is enabled); a pull-only scope cannot push; expired tokens return 401; cross-repository access is denied; passwords and signing keys never appear in logs; the v0.1 config-file flow works.

**Depends on**: T2.7 · **Estimate**: 3-4h

> **Notes** (2026-11-19, ~3.5h): Done. `registry/auth.emo` implements Docker's Bearer flow with HS256 JWTs: `GET /v2/` and every protected route answer 401 + `WWW-Authenticate: Bearer realm="…",service="…",scope="…"[,error="…"]` (realm defaults to `http://<listen>/token`); `/token` exchanges Basic auth for `{"token","expires_in","issued_at"}`; the token carries Docker-shaped `access` claims (`repository:<name>:pull,push`) and the stateless gate in the router verifies signature (constant-time), window (`expired_token`), issuer, and scope. Docker parity: auth failures are always 401 with a challenge (invalid_token / expired_token / insufficient_scope) so clients re-auth with the missing scope; unknown account and wrong password answer the identical 401 with a constant-time compare. Scopes parse space-separated with comma-joined actions; malformed ones (bad name, unknown action) are 400 and grant nothing — a pull-only token cannot push (401 insufficient_scope) and cross-repository tokens are denied. Config: `auth:` section (enabled, realm, service, issuer, token_ttl ≥ 60, users, signing_key or signing_key_file) with strict unknown-field checks, `POKERFACE_REGISTRY_AUTH_SIGNING_KEY` / `_AUTH_ENABLED` env overrides, secret files read once at load (trailing newline trimmed, both inline+file is an error), enabled-without-key-or-users is a start-up error, and a summary that prints `auth=enabled users=<n> signing_key=<set>` — no secret ever reaches the log (pinned by a test and grep on the live server). base64url rides the new `base64` dep. Tests: 25 new cases in `test/registry_auth.emo` (codec, mint/verify matrix, scope matching, challenge shape, the endpoint's 200/401/400/405, gate decisions incl. cross-repo and pull-only-push, router-level challenges with auth enabled, config section/defaults/env/redaction); `emo test` 450/450. **Manually verified: the full skopeo dance works** — `skopeo login --username alice …` then `skopeo copy` pushed a whole image through the challenge/token/push cycle; anonymous manifest GET is 401; the signing key does not appear in the server log. Gotchas: `(R.error, …)` tuples carry a String statically — the gate cannot hand a Response through the error slot, so `check_token` returns the reason and the router builds the 401 (the reason-to-error-word mapping lives in `error_class`); comma is an ACTION separator inside one scope, not a scope separator (caught live by the skopeo dance); negative `is()` guards do not narrow — the yaml/json parse helpers take the narrowed types through positive-branch wrappers.

#### T2.15 Cache Headers, ETag, and CDN Behavior

**Goal**: Use different cache policies for immutable blobs and mutable manifests; support `ETag` / `If-None-Match`; ensure the CDN can cache blobs while tag updates still take effect promptly.

**Deliverables**: response-header middleware, CDN configuration notes, and tests.

**Acceptance**: Blobs return long-lived caching plus `immutable`; manifests return short caching or `no-cache`; `If-None-Match` hits return 304; new requests see the new digest after a tag update; CDN caching never pins an old manifest for long.

**Depends on**: T2.8, T2.9 · **Estimate**: 2h

> **Notes** (2026-11-19, ~1.5h): Done. New `registry/cache.emo` carries the policy and the validators: blobs answer `ETag: "sha256:…"` (the digest is the validator) with `Cache-Control: public, max-age=31536000, immutable` on GET **and** HEAD; manifests answer the same immutable pair when fetched **by digest** and `public, max-age=60, must-revalidate` when fetched **by tag** — a tag update therefore takes effect within a minute on any honoring CDN and never pins an old manifest longer; the presigned 307 is `no-cache` (a cached redirect could hand out an expired signature; the MinIO-served object bytes carry their own headers, noted for the CDN/ops docs). `If-None-Match` follows RFC 7232: `*`, weak `W/`, comma lists, optional quoting — a hit answers 304 with the same validators and no body, before any body work; a mismatch answers 200 fresh, and a tag update makes the old ETag miss immediately (verified live: PUT a new manifest to a tag, the next GET serves the new digest). Tests: 11 in `test/registry_cache.emo` (matcher table, blob/manifest GET/HEAD headers, 304 forms, 307 no-cache, tag-vs-digest policies); `emo test` 470/470. Manually verified with curl over a live registry (headers, 304s on blob and manifest, freshness after a tag update). Gotcha: arrays have no `+` concatenation — a `with_cache` helper appends the policy headers; the tag-vs-digest flag passed to the manifests handler was initially inverted (digest-valid ≠ by-tag), caught by the tests.

#### T2.16 Tag Listing and Pagination

**Goal**: Implement `GET /v2/<name>/tags/list`, returning tags in lexical order with `n` and `last` pagination and a `Link` header when more pages exist.

**Deliverables**: routes, pagination logic, and tests.

**Acceptance**: An empty repository returns an empty list; pagination boundaries are correct; a missing `last` starts from a sensible position; pull permission is required; the response follows the OCI spec.

**Depends on**: T2.12 · **Estimate**: 2h

> **Notes** (2026-11-19, ~1.5h): Done. New `registry/tags.emo` serves `GET /v2/<name>/tags/list`: the tags in lexical order (`ORDER BY tag` in the new `db.list_tags_page`, which fetches limit+1 rows to answer the more-flag without a second query), `{"name","tags"}` JSON, `n` / `last` pagination where `last` is a tag **value** the page starts after exclusively, and `Link: </v2/<name>/tags/list?n=<n>&last=<last>; rel="next"` on a full page with more tags (relative URI-reference; the last page and any listing without `n` carry no Link). `n=0` answers an empty list with no Link; a non-numeric/negative `n` is 400 `TAG_INVALID`; a missing repository is 404 `NAME_UNKNOWN`; an existing repository without tags answers an empty list; other methods 405. The query reads the live table, so tag updates are visible on the next page by construction. Auth rides the gate: the listing needs `repository:<name>:pull` (added to `required_access`). Service gained `tags TagList` (interface + `DbTagList`), so the seven router-test files gained a tags fake. Tests: 16 in `test/registry_tags.emo` (shapes, full listing, empty/missing repository, page boundaries with the Link format, tail page, `n=0`, invalid `n`, methods, auth 401/pass legs) + 8 db_selftest checks pinning the SQL semantics (lexical order, exclusive `last`, more flag, empty page); `emo test` 481/481, db selftest 122/122. Manually verified over the wire: five tags listed lexically, `?n=2` carries the exact Link, `?n=2&last=v2` answers `v3,v4`. Gotchas: Emo has no string-ordering operators — the fake pages by locating `last` by equality (the SQL handles the general case), and the T2.7 unknown-route example happened to be `/tags/list`, now a real route.

#### T2.17 Deployment: Registry + MinIO + Caddy

**Goal**: Provide reproducible deployment: a multi-stage build for the Emo binary, a runtime image with the required shared libraries, and Compose services for the registry, MinIO, and Caddy; configure volumes, health checks, TLS, and `.env.example`.

**Deliverables**: `deploy/Dockerfile`, `deploy/compose.yaml`, `deploy/Caddyfile`, `.env.example`, and deployment docs.

**Acceptance**: On a clean machine, `docker compose up -d` brings all three services up in a healthy state; the registry is reachable through Caddy; MinIO data persists; a restart loses no data; `.env.example` contains no real secrets.

**Depends on**: T2.6, T2.14 · **Estimate**: 3h

> **Notes** (2026-11-19, ~2.5h): Done, with one environment caveat. `deploy/` holds the stack: a two-stage `Dockerfile` (stage 1 compiles the registry with the Emo toolchain via the `EMO_BUILDER_IMAGE` build argument — the toolchain is young, so until a builder image is published the argument names an image of your own; stage 2 is `debian:bookworm-slim` with `libsqlite3-0` — the c target links it — plus `wget` for the healthcheck, a non-root user, and the image-level HEALTHCHECK against /healthz), `deploy/registry-entrypoint.sh` (PID 1 turns SIGTERM/SIGINT into the shutdown marker the server watches — Emo has no signal handlers — and waits for the drain), `deploy/compose.yaml` (registry + MinIO + Caddy, internal network, named volumes for metadata/objects/certificates, MinIO's healthcheck gating the registry, the registry's gating Caddy, values from `.env` with `:?` refusals for the four secrets), `deploy/Caddyfile` (one site reverse-proxying the registry, automatic Let's Encrypt for a public domain / internal CA for localhost, cache headers passing through untouched), `.env.example` (placeholders only, generation hints), and `docs/registry/deployment.md`. **Verified on the host**: the entrypoint's signal protocol end to end (SIGTERM → marker → the server's `shutting down` / `stopped` drain lines → clean exit) — the first cut exited early because a trapped signal interrupts shell `wait`, so the reap now loops until the server is really gone (leaving early cancels the drain); `docker compose config` validates the stack definition; the binary's link surface checked (`libsqlite3` only). **Caveat**: the full `docker compose up` could not run on this machine — the MinIO and Caddy images are unreachable (Docker Hub via the dead proxy and the configured mirror both time out; the same limitation as T2.6's S3 notes). On a machine with registry access, `cd deploy && cp ../.env.example .env && docker compose up -d` is the verification, and T2.19's smoke script exercises the stack end to end.

#### T2.18 Observability and Audit Logging

**Goal**: Add structured logging (`slog` JSON), request ids, access logs, auth audit events, and Prometheus text metrics; never log tokens, Authorization headers, or presigned query strings.

**Deliverables**: logging middleware, `/metrics`, audit events, and tests.

**Acceptance**: Every request has a request id; logs parse with `jq`; metrics include request count, latency, error count, and upload / download bytes; auth failures are audited; sensitive fields are redacted.

**Depends on**: T2.1 · **Estimate**: 2-3h

#### T2.19 Protocol Smoke and Conformance Tests

> **Notes** (2026-11-19, ~2.5h): Done. `registry/metrics.emo` + migration 3: counters live in SQLite (`metrics(name, value)`) because httpd runs one process per connection — each request bumps its series with UPSERTs in one short transaction **after** the response is built (a failing database cannot fail a request that already succeeded), and `/metrics` renders the Prometheus text format: requests total, errors (4xx+5xx), upload/download bytes, and a latency histogram over the standard edges with cumulative buckets, `_sum` (seconds), and `_count`; a fresh store renders a full zeros document. The router emits one slog JSON access line per request (ts, request id — the same one the response header echoes, method, path, status, duration, byte counts; never the query, headers, or bodies, so no token or presigned signature can leak) and a `warn` audit record per authentication failure (`event=auth_failure` + reason; reasons name states, not credentials). New `observability:` config section (access_log / metrics, both default on) with `POKERFACE_REGISTRY_ACCESS_LOG` / `_METRICS` env overrides, summary switches, and strict unknown-field checks. `/metrics` is public (counts only) and GET-only. The metrics sink is an interface (`Sink`: record + render) so the interpreter tests run against fakes while `DbSink` rides sqlite3. Tests: 9 in `test/registry_metrics.emo` (bucket edges, route grouping, the endpoint's public/text/405 shape, per-request recording, auth-failure recording, config defaults/env/unknown/summary) + 13 db_selftest checks (UPSERT accumulation across bumps, cumulative buckets, the seconds-shaped sum, fresh-store zeros, every edge present); `emo test` 488/488, db selftest 135/135. Manually verified: four requests produce `pokerface_requests_total 4` / `errors_total 2` / `download_bytes_total 96`, every access line parses as JSON, and an auth-enabled instance writes `auth_failure` audit records. Gotchas: E3009 again — the sqlite-backed paths (record and render) must sit behind the Sink interface for the interpreter; `(R, …)` error slots are Strings, shaping the earlier gate refactor the same way; slog's `level_info`/`format_json` are FUNCTIONS, not constants.

**Goal**: Validate the registry with real clients: push with `oras` or `skopeo`, pull with `pokerface`, download presigned blobs, and exercise negative auth cases; turn this into a repeatable smoke script.

**Deliverables**: `scripts/e2e-m2.sh`, test image fixtures, and test documentation.

**Acceptance**: The script starts compose from a clean environment, completes push / pull / verification, and cleans up; failures emit actionable logs; it does not contact Docker Hub; it covers 401, 404, and digest-mismatch paths.

**Depends on**: T2.1-T2.18 · **Estimate**: 3h

> **Notes** (2026-11-19, ~3h): Done. `scripts/e2e-m2.sh` drives the REAL registry service (fs backend, fresh temp dir per run, 127.0.0.1 only — nothing contacts Docker Hub): skopeo pushes an image assembled from `test/fixtures/oci`, the manifest read-back by tag compares `Docker-Content-Digest` AND the exact bytes, the tags list asserts the lexical order and the exact `Link` header, `/api/v1/resolve` answers digest + platform, blob caching asserts the digest ETag, the immutable policy, and the 304, the negative set covers unknown tag/blob (404) and a digest-mismatch push (400), the pokerface CLI resolves from a local Git lock and pulls into the detected container runtime, and the auth leg restarts the registry with auth enabled — anonymous reads challenged, `skopeo login` + push succeed, a pull-only token cannot push (`insufficient_scope` in the challenge). Verified twice consecutively (re-runnable), zero residual processes or temp dirs, and `e2e-m1.sh` still passes alongside. Gotchas that cost real time: the server ignores SIGTERM by design, so a stop-by-signal hangs the runner forever — stop through the shutdown marker (the entrypoint's protocol); `curl -f` turns the EXPECTED 401 challenges into exit 22 under `set -e` (capture headers without `-f`); wire headers end CRLF, so grep line anchors need a CR strip first; the c runtime's idle worker processes hold pipes open — run this script redirected to a file, never piped (documented in the header).

## 6. M4: Build, CI, and Delivery

### 6.1 Goal and Exit Criteria

Complete the build side and delivery artifacts: `pokerface build`, image push, lock write-back, CI templates, install script, docs site, example application, and an end-to-end demo.

Exit criteria:

- The example repository builds, pushes, and writes `pokerface.lock.yaml` via `pokerface build --push`.
- The GitHub Actions template is reusable and does not create an infinite commit loop.
- The docs site covers installation, quick start, CLI, configuration, protocols, and operations.
- `scripts/e2e.sh` runs `build -> push -> resolve -> pull -> run` in a clean environment.
- The README (English and Chinese) matches the actual state.

### 6.2 Task Overview

| Status | ID | Task | Depends on | Estimate |
| --- | --- | --- | --- | --- |
| [x] | T4.1 | `pokerface build` command and build plan | T1.4, T1.5 | 2h |
| [x] | T4.2 | BuildKit / podman build adapter | T4.1 | 3-4h |
| [x] | T4.3 | Registry push: blobs + manifest | T1.10, T2.12, T4.2 | 3h |
| [x] | T4.4 | Generate and write back the lock file | T4.3 | 2h |
| [ ] | T4.5 | Build trigger and versioning strategy ADR | none | 1h |
| [ ] | T4.6 | CI template: GitHub Actions first | T4.3, T4.4 | 3h |
| [ ] | T4.7 | Install script and release workflow | T1.1 | 3h |
| [ ] | T4.8 | Docs site skeleton and navigation | T4.5 | 2-3h |
| [ ] | T4.9 | Quick start and installation guide | T4.7, T4.8 | 2h |
| [ ] | T4.10 | CLI and configuration reference | T1.1, T1.8 | 2h |
| [ ] | T4.11 | YAML / lock / metadata specification | T1.4, T1.5 | 3h |
| [ ] | T4.12 | Registry operations guide | T2.17 | 3h |
| [ ] | T4.13 | Example application | T4.2, T4.3 | 3h |
| [ ] | T4.14 | End-to-end demo script | T4.3, T4.13, T1.14 | 3h |
| [ ] | T4.15 | Failure fallback and troubleshooting matrix | T1.14, T2.19 | 2h |
| [ ] | T4.16 | README, Chinese edition, and release checklist | T4.8-T4.15 | 2h |
| [ ] | T4.17 | CI end-to-end regression | T4.14 | 3h |

### 6.3 Task Details

#### T4.1 `pokerface build` Command and Build Plan

**Goal**: Read `pokerface.yaml`, validate the configuration and context, render tag templates, and produce a build plan that `--dry-run` prints: image name, tags, platforms, build args, Dockerfile, and context.

**Deliverables**: `src/commands/build.emo`, a tag renderer, and dry-run tests.

**Acceptance**: Example configuration output is stable; a missing Dockerfile, missing context, or duplicate tags produce errors; `--dry-run` performs no build or network requests; `--platform` can override.

**Depends on**: T1.4, T1.5 · **Estimate**: 2h

> **Notes** (2026-11-19, ~2.5h): Done. `src/build.emo` holds the plan model (`GitMetadata`, `BuildPlan`), the tag renderer (manual `{{`/`}}` scanning — `String.index_of` takes no start index), the collision check (two distinct templates rendering the same string collide, error names both positions: `tags[1] ('{{ git.tag }}') collides with tags[0]`), the Git capture (rev-parse/describe run in the CONTEXT directory; exact-match describe failure = not tag-triggered, `""`), and `plan()` with the shared `context_dir` resolution (relative to the config file's dir; a `.` context joins to `/.` and the tail is dropped). `src/commands/build.emo` composes read → parse (`src.config.load` — the BUILD config, never `src.settings.load`, which would reject it as the client config.yaml with unknown fields) → context check → Git capture → plan → Dockerfile check → print; `compose_plan` + `plan_text` split out (the T1.14 resolve precedent) so the tests assert the exact lines `print_plan` printlns without stdout interception. Discovery: `--config` > `./pokerface.yaml` (cwd; `os.getcwd()` returns a bare String). Empty render (a lone `{{ git.tag }}` untagged) funnels through the charset check — one rejection shape, "renders to an invalid tag". Without `--dry-run` is a usage error until T4.2. Router gotcha: `route()` rejected every unknown `--` option after any command but pull/cache, so `build --dry-run` never reached the command — build joined the per-command parse list. Verified: 12 tests (renderer/collisions/metadata/plan/command), `emo test` 500/500, c target builds, and the compiled binary driven end to end (cwd discovery, `--config`, `--json`, `--platform` override, exit codes 2/1 for usage/validation). Spec: `docs/spec/build-plan.md`. Follow-ups: T4.2 consumes `BuildPlan`; T4.10 folds this into the CLI reference.

#### T4.2 BuildKit / Podman Build Adapter

**Goal**: Wrap the local build tool. Prefer Docker BuildKit `buildx build --output type=oci`; use podman as a fallback. Write standard OCI labels: `org.opencontainers.image.revision`, `source`, `version`, and `created`.

**Deliverables**: `src/build.emo`, tool detection, streamed log output, and build tests.

**Acceptance**: The example Dockerfile builds into an OCI layout; `inspect` shows the commit / source labels; build failures surface the original log and exit code; missing BuildKit produces a clear message; multi-platform builds are optional and do not break single-platform builds.

**Depends on**: T4.1 · **Estimate**: 3-4h

> **Notes** (2026-11-20, ~3h): Done. `src/build.emo` grows the adapter: `detect_tool` (buildx docker first — `docker buildx version` — podman fallback; neither → `runtime: no build tool found`, exit 8), `buildx_argv` (one `buildx build` invocation: all platforms at once, every tag as `--tag` so index.json carries one descriptor per tag, `--provenance=false --sbom=false` to keep the layout to the requested manifests, `--output=type=oci,dest=<work>/build.tar`, context last), `podman_argv` + save (`podman build --format=oci`, then `podman save --format=oci-dir` — one tag, push applies the rest), and `execute()` (docker: buildx tar + `tar -xf`; layout validated via `src.oci.validate` + `read_index` before answering). `RealStreamRunner` forks with inherited stdout/stderr so the build log streams live (same double-fork watchdog as git's RealRunner; only the exit code crosses back, so `pokerface: build: 'docker' exited with code 1` rides under the original log). `GitMetadata` gains the full SHA (rev-parse HEAD, short derived — the c target REJECTS conditional field assignment in init, so commit_short stays an init parameter) and the origin URL (the source label, omitted when there is no origin). `created` is injected into execute() (`rfc3339_now()` at the command, fixed in tests — keeps the fakes' argv pins deterministic). Work dir: `<TMPDIR>/pokerface-build-<pid>/`. `pokerface build` (no --dry-run) now composes, checks, executes, and reports tool/layout/digests/tags. Verified on the host with the real docker (buildx v0.38.1, daemon 29.9.3): FROM-scratch repo builds offline into a validated layout; `skopeo inspect --config` shows `revision` = full SHA, `source` = origin, `created` = RFC3339; digest matches the CLI's report; a broken Dockerfile surfaces buildx's ERROR block and exits 1; `--platform linux/amd64,linux/arm64` produces a clean 2-manifest index. Podman path is fake-tested only — podman is not installed here (the T2.17 caveat pattern). Tests: 10 new (detection ×3, argv shapes ×3, rfc3339, execute docker/podman/failure with a REAL fixture-assembled layout behind the fakes); `emo test` 510/510, c target builds. Gotchas: the e2e pipe hang hit again — piping the CLI's stdout stalls on the idle scheduler workers (redirect to a file, documented in e2e-m2.sh); the "timeout" word in an error message classifies as network (reworded to "limit"). Spec: docs/spec/build-plan.md "Execution (T4.2)".

#### T4.3 Registry Push: Blobs + Manifest

**Goal**: Reuse the M1 registry client to upload blobs (single and chunked), push manifests, update tags, and capture digests with retries.

**Deliverables**: `src/push.emo`, push tests, and progress output.

**Acceptance**: Push to the M2 registry succeeds; the returned digest matches the local digest; repeat pushes skip existing blobs; mid-flight failures can retry without corrupting existing tags; auth scopes are correct.

**Depends on**: T1.10, T2.12, T4.2 · **Estimate**: 3h

> **Notes** (2026-11-20, ~4h): Done. `src/push.emo` is the pipeline: split the image (reuse pull's `split_image` — image host is the endpoint, loopback http / else https) → client probe → blob HEAD (200 skips, no bytes read) → uploads (single `POST ?digest=` under 4 MiB; a session of 4 MiB PATCH chunks with the spec's bare Content-Range above) → manifests by digest → tags. Two findings shaped it. **The HEAD gap**: the std http client reads a HEAD response's declared Content-Length as a body and dies with "closed after 0 of N bytes" — the registry's HEAD answers are spec-correct, so HEAD moved to its own transport (`HeadTransport` + `RealHeadTransport`: HTTP/1.1 over `net`, headers only, reusing blob.emo's URL parser and response-head reader; injectable for tests). **Child manifests are manifests, not just blobs**: the M2 index validation checks children against the MANIFESTS table, and real clients PUT child manifests by digest before the index — so every layout descriptor goes out as `/manifests/<digest>` (recursively for buildx's nested multi-platform wrapper), buildx's one-descriptor-per-tag index.json is deduped by digest, and the tag target is the manifest for single-platform layouts / the index otherwise. The registry's `Docker-Content-Digest` must equal the pushed bytes' local sha256 (mismatch = integrity exit 7); transport errors and 5xx retry 3×; a 401 dances with `repository:<repo>:pull,push` and replays once. Progress streams through a `Progress` interface (`StdoutProgress`/`SilentProgress` for --json). `pokerface build` now pushes when pokerface.yaml has a `registry` section (token from `POKERFACE_REGISTRY_TOKEN`/config — the `--config` flag names the BUILD file, never the client config, so settings.load runs flagless). Registry side: `/api/v1/resolve`'s platform walk recurses nested indexes (depth 4) and takes a platformless manifest child's platform from its config — buildx's wrapper no longer answers an empty platform. **Verified against the real registry end to end**: single-platform push digest == served `Docker-Content-Digest` == skopeo's read-back; repeat push skips the deterministic layer; multi-platform push serves a clean 2-platform index and resolve answers both platforms; auth leg with a minted push-scope token succeeds, a pull-only token is rejected with the registry's own envelope (exit 5), and no token fails the dance clearly; `e2e-m2.sh` still passes. Tests: 9 new in `test/push.emo` (RecTransport + RecHeadTransport with per-rule call budgets) + 2 resolve nested-index tests; `emo test` 519/519, c target builds. Known follow-ups: Basic username/password → /token exchange in the client (today a token is provided out of band); the interpreter's 6-tuple deep-nesting and the manifest `Subject` field are untouched. Spec: docs/spec/push.md; build-plan.md's execution section updated.

#### T4.4 Generate and Write Back the Lock File

**Goal**: After a successful build and push, generate `pokerface.lock.yaml` with the commit, image, tags, digest, platforms, and builder. Support `--write-lock` and an optional `--commit` that only creates a local Git commit and never pushes.

**Deliverables**: a lock generator, merge logic, and tests.

**Acceptance**: Rebuilding the same image produces an idempotent lock; multi-tag and multi-platform entries sort stably; unrelated entries are preserved; no real secrets are written; `pokerface resolve` consumes the generated lock directly.

**Depends on**: T4.3 · **Estimate**: 2h

> **Notes** (2026-11-20, ~2h): Done. `src/lockfile.emo` grows the generation side: `entry_for` (tags/platforms sorted lexically — strings have no order operators, so `text_less` walks bytes through a sort charset; the digest is checked with the loader's own rule), `merge` (same-image entry replaced IN PLACE, absent entries appended, unrelated entries untouched, `generated_at` forced empty so the same inputs encode byte-identically), and `fresh_doc`. `pokerface build --write-lock` writes `pokerface.lock.yaml` next to pokerface.yaml after the push (it requires a registry section — the lock records the pushed digest): `commit` = the full SHA the image was built from, `source` = the origin remote normalized via the loader's `parse_source` (a repository without an origin errors — the source is required), `builder` = buildkit/podman mapped from the adapter's tool. An existing lock merges; one that does not parse is an error, never a silent clobber. `--commit` stages and commits ONLY the lock (`git add --` + `git commit -- pokerface.lock.yaml`, message `pokerface: update pokerface.lock.yaml` — a pathspec commit, so no other staged or modified file rides along) and never pushes; `--commit` without `--write-lock` is a usage error. No secrets: the schema has no credential-bearing field. Verified end to end against the real registry: the written lock's shape (sorted tags/platforms, builder line, unrelated entry preserved, entry replaced in place on the second run), the lock commit touching only `pokerface.lock.yaml`, and `pokerface resolve <repo>:main` consuming the committed lock straight to image+digest. Idempotency nuance: the lock's SHAPE is stable across rebuilds (encode/load/merge cycle pinned by `test_rebuild_is_idempotent`), but the digest legitimately changes per build because buildx stamps `created` — noted in the spec rather than papered over. Tests: 6 new in `test/lockfile.emo`; `emo test` 525/525, c target builds. Spec: pokerface-lock.md "Generation (T4.4)" + build-plan.md "Lock write-back".

#### T4.5 Build Trigger and Versioning Strategy ADR

**Goal**: Define v0.1 build triggers: Git push / tag / CI `workflow_dispatch`; no self-hosted webhook service. Define tag rules (default branch `latest`, Git tags verbatim, short commit SHA, semantic versions).

**Deliverables**: `docs/adr/0001-build-trigger.md` and a versioning policy document.

**Acceptance**: The ADR records the context, alternatives, and trade-offs; CI templates follow the tag rules; the document explicitly defers polling / self-hosted webhooks to a later version.

**Depends on**: none · **Estimate**: 1h

#### T4.6 CI Template: GitHub Actions First

**Goal**: Provide a reusable workflow: checkout, install pokerface, log in to the registry, run `pokerface build --push --write-lock`, and commit the lock back to the repository. Add minimal GitLab CI / Gitea Actions examples.

**Deliverables**: `.github/workflows/publish.yaml`, `docs/ci/github-actions.md`, and GitLab / Gitea examples.

**Acceptance**: The workflow passes `actionlint`; the example repository runs it successfully; the lock commit uses `[skip ci]` or path filters to avoid a loop; secrets are never written to disk; permissions are minimized.

**Depends on**: T4.3, T4.4 · **Estimate**: 3h

#### T4.7 Install Script and Release Workflow

**Goal**: Provide `install.sh` and a release process: detect OS / architecture, download the matching binary, verify the checksum, and install it on `PATH`; the release workflow cross-compiles Linux / macOS amd64 / arm64 artifacts.

**Deliverables**: `install.sh`, `.github/workflows/release.yaml`, checksum files, and installation docs.

**Acceptance**: `curl ... | sh` installs successfully in a clean container; `pokerface version` matches the release; a checksum mismatch aborts installation; the script uses safe temp-file permissions.

**Depends on**: T1.1 · **Estimate**: 3h

#### T4.8 Docs Site Skeleton and Navigation

**Goal**: Build the docs site with Getting Started, CLI, Configuration, Spec, Registry, Examples, and Troubleshooting. Start with plain Markdown + GitHub Pages; add VitePress only when search is needed.

**Deliverables**: a `docs-site/` or `docs/` site configuration, navigation, landing page, and deployment workflow.

**Acceptance**: Local preview works; navigation has no dead links; mobile layout is readable; deployment to GitHub Pages succeeds; source Markdown stays under `docs/` for review.

**Depends on**: T4.5 · **Estimate**: 2-3h

#### T4.9 Quick Start and Installation Guide

**Goal**: Let a new user install, run `pokerface resolve`, `pokerface pull`, and `docker run` within 10 minutes. State prerequisites clearly: Git, skopeo, Docker / podman.

**Deliverables**: `docs/getting-started.md`, copy-pasteable commands, expected output, and common failure hints.

**Acceptance**: Following the guide works in a clean environment; commands match the current CLI; key sections are mirrored in Chinese; the guide explicitly says Docker Hub is not required.

**Depends on**: T4.7, T4.8 · **Estimate**: 2h

#### T4.10 CLI and Configuration Reference

**Goal**: Document every command, flag, environment variable, config field, and exit code; generate from or validate against `--help` output where possible.

**Deliverables**: `docs/reference/cli.md`, `docs/reference/config.md`, and help-text snapshot tests.

**Acceptance**: Docs cover every command; defaults are accurate; exit codes match `docs/spec/errors.md`; CI warns when help text changes without a docs update.

**Depends on**: T1.1, T1.8 · **Estimate**: 2h

#### T4.11 YAML / Lock / Metadata Specification

**Goal**: Turn `pokerface.yaml`, `pokerface.lock.yaml`, and manifest metadata into a formal spec: fields, types, validation rules, version compatibility, examples, and OCI field mappings.

**Deliverables**: `docs/spec/pokerface-yaml.md`, `docs/spec/pokerface-lock.md`, a JSON Schema (optional but recommended), and examples.

**Acceptance**: All examples validate against the schema; the spec covers unknown fields and version upgrades; validation matches the implementation; review finds no ambiguity.

**Depends on**: T1.4, T1.5 · **Estimate**: 3h

#### T4.12 Registry Operations Guide

**Goal**: Guide operators who self-host the registry: Compose deployment, S3/MinIO configuration, CDN integration, TLS, authentication, backup, blob cleanup, capacity and monitoring, and a security checklist.

**Deliverables**: `docs/registry/operations.md`, deployment examples, and a troubleshooting checklist.

**Acceptance**: The guide enables a from-scratch deployment; CDN cache policy matches the code; backup / restore steps are executable; it includes a warning never to expose MinIO credentials.

**Depends on**: T2.17 · **Estimate**: 3h

#### T4.13 Example Application

**Goal**: Provide a minimal example: a Dockerfile, `pokerface.yaml`, and a reachable HTTP service that demonstrates Git metadata, build, push, and pull.

**Deliverables**: `examples/hello/`, an example README, expected image size, and a run command.

**Acceptance**: `pokerface build --push --write-lock` succeeds; `pokerface pull` followed by a container run returns 200; the image contains no build cache or secrets; the example can feed the CI template.

**Depends on**: T4.2, T4.3 · **Estimate**: 3h

#### T4.14 End-to-End Demo Script

**Goal**: Demonstrate the full path with one command: start the local registry / MinIO, build the example, push, write the lock, `resolve`, `pull`, run the container, and assert the HTTP response.

**Deliverables**: `scripts/e2e.sh`, a `--ci` mode, and logging / cleanup logic.

**Acceptance**: One command succeeds on a clean machine; failures preserve diagnostic logs; no Docker Hub access; the run completes in reasonable time (target under 10 minutes); repeated runs leave no residue.

**Depends on**: T4.3, T4.13, T1.14 · **Estimate**: 3h

#### T4.15 Failure Fallback and Troubleshooting Matrix

**Goal**: Turn the README failure fallbacks into executable documentation and verify each: Git failure, manifest failure, CDN failure, digest mismatch, runtime import failure, and cache corruption.

**Deliverables**: `docs/troubleshooting.md`, a fallback matrix, diagnostic commands, and test records.

**Acceptance**: Every scenario has four sections: symptom / cause / handling / verification; documented behavior matches the implementation; offline mode and cache cleanup steps are included.

**Depends on**: T1.14, T2.19 · **Estimate**: 2h

#### T4.16 README, Chinese Edition, and Release Checklist

**Goal**: Update the README's project status, Quick Start, Roadmap checkboxes, and links; sync `README.zh-CN.md`; create a release checklist (version, changelog, tag, install script, rollback).

**Deliverables**: updated `README.md` / `README.zh-CN.md`, `RELEASE.md`, and `CHANGELOG.md`.

**Acceptance**: English and Chinese content correspond one-to-one; commands are copy-pasteable; Roadmap checkboxes match reality; the checklist covers versioning and tag rules; no stale screenshots or links.

**Depends on**: T4.8-T4.15 · **Estimate**: 2h

#### T4.17 CI End-to-End Regression

**Goal**: Run the end-to-end path regularly in CI to catch regressions in the registry, CLI, and build scripts. Support manual and daily scheduled runs.

**Deliverables**: `.github/workflows/e2e.yaml`, caching strategy, and failure-log artifacts.

**Acceptance**: CI passes on the main branch; runtime stays under 15 minutes; failures upload compose and CLI logs; the E2E run does not contact Docker Hub; required base images are pre-cached or built locally, with pinned sources in the workflow.

**Depends on**: T4.14 · **Estimate**: 3h

## 7. Suggested Execution Order

Recommended order for a solo developer; the parallelizable work below can fill gaps while waiting for CI or review.

1. **Contract phase**: T1.1 -> T1.2 -> T1.3 -> T1.4 -> T1.5. Lock down the CLI, reference syntax, and both YAML specs first.
2. **Client resolution loop**: T1.6 -> T1.7 -> T1.8 -> T1.9 -> T1.16. `resolve` becomes usable here.
3. **Client pull loop**: T1.10 -> T1.11 -> T1.12 -> T1.13 -> T1.14 -> T1.15 -> T1.17.
4. **Server MVP**: T2.1 -> T2.2 -> T2.3 -> T2.4 -> T2.5 -> T2.6 -> T2.7 -> T2.8 -> T2.9 -> T2.10 -> T2.11 -> T2.12 -> T2.14 -> T2.13 -> T2.15 -> T2.16 -> T2.18 -> T2.17 -> T2.19.
5. **Build and delivery**: T4.1 -> T4.2 -> T4.3 -> T4.4 -> T4.5 -> T4.6 -> T4.7.
6. **Docs and end-to-end**: T4.8 -> T4.9 -> T4.10 -> T4.11 -> T4.12 -> T4.13 -> T4.14 -> T4.15 -> T4.16 -> T4.17.

Parallelizable work:

- Once T1.4 / T1.5 are final, M2's T2.2 / T2.3 can start early.
- T4.5 / T4.8 / T4.10 / T4.11 can run alongside M2.
- T1.15's cache and T1.16's error model are off the critical path; slot them into spare time while builds or reviews run.

Critical path: `T1.2 -> T1.5 -> T1.10 -> T1.13 -> T1.14 -> T2.17 -> T4.3 -> T4.14`.

## 8. Risks and Open Questions

| Risk | Impact | Mitigation |
| --- | --- | --- |
| The Emo `http` client does not follow redirects and reads response bodies fully into memory | Large layer downloads may consume excessive memory; 307s must be handled manually | Verify in T1.2; if needed, implement streaming downloads and redirect handling on top of `net` in T1.11 |
| S3 SigV4 has many implementation details | Presigned URLs fail and block blob pulls | Use official test vectors in T2.5; integrate with MinIO first; keep the local filesystem backend + direct streaming as a development mode |
| `skopeo` is not available everywhere | `pull` cannot import into Docker | Detect tools and give clear guidance in T1.13; document installation; consider built-in import in a later version |
| Limited OCI client compatibility | `oras` / `skopeo` pushes fail | Smoke-test with real clients in T2.19; fix issues one by one instead of chasing full spec coverage at once |
| CDN caching hides tag updates | Clients pull a stale manifest | Use short caching / `no-cache` + ETag in T2.15; reserve long caching for blobs |
| Large Git repositories or fetch restrictions | `resolve` is slow or fails | Use bare mirrors + shallow fetches; fetch only the lock file when possible; make cache TTL configurable |
| Proxy or network interference | Requests are hijacked or time out | Use your own domains end to end; log the actual request host; assert no Docker Hub access in E2E |
| Multi-architecture complexity | Platform selection fails during build or pull | Ship single-platform first in v0.1; parse indexes in T1.10; treat multi-platform as optional in T4.2 |

## 9. MVP Acceptance Checklist

- [ ] `pokerface resolve` outputs `tag -> commit -> digest`.
- [ ] `pokerface pull` downloads, verifies, and imports; `docker run` / `podman run` works.
- [ ] Pulling never contacts `registry-1.docker.io`.
- [ ] The registry starts with a single compose command, and MinIO data persists.
- [ ] The required OCI manifest / blob / tag endpoints work and pass an `oras` or `skopeo` smoke test.
- [ ] Blobs download through presigned URLs and the URLs expire.
- [ ] Pull / push scopes are enforced; unauthorized requests are rejected.
- [ ] `pokerface build --push --write-lock` builds, pushes, and writes metadata back.
- [ ] The CI template works and does not create a commit loop.
- [ ] The example application runs end to end with `scripts/e2e.sh`.
- [ ] The docs site covers installation, quick start, CLI, specifications, registry operations, and troubleshooting.
- [ ] The English and Chinese READMEs stay in sync, and the Roadmap matches reality.
