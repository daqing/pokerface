# Troubleshooting (T4.15)

> Every scenario has four sections — **symptom / cause / handling /
> verification** — and the verification cites where the behavior is pinned
> (a test, an e2e leg, or an executed run). Exit codes follow
> `docs/spec/errors.md`; the build-side specifics live in
> `docs/spec/build-plan.md` and `docs/spec/push.md`.

## The matrix at a glance

| Symptom | Exit | Scenario |
| --- | --- | --- |
| `git: …` during resolve/pull | 3 | [Git failure](#1-git-failure) |
| `registry: manifest …` then a warning | 4 or 6 | [Manifest fetch failure](#2-manifest-fetch-failure) |
| `connection refused` / `timeout` mid-pull | 6 | [Registry or CDN failure](#3-registry-or-cdn-failure) |
| `integrity: …` / `digest mismatch` | 7 | [Digest mismatch](#4-digest-mismatch) |
| `runtime: skopeo is required` | 8 | [Runtime import failure](#5-runtime-import-failure) |
| `blob: corrupt` / cache oddities | 7 | [Cache corruption](#6-cache-corruption) |
| `runtime: no build tool found` | 8 | [No build tool](#7-no-build-tool) |
| build exits non-zero after buildx's log | 1 | [Build failure](#8-build-failure) |
| `renders to an invalid tag` / `collides with` | 4 | [Tag rendering](#9-tag-rendering) |
| `the lock's source names the origin remote…` | 4 | [Lock write-back](#10-lock-write-back) |
| `insufficient_scope` / 401 | 5 | [Authentication](#11-authentication) |
| big transfers die mid-body | varies | [Large transfers](#12-large-transfers) |
| the registry will not stop | — | [Stopping the registry](#13-stopping-the-registry) |

---

## 1. Git failure

- **Symptom**: `pokerface: resolve: git: …` — ref resolution, mirror fetch,
  or mirror read failed; exit 3.
- **Cause**: the repository is unreachable (wrong URL, no network, no SSH
  key), the ref does not exist, or the mirror is wedged.
- **Handling**: check the URL with the same Git the CLI uses
  (`git ls-remote <url>`); fix access (network, key); for mirror trouble,
  `pokerface cache verify` repairs mirrors (`git fsck`) or `pokerface cache
  rm --git` resets them. A Git failure is **never** answered from a stale
  cache — deliberately, so a broken fetch cannot masquerade as an old
  truth. The offline escape is `--offline` with a full commit SHA.
- **Verification**: `test/pull_cmd.emo` pins the no-stale-fallback rule;
  `e2e-m2.sh` exercises the online chain. Executed: a bad-ref resolve
  fails with the ref named in the error (T1.9 run).

## 2. Manifest fetch failure

- **Symptom**: `registry: manifest fetch failed (registry: …); using cached
  manifest sha256:…` during a pull; exit 0 when the cache serves, else 4/6.
- **Cause**: the registry answered non-200 (gone, 5xx, CDN error) for the
  manifest request.
- **Handling**: nothing — the pull falls back to the **cached manifest**,
  whose digest must still match the lock (a mismatch is an integrity error,
  not a fallback). Fix the registry; the warning names the original failure.
- **Verification**: `test/pull_cmd.emo`'s fallback cases (fetch fails →
  cache serves; cache digest disagrees → integrity error). Executed: the
  T2.19-era run with a 500-ing registry.

## 3. Registry or CDN failure

- **Symptom**: `connection refused`, `timeout`, `status 5…` during blob
  download; exit 6.
- **Cause**: the registry or the CDN in front of it is down, the URL in
  the lock is wrong, or a proxy interferes.
- **Handling**: retry (blob downloads retry per blob with backoff); if the
  image was pulled before, `--offline` serves everything from the cache;
  `pokerface cache verify` can confirm the cache is complete. For a CDN:
  cache policy must match `docs/spec/registry-cache.md` (blobs immutable,
  manifests 60 s, `/token` never cached).
- **Verification**: `test/blob_dl.emo` (retry/backoff/resume matrix);
  executed: a registry restarted mid-pull resumes through the cache.

## 4. Digest mismatch

- **Symptom**: `integrity: … digest mismatch …` on pull, or
  `the registry answered digest X … the pushed bytes hash to Y` on build
  push; exit 7.
- **Cause**: the bytes on the wire do not hash to what the lock (or the
  local build) declares — corruption in transit, a CDN rewriting bodies, or
  a registry bug.
- **Handling**: never bypass. Retry once (transient corruption is
  conceivable); if it persists, purge the suspect cache entry
  (`pokerface cache rm --blobs`) and re-pull; report a registry that
  consistently serves wrong bytes. On the push side the tag is NOT updated
  with mismatched bytes.
- **Verification**: `test/pull_cmd.emo` (mismatch aborts, temp files
  cleaned), `test/push.emo` (`test_push_verifies_the_manifest_digest`).
  Executed: the wrong-`Docker-Content-Digest` push test.

## 5. Runtime import failure

- **Symptom**: `runtime: skopeo is required…` or an import error naming
  docker/podman/containerd; exit 8.
- **Cause**: skopeo is missing, the daemon is down, or the socket is not
  accessible.
- **Handling**: install skopeo (`brew install skopeo` / the distro
  package); start the runtime; check `docker info`. The pull has already
  verified every byte — the import is the only missing leg, and re-running
  `pokerface pull` after the fix reuses the cached blobs.
- **Verification**: `test/pull_cmd.emo` (missing-skopeo path);
  `e2e-m2.sh`'s import leg skips with a clear report when no runtime
  exists.

## 6. Cache corruption

- **Symptom**: `pokerface cache verify` reports corrupt blobs, bad manifest
  envelopes, broken ref maps, or `git fsck` failures; pulls fail with
  integrity errors; exit 7.
- **Cause**: interrupted writes (power loss, disk full), manual edits, a
  cache directory copied incoherently.
- **Handling**: `pokerface cache verify` **repairs by default** — corrupt
  entries and debris are evicted and re-fetched on the next pull;
  `--check` only reports (exit 7 while issues remain). A full reset:
  `pokerface cache rm --all`. Offline mode needs a complete cache — verify
  before relying on it.
- **Verification**: `test/cache_cmd.emo`'s verify/repair matrix; the cache
  layout contract is `docs/spec/cache.md`.

## 7. No build tool

- **Symptom**: `runtime: no build tool found — install docker (with
  buildx) or podman, and check PATH` on `pokerface build` (without
  `--dry-run`); exit 8.
- **Cause**: neither `docker buildx version` nor `podman --version` runs.
- **Handling**: install Docker (buildx ships with it) or podman; check
  PATH. `--dry-run` needs no build tool at all.
- **Verification**: `test/build_cmd.emo` (`test_detect_tool_*` — buildx
  preferred, podman fallback, the toolless error classified as runtime).

## 8. Build failure

- **Symptom**: buildx's own log streams by, ending in
  `pokerface: build: 'docker' exited with code 1`; exit 1.
- **Cause**: the Dockerfile, the context, or the builder itself — the CLI
  wraps the tool, it does not interpret Dockerfiles.
- **Handling**: read the streamed log (the real reason is in it); fix the
  Dockerfile; re-run. The temp layout is discarded; the lock is not
  touched.
- **Verification**: executed — a `RUN definitely-not-a-real-command`
  Dockerfile surfaces buildx's ERROR block, then the CLI's one-line
  failure with the exit code.

## 9. Tag rendering

- **Symptom**: `pokerface.yaml: tags[1]: …` at parse time, or at build time
  `tag template '…': renders to an invalid tag` / `tags[1] ('{{ git.tag }}')
  collides with tags[0]`; exit 4.
- **Cause**: a rendered tag left the OCI charset (a branch with `/`, an
  untagged repo's `{{ version }}`), or two templates rendered the same
  string.
- **Handling**: quote template entries (`"sha-{{ commit.short }}"` — in a
  flow list `{{` opens a flow mapping); pick tags per ADR 0001's rules;
  `sha-{{ commit.short }}` is always valid.
- **Verification**: `test/build_cmd.emo`'s renderer/collision tests;
  executed: a `feat/x` branch fails with the charset error.

## 10. Lock write-back

- **Symptom**: `the lock's source names the origin remote, and the context
  repository has none` / `the existing pokerface.lock.yaml does not parse`;
  exit 4.
- **Cause**: `--write-lock` needs the origin remote (the lock's `source`)
  and an existing lock that parses (a broken one is an error, never a
  clobber). `--commit` without `--write-lock` is a usage error.
- **Handling**: `git remote add origin …`; fix or remove the broken lock;
  run `--write-lock` (add `--commit` for the local lock commit — it never
  pushes).
- **Verification**: `test/lockfile.emo`'s generation/merge tests;
  executed: the T4.14 flow writes, commits, and resolves the lock.

## 11. Authentication

- **Symptom**: 401 with `insufficient_scope` in the challenge, or
  `token endpoint returned status 401`; exit 5.
- **Cause**: the token lacks the action (a pull-only token pushing), the
  token expired, or the client could not mint one (the `/token` endpoint
  needs Basic credentials the CLI does not carry — provide a token via
  `POKERFACE_REGISTRY_TOKEN` or `registry.token`).
- **Handling**: mint a token with the needed scope
  (`curl -u user:pass "$URL/token?service=…&scope=repository:<repo>:pull,push"`)
  and pass it; the CLI's 401 dance re-asks with the push+pull scope, but
  it cannot invent credentials.
- **Verification**: `test/push.emo`'s dance test (the scope request is
  pinned); executed: a push-scope token pushes, a pull-only token is
  rejected with the registry's envelope, no-token fails clearly.

## 12. Large transfers

- **Symptom**: a transfer dies mid-body (`closed after N of M bytes`) for
  blobs bigger than ~64 KiB — on push (mitigated: uploads are 64 KiB
  windows), on pull (mitigated: the registry serves bounded 206 windows and
  the pull walks them), or on a plain GET by other clients (still broken).
- **Cause**: the Emo runtime's plain-TCP `send` treats EAGAIN (socket
  buffer full) as fatal; documented in
  `docs/notes/runtime-capabilities.md` with the recommended runtime fix.
- **Handling**: pokerface's own push/pull work through the window
  protocol; for other clients (skopeo, curl), pull large images with
  `pokerface pull` until the runtime fix lands.
- **Verification**: `test/registry_blobs.emo`'s Range-window tests;
  executed: the hello example's 2.5 MB layer pulled through the windows
  and served by the container (T4.13).

## 13. Stopping the registry

- **Symptom**: `kill -TERM` on the registry process does nothing.
- **Cause**: by design — the server has no signal handlers; the documented
  stop protocol is the shutdown marker file
  (`docs/spec/registry-config.md`).
- **Handling**: `touch <data_dir>/registry.shutdown` and wait for the
  drain. If the marker cannot be created (the data dir was deleted), the
  process is orphaned: `kill -9` is the only option — prefer deleting the
  *marker's directory* being the last thing you do, not the first.
- **Verification**: `deploy/registry-entrypoint.sh` and `e2e-m2.sh` both
  drive the marker protocol; executed repeatedly.
