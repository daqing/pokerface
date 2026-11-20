# Deploying the Registry Stack (T2.17)

The distribution stack is three services: the **pokerface registry** (API),
**MinIO** (blob storage), and **Caddy** (TLS in front of the API). Compose
brings them up together; MinIO is never exposed — the registry is the single
entrypoint.

```console
$ cd deploy
$ cp ../.env.example .env      # then edit: credentials, domain, signing key
$ openssl rand -base64 24 | tr -d '\n' > registry.password   # the auth account
$ chmod 600 registry.password
$ docker compose up -d
$ docker compose ps            # all three healthy
```

## What the pieces are

- `deploy/registry.compose.yaml` — the base configuration the service
  **requires** (a missing config file is a startup error). It carries no
  secrets: the S3 endpoint, credentials, and auth key arrive as
  `POKERFACE_REGISTRY_*` environment overrides from `.env`, and the auth
  account's password comes from `deploy/registry.password`
  (`password_file`, mounted read-only) — never baked into an image.
  The compose environment also sets `POKERFACE_REGISTRY_AUTH_REALM` to the
  public `https://<domain>/token` (clients follow the 401 challenge's realm;
  the internal listen address is unreachable for them) and
  `POKERFACE_REGISTRY_S3_PRESIGN_TTL=0`, which makes blob GETs stream
  through the registry instead of redirecting to a presigned internal MinIO
  URL — Caddy stays the single entrypoint.
- `createbucket` — a one-shot service that creates the S3 bucket the
  registry's startup check requires (`mc mb --ignore-existing`). Both MinIO
  and mc come from `minio/minio:local` / `minio/mc:local`, built from the
  pinned upstream sources: MinIO stopped publishing community images and
  binary downloads in 2025 (`RELEASE.2025-04-22T22-12-26Z` for the server,
  `RELEASE.2025-05-21T01-59-54Z` for mc here). Build them once per machine
  — see the notes under "Verified" below.
- `deploy/Dockerfile` — a two-stage build. Stage 1 compiles the registry
  with the Emo toolchain (the `EMO_BUILDER_IMAGE` build argument names the
  image carrying `emo`; the toolchain is young, so until a builder image is
  published, build one from `emo-lang/emo` or point the argument at an image
  of your own). Stage 2 is `debian:bookworm-slim` with `libsqlite3-0` (the
  metadata store links it) and `wget` (the healthcheck); the binary itself
  carries the HTTP server, YAML/JSON, SHA-256, and the filesystem store.
- `deploy/registry-entrypoint.sh` — the registry ignores SIGTERM by design
  (Emo offers no signal handlers; `scripts/run-registry.sh` documents the
  same protocol), so the entrypoint is PID 1 and turns the container's
  signal into the shutdown marker file the main loop watches, then waits for
  the in-flight requests to drain before exiting. A trapped signal
  interrupts shell `wait`, so the reap loops until the server is really
  gone — leaving early would cancel the drain.
- `deploy/compose.yaml` — the three services, the internal network, the
  named volumes (`registry-data` for SQLite metadata, `minio-data` for
  objects, `caddy-data`/`caddy-config` for certificates), MinIO's health
  check gating the registry start, and the registry's healthcheck gating
  Caddy. Values come from `.env`; the compose file refuses to start without
  the four secrets set.
- `deploy/Caddyfile` — one site for `$REGISTRY_DOMAIN` reverse-proxying the
  registry. With a public DNS name Caddy obtains a Let's Encrypt certificate
  automatically; `REGISTRY_DOMAIN=localhost` uses Caddy's internal CA (dev
  only). Cache headers pass through untouched ([registry-cache.md] — blobs
  are immutable, tag manifests revalidate within a minute), so a CDN in
  front of Caddy honors the registry's policy.

## Configuration surface

Everything reaches the registry through environment overrides
([registry-config.md]): listen address, data dir, the S3 backend pointed at
`http://minio:9000` with path-style addressing, the auth toggle and signing
key. The signing key and MinIO credentials come from `.env` — never commit
it; `.env.example` carries placeholders only.

Rotation: restart the registry with a new `REGISTRY_SIGNING_KEY` — existing
tokens invalidate immediately (they verify against the configured key), and
clients simply re-authenticate. MinIO credentials rotate the same way.

## Persistence

MinIO's objects and the registry's SQLite metadata live in named volumes;
`docker compose down` keeps them (add `-v` to erase — that erases every
pushed image). A restart re-serves everything: the registry re-reads its
metadata and re-opens the S3 store, and the start-up bucket check fails
loudly if MinIO's bucket vanished.

## Verified and known gaps

- The entrypoint's signal protocol and the server's graceful drain are
  verified on the host (SIGTERM → marker → `shutting down` / `stopped` →
  clean exit).
- `docker compose config` validates the stack definition.
- **The whole stack was exercised end to end** (2026-11-20, section-9
  verification): `docker compose up -d` brings all three services up
  healthy; `skopeo login` through Caddy succeeds against the public realm;
  a skopeo push lands in MinIO; the tag list and blobs answer through
  Caddy (blobs streamed by the registry, `presign_ttl: 0`); and a full
  `docker compose down` + `up` leaves the tags and blobs intact (the named
  volumes). Getting there required fixing two upstream Emo Linux runtime
  bugs (uninitialized `pending` in the connection meta, missing
  `<stddef.h>`) — recorded in `docs/notes/runtime-capabilities.md`; the
  fixes live on the emo repo's `fix/stdlib-http` branch.
- The registry image needs a **Linux** Emo compiler: this machine's
  toolchain builds macOS binaries. The verification built one with the emo
  repo's own release builder image (`devtools/release-builder.Dockerfile`,
  `emo-release:ubuntu22.04-arm64`) and used it for both the registry and
  the probe programs; `EMO_BUILDER_IMAGE` is the supported path once a
  published builder image exists.
