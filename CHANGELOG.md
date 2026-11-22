# Changelog

All notable changes to pokerface. The format follows
[Keep a Changelog](https://keepachangelog.com/); versions are the release
tags (`vX.Y.Z`), and unreleased work lives at the top.

## [0.3.2] — 2026-11-22

### Fixed

- The release job checks out the repository before publishing:
  `gh release create --verify-tag` and `--generate-notes` need a git
  repository, and only the downloaded artifacts were present.

### Changed

- Documentation notes the emo runtime's would-block send fix (unreleased at
  the time of writing); toolchains built before it still need the Range
  windows for large transfers.

## [0.3.1] — 2026-11-22

### Fixed

- The macOS release job builds the Emo toolchain from source again: the
  published macOS archive targets a newer macOS than the runners, so dyld
  failed at start-up.

## [0.3.0] — 2026-11-22

### Fixed

- `pokerface resolve` and `pokerface pull` accept `.` and `..` as local
  references (e.g. `.:main`, as the quick start documents); relative local
  paths resolve against the working directory.

## [0.2.0] — 2026-11-22

### Changed

- The registry server installs and runs as `pokerface-registry` (was the
  generic `registry`), and release builds land in `bin/`.
- Release binaries are built with the published Emo toolchain; Intel macOS
  (`darwin-amd64`) is no longer a release target.

## [0.1.0] — 2026-11-20

The first complete path: an application repository commits
`pokerface.yaml`, CI builds and pushes with `pokerface build`, the
registry serves it, and consumers resolve and pull from Git alone.

### Added — client (M1)

- `pokerface resolve`: the `ref → commit → pokerface.lock.yaml → digest`
  chain from Git alone, with the mirror cache and digest verification.
- `pokerface pull`: manifest + blob fetch with per-blob retries, incremental
  SHA-256 verification, OCI layout assembly, and skopeo-based import into
  Docker / podman / containerd; `--offline` repeats from the cache.
- `pokerface cache ls/verify/rm`: layout inspection, repair-by-default
  verification, sectioned resets, TTL/size limits.
- The client configuration surface (`--config`, `POKERFACE_*` variables,
  XDG paths) with redacted verbose logging and the fixed exit-code table.

### Added — registry (M2)

- An OCI Distribution subset service: `/v2/` probe, manifest GET/HEAD/PUT,
  blob GET/HEAD, monolithic and chunked uploads, tag listing with
  pagination, and the `/api/v1/resolve` metadata endpoint.
- Storage: a local filesystem backend and an S3/MinIO backend with SigV4
  signing and presigned-GET redirects; SQLite metadata with append-only
  migrations.
- Bearer-token authentication (HS256, pre-shared accounts, pull/push
  scopes), cache headers (immutable blobs, short-lived manifests), slog
  JSON access/audit logs, and SQLite-backed Prometheus metrics.
- The compose deployment (registry + MinIO + Caddy) and the shutdown-marker
  stop protocol.

### Added — build and delivery (M4)

- `pokerface build`: reads `pokerface.yaml`, captures Git metadata, renders
  tag templates (with collision detection), and answers a plan;
  `--dry-run` prints it, `--json` serializes it.
- The build adapter: buildx-first (`--output type=oci`), podman fallback,
  streamed logs, and the standard OCI labels (revision, source, version,
  created).
- The push pipeline: HEAD-skip blob uploads (single and 64 KiB chunked),
  manifests by digest, tag application, and served-digest verification.
- `--write-lock`: the generated `pokerface.lock.yaml` (sorted, merged,
  byte-stable rebuilds) and `--commit` for the local lock commit.
- The CI surface: a GitHub Actions publish workflow with GitLab and Gitea
  equivalents, an install script with checksum verification, the release
  workflow (four native platforms), the zero-framework docs site, the
  troubleshooting matrix, and the end-to-end demo script.
- The example application (`examples/hello`) and the build-trigger/versioning
  ADR.

### Fixed

- Registry blob GETs serve bounded 206 Range windows and the pull walks
  them — large blobs transfer reliably despite the runtime's socket-write
  limitation (see `docs/notes/runtime-capabilities.md`).
- Client platform selection and the registry's resolve API recurse into
  nested image indexes (buildx's multi-platform shape).
