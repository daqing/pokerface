# Deploying the Registry Stack (T2.17)

The distribution stack is three services: the **pokerface registry** (API),
**MinIO** (blob storage), and **Caddy** (TLS in front of the API). Compose
brings them up together; MinIO is never exposed — the registry is the single
entrypoint.

```console
$ cd deploy
$ cp ../.env.example .env      # then edit: credentials, domain, signing key
$ docker compose up -d
$ docker compose ps            # all three healthy
```

## What the pieces are

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
- The full `docker compose up` could not be run on the development machine:
  the MinIO and Caddy images are unreachable there (Docker Hub and the
  configured mirror both time out — the same limitation recorded in T2.6's
  S3 notes). On a machine with registry access, `docker compose up -d` from
  `deploy/` is the verification; the smoke script (T2.19) exercises the
  stack end to end once it is up.
