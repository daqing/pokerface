# Specification Index

> The client's v0.1 contracts (M1, complete) and the server side as it lands
> (M2, in progress).

| Spec | Covers | Implemented by |
| --- | --- | --- |
| [pokerface-yaml.md](pokerface-yaml.md) | The build input committed with the app: image, tags, platforms, builder. | `src/config.emo` |
| [pokerface-lock.md](pokerface-lock.md) | The metadata CI writes back: `commit → image → digest` chain. | `src/lockfile.emo` |
| [config.md](config.md) | Client config precedence, credentials, XDG paths, cache limits. | `src/settings.emo` |
| [errors.md](errors.md) | Error kinds, fixed exit codes, remediation hints, JSON errors, verbose logging and redaction. | `src/errors.emo`, `src/common.emo` |
| [registry-client.md](registry-client.md) | `/v2/` probe, Bearer auth, manifest/index fetch, media types. | `src/registry.emo` |
| [pull.md](pull.md) | The pull chain, failure fallbacks, offline mode, host discipline. | `src/commands/pull.emo` |
| [oci-layout.md](oci-layout.md) | Writing/validating `oci-layout`, `index.json`, `blobs/sha256`. | `src/oci.emo` |
| [runtime-import.md](runtime-import.md) | Docker/Podman/containerd import via skopeo, verification, cleanup. | `src/runtime.emo` |
| [cache.md](cache.md) | Cache layout, marker, TTL/size limits, `cache ls/rm/verify`. | `src/cache.emo`, `src/commands/cache.emo` |
| [registry-config.md](registry-config.md) | Registry service config, health/readiness, request limits, shutdown (M2/T2.1). | `registry/config.emo`, `registry/health.emo`, `registry/main.emo` |
| [registry-db.md](registry-db.md) | SQLite schema, migrations, pragmas, readiness, and the split test story (M2/T2.2). | `registry/db.emo`, `registry/db_selftest.emo` |
| [registry-oci.md](registry-oci.md) | Manifest/index/config model, descriptor validation, canonical encoding, platform selection (M2/T2.3). | `registry/oci.emo` |
| [registry-blobstore.md](registry-blobstore.md) | Blob abstraction, local filesystem backend, atomic writes, range reads, presign fallback (M2/T2.4). | `registry/blobstore.emo` |
| [registry-sigv4.md](registry-sigv4.md) | AWS SigV4 header signing and presigned URLs, encoding rules, official vectors (M2/T2.5). | `registry/sigv4.emo` |
| [registry-s3.md](registry-s3.md) | S3/MinIO backend, addressing, signed requests, retries, presigning, startup bucket check (M2/T2.6). | `registry/s3_blobstore.emo` |
| [registry-api.md](registry-api.md) | `/v2/` probe, OCI error envelope and codes, request ids, routing (M2/T2.7). | `registry/api.emo`, `registry/router.emo` |
| [registry-manifests.md](registry-manifests.md) | Manifest GET/HEAD by tag or digest, Accept, integrity, 404s (M2/T2.8). | `registry/manifests.emo` |
| [registry-blobs.md](registry-blobs.md) | Blob GET/HEAD, 307 presigned redirects, link checks (M2/T2.9). | `registry/blobs.emo` |
| [registry-uploads.md](registry-uploads.md) | Blob upload: POST session, monolithic PUT with digest verification, session expiry, name grammar (M2/T2.10). | `registry/uploads.emo` |
| [registry-auth.md](registry-auth.md) | Bearer tokens (HS256 JWT), scopes, the /token exchange, WWW-Authenticate challenges, auth config (M2/T2.14). | `registry/auth.emo`, `registry/config.emo` |
| [registry-resolve.md](registry-resolve.md) | The /api/v1/resolve metadata endpoint: digest, media type, platforms, revision annotation, pull-scope auth (M2/T2.13). | `registry/resolve.emo` |
| [registry-cache.md](registry-cache.md) | ETag/If-None-Match, immutable blob caching, short tag-manifest caching, CDN behavior (M2/T2.15). | `registry/cache.emo` |
| [registry-tags.md](registry-tags.md) | Tag listing in lexical order with n/last pagination and rel=next links (M2/T2.16). | `registry/tags.emo` |
| [registry-metrics.md](registry-metrics.md) | slog JSON access/audit logs, SQLite-backed Prometheus counters and latency histogram, /metrics (M2/T2.18). | `registry/metrics.emo`, `registry/router.emo` |

## M1 flow

```text
repository reference
  → parse + resolve the ref to a commit            docs/cli.md (ref syntax)
  → read pokerface.lock.yaml from the mirror cache  pokerface-lock.md
  → pick image / digest / tag / platform
  → fetch the manifest (cache fallback)            registry-client.md, pull.md
  → download + verify blobs                        pull.md, cache.md
  → assemble an OCI layout                         oci-layout.md
  → import into Docker/Podman/containerd           runtime-import.md
  → enforce cache limits                           cache.md
```

Every failure is classified into the kinds in [errors.md](errors.md).

## Validating the M1 client

```console
$ emo build main.emo       # compile the CLI
$ emo test                 # the full unit/integration suite
$ ./scripts/e2e-m1.sh      # local fixture repo + Emo mock registry/CDN
```

`scripts/e2e-m1.sh` never contacts Docker Hub: the lock names a loopback mock
registry, whose blob endpoint redirects to a local CDN path. Set `KEEP_TMP=1`
to keep its temp directory and logs.
