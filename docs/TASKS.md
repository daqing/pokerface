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
| [ ] | T1.12 | Assemble an OCI image layout | T1.10, T1.11 | 2-3h |
| [ ] | T1.13 | Runtime import adapter | T1.12 | 3h |
| [ ] | T1.14 | Wire up the `pull` command and failure fallbacks | T1.9-T1.13 | 3h |
| [ ] | T1.15 | Local cache and offline mode | T1.7, T1.14 | 2-3h |
| [ ] | T1.16 | Error model, exit codes, and logging | T1.1 | 2h |
| [ ] | T1.17 | M1 test baseline, E2E script, and spec docs | T1.1-T1.16 | 2-3h |

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

#### T1.13 Runtime Import Adapter

**Goal**: Import the OCI layout into the local runtime. Prefer `skopeo copy oci:<dir> docker-daemon:<image>:<tag>`; use `containers-storage:` for podman and `oci-archive` + `ctr images import` for containerd. Detect available tools and provide clear guidance.

**Deliverables**: `src/runtime.emo`, a support matrix, and tests for command construction and error mapping.

**Acceptance**: The Docker + skopeo path works; the podman path works; Docker without skopeo produces a clear installation hint; failed imports leave no partial image; temp files are cleaned up.

**Depends on**: T1.12 · **Estimate**: 3h

#### T1.14 Wire Up the `pull` Command and Failure Fallbacks

**Goal**: Chain `resolve -> manifest -> blob -> verify -> OCI layout -> runtime import`. Implement the README fallbacks: a Git failure is a hard error; a manifest failure falls back to the local cache; a CDN failure retries per blob; an import failure cleans up temp files.

**Deliverables**: `src/commands/pull.emo`, integration tests against a local registry, and `--platform` / `--tag` / `--keep-temp` / `--offline` options.

**Acceptance**: An end-to-end pull followed by `docker run` succeeds; a manifest fetch failure can still complete from cache (the cached digest must match); a corrupted blob is never imported; an import failure leaves no temp directory behind; packet captures or proxy logs show no Docker Hub requests.

**Depends on**: T1.9-T1.13 · **Estimate**: 3h

#### T1.15 Local Cache and Offline Mode

**Goal**: Manage the Git mirror, manifest, and blob caches in one place; add TTL, size limits, cleanup, and verification commands; support `--offline` to use only the cache.

**Deliverables**: `src/cache.emo`, `pokerface cache ls` / `cache rm` / `cache verify`, and cache tests.

**Acceptance**: A second pull works offline; corrupted cache entries are detected and evicted; the size limit is enforced; `cache rm` never deletes non-pokerface directories; concurrent reads and writes are safe.

**Depends on**: T1.7, T1.14 · **Estimate**: 2-3h

#### T1.16 Error Model, Exit Codes, and Logging

**Goal**: Define stable error categories and exit codes. Human-facing errors include a next step; machine-facing results are consumable via `--json`. Logs are quiet by default; `--verbose` adds request / command detail without leaking tokens.

**Deliverables**: `docs/spec/errors.md`, `src/errors.emo`, and table-driven tests.

**Acceptance**: Usage, Git, metadata, authentication, network, integrity, and runtime errors each have a fixed exit code; error output includes actionable remediation; `--verbose` redacts tokens, Authorization headers, and presigned URL query strings.

**Depends on**: T1.1 · **Estimate**: 2h

#### T1.17 M1 Test Baseline, E2E Script, and Spec Docs

**Goal**: Fill in M1's tests and docs so later changes have regression coverage. Use local fixture Git repositories plus Emo-based mock registry / CDN services to cover the full path.

**Deliverables**: `scripts/e2e-m1.sh`, the mock services, a summary of the YAML / lock / config / errors specs under `docs/spec/`, and an M1 usage example in the README (English and Chinese kept in sync).

**Acceptance**: `emo test` passes; `scripts/e2e-m1.sh` is repeatable in a clean temp directory; it does not depend on the real Docker Hub; documented commands match actual output.

**Depends on**: T1.1-T1.16 · **Estimate**: 2-3h

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
| [ ] | T2.1 | Service skeleton, configuration, and health checks | T1.2 | 2h |
| [ ] | T2.2 | SQLite data layer and migrations | T2.1 | 2-3h |
| [ ] | T2.3 | OCI manifest / index model and validation | T1.5 | 2-3h |
| [ ] | T2.4 | BlobStore interface and local filesystem backend | T2.1 | 2h |
| [ ] | T2.5 | AWS SigV4 signing and presigned URLs | T2.1 | 3h |
| [ ] | T2.6 | S3 / MinIO BlobStore adapter | T2.4, T2.5 | 3h |
| [ ] | T2.7 | `/v2/` base protocol and error format | T2.1, T2.2 | 1-2h |
| [ ] | T2.8 | Manifest GET / HEAD and tag / digest resolution | T2.2, T2.3, T2.7 | 3h |
| [ ] | T2.9 | Blob GET and 307 presigned redirect | T2.4, T2.6, T2.8 | 2-3h |
| [ ] | T2.10 | Blob upload: POST / PUT | T2.4, T2.7 | 3h |
| [ ] | T2.11 | Chunked upload and resumable transfers: PATCH / GET / DELETE | T2.10 | 3h |
| [ ] | T2.12 | Manifest PUT and tag updates | T2.3, T2.10, T2.11 | 2-3h |
| [ ] | T2.13 | Resolve / metadata API | T2.8, T2.12 | 2h |
| [ ] | T2.14 | Authentication and token service | T2.7 | 3-4h |
| [ ] | T2.15 | Cache headers, ETag, and CDN behavior | T2.8, T2.9 | 2h |
| [ ] | T2.16 | Tag listing and pagination | T2.12 | 2h |
| [ ] | T2.17 | Deployment: registry + MinIO + Caddy | T2.6, T2.14 | 3h |
| [ ] | T2.18 | Observability and audit logging | T2.1 | 2-3h |
| [ ] | T2.19 | Protocol smoke and conformance tests | T2.1-T2.18 | 3h |

### 5.3 Task Details

#### T2.1 Service Skeleton, Configuration, and Health Checks

**Goal**: Create the registry service entry point, register routes with `httpd`, support YAML and environment-based configuration, `/healthz`, `/readyz`, graceful shutdown, and request size limits.

**Deliverables**: `registry/main.emo`, configuration structs and validation, health checks, and `docs/spec/registry-config.md`.

**Acceptance**: `emo build` passes; `/healthz` returns 200; `/readyz` returns non-200 when the database or object store is unavailable; SIGTERM stops accepting new requests and finishes in-flight ones; missing configuration produces a clear error.

**Depends on**: T1.2 · **Estimate**: 2h

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

#### T2.3 OCI Manifest / Index Model and Validation

**Goal**: Implement parsing and encoding for OCI Image Manifest, Image Index, and Image Config; validate descriptor media type, digest, and size; support selecting a child manifest by platform.

**Deliverables**: `registry/oci.emo`, golden fixtures, and parser / validation tests.

**Acceptance**: Real image manifests parse; missing fields, bad digest formats, and size mismatches are rejected; encoded bytes are reproducible; index platform selection matches the client.

**Depends on**: T1.5 · **Estimate**: 2-3h

#### T2.4 BlobStore Interface and Local Filesystem Backend

**Goal**: Define the blob storage abstraction: `put`, `get`, `head`, `delete`, and `presign_get`. The local filesystem backend is for development and tests, with content-addressed paths.

**Deliverables**: `registry/blobstore.emo`, the local backend, and interface tests.

**Acceptance**: Writes use a temp file plus atomic rename; reads support Range; paths cannot escape the root; data survives a restart; `presign_get` returns empty for backends without presigning, and the caller falls back to direct streaming.

**Depends on**: T2.1 · **Estimate**: 2h

#### T2.5 AWS SigV4 Signing and Presigned URLs

**Goal**: Use `crypto` HMAC-SHA256 to implement AWS Signature V4 request signing and query-string presigning, compatible with MinIO path-style access.

**Deliverables**: `registry/sigv4.emo`, official test vectors, and unit tests with a fixed clock.

**Acceptance**: Signatures match the AWS test vectors; presigned URLs work within their validity window and fail after expiry; URI encoding follows SigV4; keys and signatures never appear in logs.

**Depends on**: T2.1 · **Estimate**: 3h

#### T2.6 S3 / MinIO BlobStore Adapter

**Goal**: Implement an S3-compatible storage backend on top of SigV4, supporting PUT / GET / HEAD / DELETE and GET presigning; configure endpoint, bucket, region, access key, secret key, TLS, and path-style.

**Deliverables**: `registry/s3_blobstore.emo`, MinIO integration tests, and configuration examples.

**Acceptance**: Upload, download, and presigned access against MinIO work; a missing bucket fails startup with a clear message; TLS and custom CAs are configurable; network errors retry with clear messages; keys are never logged.

**Depends on**: T2.4, T2.5 · **Estimate**: 3h

#### T2.7 `/v2/` Base Protocol and Error Format

**Goal**: Implement `GET /v2/` with `Docker-Distribution-API-Version: registry/2.0`; standardize OCI error JSON `{"errors":[{"code","message","detail"}]}`; cover 401 / 404 / 405 responses.

**Deliverables**: routes and middleware, error response helpers, and protocol tests.

**Acceptance**: In unauthenticated mode `GET /v2/` returns 200; with auth enabled, T2.14 covers the 401 challenge; unknown routes return 404; method mismatches return 405 with `Allow`; all errors follow the OCI error format; responses carry a request id.

**Depends on**: T2.1, T2.2 · **Estimate**: 1-2h

#### T2.8 Manifest GET / HEAD and Tag / Digest Resolution

**Goal**: Implement `/v2/<name>/manifests/<reference>` where `<name>` may contain `/`; reference supports tag and digest; handle `Accept` and return the raw manifest bytes with `Docker-Content-Digest`, `Content-Type`, and `Content-Length`.

**Deliverables**: routes, lookup logic, HEAD support, and tests.

**Acceptance**: Fetch by tag and digest both work; missing content returns 404 `MANIFEST_UNKNOWN`; HEAD returns no body; digest mismatches are rejected; multi-arch indexes are returned intact.

**Depends on**: T2.2, T2.3, T2.7 · **Estimate**: 3h

#### T2.9 Blob GET and 307 Presigned Redirect

**Goal**: Implement `/v2/<name>/blobs/<digest>`. With S3, return 307 plus a presigned `Location`; with the local filesystem backend, stream a 200. HEAD returns metadata and does not redirect.

**Deliverables**: blob GET / HEAD, presigned TTL configuration, and tests.

**Acceptance**: The URL in the 307 `Location` downloads directly and expires; the local backend returns the correct `Content-Length` and `Docker-Content-Digest`; missing blobs return 404 `BLOB_UNKNOWN`; the client works in both modes.

**Depends on**: T2.4, T2.6, T2.8 · **Estimate**: 2-3h

#### T2.10 Blob Upload: POST / PUT

**Goal**: Implement the minimal OCI upload flow: `POST /v2/<name>/blobs/uploads/` creates a session; `PUT ...?digest=sha256:...` uploads the full blob; verify digest and size, deduplicate, and expire old sessions.

**Deliverables**: upload routes, the session table, single-blob upload tests, and a `curl` example.

**Acceptance**: A `HEAD` request finds the blob after upload; a digest mismatch returns 400 and stores nothing; duplicate blobs are stored once; expired sessions can be cleaned up; upload size limits are enforced.

**Depends on**: T2.4, T2.7 · **Estimate**: 3h

#### T2.11 Chunked Upload and Resumable Transfers: PATCH / GET / DELETE

**Goal**: Complete OCI chunked upload: `PATCH` appends data, `GET` reports the offset, and `DELETE` cancels a session; support client-side resume.

**Deliverables**: chunked upload implementation, state-machine tests, and compatibility tests with `oras` / `skopeo`.

**Acceptance**: Multi-part PATCH followed by PUT succeeds; GET mid-upload returns the correct `Range`; a deleted session is unusable; concurrent writes to the same session are rejected; abandoned sessions expire.

**Depends on**: T2.10 · **Estimate**: 3h

#### T2.12 Manifest PUT and Tag Updates

**Goal**: Implement `PUT /v2/<name>/manifests/<tag|digest>`, verify that the manifest's config and layers exist, store the manifest, and update the tag atomically.

**Deliverables**: manifest writes, tag updates, and transaction tests.

**Acceptance**: `oras push` / `skopeo copy` succeeds; missing references return `MANIFEST_BLOB_UNKNOWN`; tag updates are atomic; the response includes `Docker-Content-Digest`; a failure does not overwrite the old tag.

**Depends on**: T2.3, T2.10, T2.11 · **Estimate**: 2-3h

#### T2.13 Resolve / Metadata API

**Goal**: Provide a read-only endpoint for CLI and operational debugging: `GET /api/v1/resolve?repository=<name>&tag=<tag>`, returning the digest, media type, platforms, and an optional commit annotation from `org.opencontainers.image.revision`.

**Deliverables**: the endpoint, JSON responses, authentication, and tests.

**Acceptance**: Existing tags return full information; missing tags return 404; unauthorized requests return 401/403; storage credentials are never exposed; `pokerface` can use it as a read-only fallback when Git metadata is missing.

**Depends on**: T2.8, T2.12 · **Estimate**: 2h

#### T2.14 Authentication and Token Service

**Goal**: Implement the Bearer token flow: `GET /v2/` returns 401 with `WWW-Authenticate`; `/token` exchanges Basic auth for a short-lived scoped token; middleware validates `repository:<name>:pull|push`.

**Deliverables**: token issuance / validation, scope middleware, configuration examples, and negative tests.

**Acceptance**: Anonymous pull is rejected (when auth is enabled); a pull-only scope cannot push; expired tokens return 401; cross-repository access is denied; passwords and signing keys never appear in logs; the v0.1 config-file flow works.

**Depends on**: T2.7 · **Estimate**: 3-4h

#### T2.15 Cache Headers, ETag, and CDN Behavior

**Goal**: Use different cache policies for immutable blobs and mutable manifests; support `ETag` / `If-None-Match`; ensure the CDN can cache blobs while tag updates still take effect promptly.

**Deliverables**: response-header middleware, CDN configuration notes, and tests.

**Acceptance**: Blobs return long-lived caching plus `immutable`; manifests return short caching or `no-cache`; `If-None-Match` hits return 304; new requests see the new digest after a tag update; CDN caching never pins an old manifest for long.

**Depends on**: T2.8, T2.9 · **Estimate**: 2h

#### T2.16 Tag Listing and Pagination

**Goal**: Implement `GET /v2/<name>/tags/list`, returning tags in lexical order with `n` and `last` pagination and a `Link` header when more pages exist.

**Deliverables**: routes, pagination logic, and tests.

**Acceptance**: An empty repository returns an empty list; pagination boundaries are correct; a missing `last` starts from a sensible position; pull permission is required; the response follows the OCI spec.

**Depends on**: T2.12 · **Estimate**: 2h

#### T2.17 Deployment: Registry + MinIO + Caddy

**Goal**: Provide reproducible deployment: a multi-stage build for the Emo binary, a runtime image with the required shared libraries, and Compose services for the registry, MinIO, and Caddy; configure volumes, health checks, TLS, and `.env.example`.

**Deliverables**: `deploy/Dockerfile`, `deploy/compose.yaml`, `deploy/Caddyfile`, `.env.example`, and deployment docs.

**Acceptance**: On a clean machine, `docker compose up -d` brings all three services up in a healthy state; the registry is reachable through Caddy; MinIO data persists; a restart loses no data; `.env.example` contains no real secrets.

**Depends on**: T2.6, T2.14 · **Estimate**: 3h

#### T2.18 Observability and Audit Logging

**Goal**: Add structured logging (`slog` JSON), request ids, access logs, auth audit events, and Prometheus text metrics; never log tokens, Authorization headers, or presigned query strings.

**Deliverables**: logging middleware, `/metrics`, audit events, and tests.

**Acceptance**: Every request has a request id; logs parse with `jq`; metrics include request count, latency, error count, and upload / download bytes; auth failures are audited; sensitive fields are redacted.

**Depends on**: T2.1 · **Estimate**: 2-3h

#### T2.19 Protocol Smoke and Conformance Tests

**Goal**: Validate the registry with real clients: push with `oras` or `skopeo`, pull with `pokerface`, download presigned blobs, and exercise negative auth cases; turn this into a repeatable smoke script.

**Deliverables**: `scripts/e2e-m2.sh`, test image fixtures, and test documentation.

**Acceptance**: The script starts compose from a clean environment, completes push / pull / verification, and cleans up; failures emit actionable logs; it does not contact Docker Hub; it covers 401, 404, and digest-mismatch paths.

**Depends on**: T2.1-T2.18 · **Estimate**: 3h

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
| [ ] | T4.1 | `pokerface build` command and build plan | T1.4, T1.5 | 2h |
| [ ] | T4.2 | BuildKit / podman build adapter | T4.1 | 3-4h |
| [ ] | T4.3 | Registry push: blobs + manifest | T1.10, T2.12, T4.2 | 3h |
| [ ] | T4.4 | Generate and write back the lock file | T4.3 | 2h |
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

#### T4.2 BuildKit / Podman Build Adapter

**Goal**: Wrap the local build tool. Prefer Docker BuildKit `buildx build --output type=oci`; use podman as a fallback. Write standard OCI labels: `org.opencontainers.image.revision`, `source`, `version`, and `created`.

**Deliverables**: `src/build.emo`, tool detection, streamed log output, and build tests.

**Acceptance**: The example Dockerfile builds into an OCI layout; `inspect` shows the commit / source labels; build failures surface the original log and exit code; missing BuildKit produces a clear message; multi-platform builds are optional and do not break single-platform builds.

**Depends on**: T4.1 · **Estimate**: 3-4h

#### T4.3 Registry Push: Blobs + Manifest

**Goal**: Reuse the M1 registry client to upload blobs (single and chunked), push manifests, update tags, and capture digests with retries.

**Deliverables**: `src/push.emo`, push tests, and progress output.

**Acceptance**: Push to the M2 registry succeeds; the returned digest matches the local digest; repeat pushes skip existing blobs; mid-flight failures can retry without corrupting existing tags; auth scopes are correct.

**Depends on**: T1.10, T2.12, T4.2 · **Estimate**: 3h

#### T4.4 Generate and Write Back the Lock File

**Goal**: After a successful build and push, generate `pokerface.lock.yaml` with the commit, image, tags, digest, platforms, and builder. Support `--write-lock` and an optional `--commit` that only creates a local Git commit and never pushes.

**Deliverables**: a lock generator, merge logic, and tests.

**Acceptance**: Rebuilding the same image produces an idempotent lock; multi-tag and multi-platform entries sort stably; unrelated entries are preserved; no real secrets are written; `pokerface resolve` consumes the generated lock directly.

**Depends on**: T4.3 · **Estimate**: 2h

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
