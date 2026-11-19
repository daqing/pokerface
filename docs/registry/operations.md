# Registry Operations Guide (T4.12)

> For operators self-hosting the pokerface registry. The compose stack and
> its pieces are `docs/registry/deployment.md` (T2.17); the configuration
> reference is `docs/spec/registry-config.md`. This guide is the runbook:
> topologies, storage, TLS, auth, CDN, backup, capacity, monitoring, and
> the security checklist.

## Topologies

1. **Compose stack** (recommended): `cd deploy && cp ../.env.example .env &&
   docker compose up -d` — registry + MinIO + Caddy, TLS automatic, MinIO
   never exposed. See `docs/registry/deployment.md`.
2. **Bare binary**: the release's `registry` binary with a config file —
   `registry --config registry.yaml`. The fs backend is the default store
   (`docs/spec/registry-blobstore.md`); the shutdown protocol applies (see
   Stopping, below).

## Storage

- **fs backend**: `store.backend: fs`, `store.root` — blobs land as
  `blobs/sha256/<hex>` with atomic rename installs; corrupted or partial
  writes never enter the store. Back up the whole `data_dir` (SQLite) plus
  `store.root` (blobs).
- **S3/MinIO**: `store.backend: s3` with `store.s3.{endpoint, bucket,
  region, access_key, secret_key, path_style, prefix}` — path-style
  addressing is what MinIO wants (`docs/spec/registry-s3.md`). The server
  checks the bucket at startup and **fails loudly** if it is missing.
  Presigned GET redirects (307) serve blobs when configured — the CDN must
  pass them through (see Caching).

> **Never expose MinIO.** The registry is the single entrypoint: MinIO's
> port is not published in the compose stack, and its credentials live only
> in the registry's environment. If MinIO is reachable, anyone with the
> credentials bypasses every auth check the registry performs — the bucket
> is the blob store, and the registry's tokens mean nothing to it. Publish
> only the registry; keep MinIO on the internal network and its keys in
> `.env` (never committed).

## Authentication

`auth.enabled: true` in production, with pre-shared accounts under
`auth.users` (v0.1 signs HS256 tokens for those accounts; no OAuth —
decision D6). Every push and every authenticated read rides Bearer tokens
minted by `/token` (`docs/spec/registry-auth.md`).

- **Rotation**: restart with a new `auth.signing_key` (or
  `signing_key_file`) — existing tokens invalidate immediately and clients
  simply re-authenticate. MinIO credentials rotate the same way.
- **Reverse proxy discipline**: the proxy must pass `Authorization`,
  `WWW-Authenticate`, and `Docker-Content-Digest` headers through
  untouched; rewriting any of them breaks the Bearer dance and digest
  verification.
- The token endpoint requires Basic auth over TLS — never front it with
  plain HTTP on a public domain.

## TLS

Caddy in the compose stack obtains a Let's Encrypt certificate for
`REGISTRY_DOMAIN` automatically; `REGISTRY_DOMAIN=localhost` uses the
internal CA (development only — clients need `--tls-verify=false` for it).
Behind your own proxy: terminate TLS at the proxy, keep the registry on the
internal network, and make sure the `Host` header reaches the registry
unchanged (the token realm's URL is built from the challenge).

## Caching (CDN)

The registry's cache policy is in `docs/spec/registry-cache.md`; a CDN in
front must honor it, not fight it:

| Content | Policy | Why |
| --- | --- | --- |
| Blobs (`/v2/<name>/blobs/<digest>`) | `public, max-age=31536000, immutable`, ETag = the digest | digest-addressed content never changes — cache it forever |
| Tag manifests (`/v2/<name>/manifests/<tag>`) | `max-age=60, must-revalidate`, ETag = the digest | tags are mutable; 60 s is the staleness budget |
| `/token`, `/metrics`, `/api/v1/resolve` | **do not cache** | tokens are credentials; metrics are per-instance |

A CDN in front of Caddy passes the policy headers through untouched. S3
presigned redirects (307) may point at the object store — CDN rules for
`/v2/…/blobs/…` must not swallow the redirect response itself.

## Backup and restore

The state is two trees: `data_dir` (SQLite: repositories, manifests, tags,
upload sessions, metrics) and the blob store (`store.root` or the MinIO
bucket).

**Stop → copy → start** (the only safe order — the server holds SQLite in
WAL mode and uploads stream to temp files):

```console
$ touch "$DATA_DIR/registry.shutdown"      # the documented stop protocol
$ # wait for the process to exit; the drain is clean
$ tar -czf backup-$(date +%F).tgz "$DATA_DIR" "$STORE_ROOT"
$ rm "$DATA_DIR/registry.shutdown"         # per your own procedure, e.g. mv to /tmp
$ registry --config registry.yaml &
$ curl -sf "$URL/readyz"                   # 200 = migrations done, store reachable
```

(The `rm` above is the operator's own call — the marker file is a control
file, not data.) On S3, back up the bucket with object versioning or
cross-bucket replication instead of tarballs, and always back up `data_dir`
separately — SQLite and the bucket are consistent only as a pair.

**Restore**: place both trees, start the server, hit `/readyz`, then pull a
known image by digest and compare (`skopeo inspect --raw
docker://<host>/<repo>@sha256:…`). Migrations are append-only and idempotent
— a restored database replays nothing and just serves.

## Capacity and blob cleanup

- **Upload sessions expire**: abandoned pushes (the `.part` files behind
  them) are cleaned when their expiry passes — no operator action.
- **Orphaned blobs accumulate**: blobs uploaded but never referenced by a
  manifest (a push aborted between upload and manifest PUT) stay in the
  store. v0.1 has no garbage collector — plan capacity accordingly and
  audit with SQLite:

  ```sql
  -- blobs no manifest in this repository references (read-only)
  SELECT b.digest, b.size FROM blobs b
  WHERE NOT EXISTS (
    SELECT 1 FROM manifests m
    WHERE m.repository_id = b.repository_id
      AND (m.body LIKE '%' || replace(b.digest, 'sha256:', '') || '%')
  );
  ```

  Deletion is a manual, deliberate act — remove the row, the store object,
  and its link atomically only while the server is stopped, and only for
  blobs this query names. The spec's blob semantics never depend on orphans
  existing, but a manifest re-push might reference one.
- **Limits**: `limits.max_body_bytes` (default 16 MiB), `max_header_bytes`,
  `read_timeout`, `idle_timeout` cap request sizes and stalls; sizes are
  config, not code (`docs/spec/registry-config.md`).

## Monitoring

- **`/healthz`** — the process is up (unauthenticated).
- **`/readyz`** — migrations applied, store reachable (what your
  orchestrator gates on; compose wires it as the healthcheck).
- **`/metrics`** — Prometheus text (unauthenticated, counts only):
  `pokerface_requests_total`, `errors_total`, `upload_bytes_total`,
  `download_bytes_total`, and the request latency histogram
  (`docs/spec/registry-metrics.md`). Scrape it:

  ```yaml
  scrape_configs:
    - job_name: pokerface-registry
      static_configs:
        - targets: ["registry.internal:8080"]
  ```

- **Logs** are slog JSON on stdout: one access line per request (ts, request
  id, method, path, status, duration, bytes — never the query, headers, or
  bodies, so no token or signature can leak) and a `warn` audit record per
  authentication failure (`event=auth_failure` with a reason that names a
  state, not a credential).

## Security checklist

- [ ] `auth.enabled: true`; a strong `signing_key` (or `signing_key_file`);
      users are pre-shared, no OAuth.
- [ ] MinIO **not** reachable from outside the internal network; its keys
      only in `.env`/secrets, never committed, never logged.
- [ ] TLS on every non-loopback hop; the token endpoint never plain-HTTP on
      a public domain.
- [ ] The shutdown marker path is writable only by the operator (it stops
      the server — treat it like a control socket).
- [ ] The proxy passes `Authorization` / `WWW-Authenticate` /
      `Docker-Content-Digest` through untouched; no caching of `/token` or
      `/metrics`.
- [ ] `metrics` is safe to expose (counts only), but check your own policy.
- [ ] No secrets in logs: the access log never records queries/headers;
      settings summaries redact; audit records name states, not credentials.
- [ ] The `.env` file holds real credentials — never committed
      (`.env.example` carries placeholders only).

## Troubleshooting

The symptom → cause → remedy matrix lives in `docs/troubleshooting.md`
(T4.15). The short version: `connection refused` is a listen mismatch, 401
with `insufficient_scope` means the token lacks the action, and
`MANIFEST_BLOB_UNKNOWN` means a push died between blob upload and manifest
PUT — re-push (it is idempotent).
