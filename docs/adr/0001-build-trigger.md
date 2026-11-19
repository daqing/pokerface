# ADR 0001: Build Triggers and Versioning Policy

- **Status**: Accepted (2026-11-20)
- **Implements**: decision D7 (`docs/TASKS.md` §3)
- **Consumed by**: T4.6's CI template, T4.1's tag renderer, T4.2's build adapter

## Context

A pokerface image is always built from a commit: `pokerface build` captures
the Git metadata of the context repository, renders tags from it, pushes,
and writes the `commit → image → digest` chain back into
`pokerface.lock.yaml` (`docs/spec/pokerface-lock.md`). Something must
decide **when** that runs. The candidates:

1. CI events (a Git push, a Git tag, a manual dispatch) — the CI system
   already owns trigger machinery, secrets, and runner capacity.
2. A pokerface-operated webhook service — an always-on listener that spawns
   builds.
3. Polling — a scheduler that re-checks repositories for new commits.

v0.1 has no build queue, no build scheduler, and no daemon beyond the
registry. The tag renderer (T4.1) constrains what a trigger can express:
tags come from the Git facts (commit, tag, branch, version) through the
`pokerface.yaml` templates, and the rendered tag must satisfy the OCI
charset (lowercase `[a-z0-9._-]`, no leading `.` or `-`).

## Decision

**v0.1 builds are CI-driven.** The supported triggers are exactly:

| Trigger | When it fires | The Git facts it produces |
| --- | --- | --- |
| **Branch push** | Every push to a branch | `{{ branch }}` = the branch name, `{{ commit.short }}` = the pushed commit, `{{ git.tag }}` = `""` |
| **Tag push** | Every push of a Git tag (`git tag vX.Y.Z && git push --tags`) | `{{ git.tag }}` = the tag verbatim, `{{ version }}` = the newest reachable tag, `{{ commit.short }}` = the tagged commit |
| **`workflow_dispatch`** | A human clicks "Run workflow" (or CI retries) | the facts of the ref the workflow runs on |

The CI template (T4.6) wires exactly these three. A build that is not one
of these — a laptop cron, a docker-cached rebuild — is simply a local
`pokerface build`, which is allowed but produces no lock write-back unless
the operator passes `--write-lock`.

### Tag rules

The recommended `pokerface.yaml` `tags` per trigger (what the T4.6
template ships as the example):

| Fact | Rule | Example |
| --- | --- | --- |
| Every build | `sha-{{ commit.short }}` | `sha-0123abcd` — the immutable, always-correct pointer |
| Branch push | `latest` for the default branch (the lock's commit tells consumers exactly what `latest` means) | `latest` |
| Branch push | `{{ branch }}` — **only for branch names that survive the OCI charset**; a branch like `feat/x` renders a `/` and the build fails with the renderer's clear error. Use `sha-{{ commit.short }}` for such branches, or name branches sanely. | `main`, `release-1` |
| Tag push | the Git tag **verbatim** (`v1.2.3` stays `v1.2.3`) | `v1.2.3` |
| Tag push | `{{ version }}` for derived forms the operator wants (`v{{ version }}`) | `v1.4.2` |

**Semantic versions**: a tag matching `v<MAJOR>.<MINOR>.<PATCH>` is pushed
verbatim; v0.1 does **not** derive floating convenience tags (`1.2`, `1`,
retargeting `latest` on semver). That is registry-mutation policy with real
blast radius (moving `1` moves every consumer), and it deserves its own ADR
once there is a consumer that needs it. Operators who want it today add the
derived tags as explicit literals in `pokerface.yaml`'s CI step.

### Versioning policy

- The **version string** is `git describe --tags --abbrev=0` — the newest
  tag reachable from the built commit. A repository without tags renders
  `{{ version }}` to `""`, which fails the tag charset check with a clear
  message: tag your releases.
- The **release discipline** is: tag (`vX.Y.Z`) → push the tag → the
  tag-triggered build → the lock records `tag → commit → digest` →
  consumers resolve `github.com/acme/app:vX.Y.Z` from Git alone.
- The **lock is the source of truth** for what a tag meant at a commit;
  mutable registry tags (`latest`, branch tags) are conveniences whose
  meaning is always recoverable from the lock history in Git.
- **Rebuilds** are CI re-runs (`workflow_dispatch`). They produce a new
  image (buildx stamps `created`) and a new lock entry — a rebuild is a new
  build, not a replay of the old bytes.

## Alternatives considered

- **Self-hosted webhook service** (rejected for v0.1): a second always-on
  service (auth surface, deployment story, a queue for concurrent builds,
  and a place for build logs to live). Everything it would do, the CI
  system already does — and T4.2's adapter runs on the CI runner with
  docker available, which a webhook host would need anyway. Revisit when
  there is a consumer that needs sub-minute build starts without CI.
- **Polling** (rejected): wasted builds on unchanged commits, API rate
  limits, and minutes-to-hours of latency, in exchange for avoiding one
  CI YAML file. The lock's commit chain makes repeated no-op builds
  *safe* but not *free*; polling buys nothing.
- **Build on the registry** (rejected, not even deferred): the registry is
  a dumb, fast metadata+blob store by design (D8); coupling builds to it
  would make the registry stateful and the build story less portable.

## Consequences

- No self-hosted infrastructure in v0.1: the trigger story is one CI
  workflow file (T4.6).
- Build visibility is the CI system's — pokerface offers no build queue,
  log store, or status API. `pokerface resolve` answers *what was built*,
  never *what is building*.
- Branch names outside the tag charset fail at the renderer with a clear
  error (documented above) instead of being silently mangled.
- The trigger contract is pure Git: any CI system that can run a binary on
  a checkout can build pokerface images; nothing pokerface-specific has to
  be installed server-side.

## Deferred to later versions

- Self-hosted webhook triggers (needs the queue/auth/log story first).
- Polling-based triggers.
- Floating semver convenience tags (`1.2`, `1`, semver-driven `latest`).
- Build queues, concurrency limits, and build status reporting.
