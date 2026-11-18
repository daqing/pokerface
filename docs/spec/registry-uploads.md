# Registry Blob Uploads (T2.10)

> Status: v0.1, implemented by `registry/uploads.emo`. Tests:
> `test/registry_uploads.emo` (routes with fakes) and the compiled
> `registry/db_selftest.emo` (`DbUploadSessions`).

## The flow

The minimal OCI distribution upload, as `skopeo` and `oras` drive it:

1. `POST /v2/<name>/blobs/uploads/` opens a session:

   ```http
   HTTP/1.1 202 Accepted
   Location: /v2/acme/app/blobs/uploads/9f2c…64-hex
   Docker-Upload-UUID: 9f2c…64-hex
   Content-Length: 0
   ```

   The path without the trailing slash (`/v2/<name>/blobs/uploads`) is
   accepted as the same collection. The Location is relative; the client
   resolves it against the registry URL.

2. `PUT <Location>?digest=sha256:<hex>` uploads the whole body. The registry
   hashes the body **before anything is stored**: a mismatch answers

   ```http
   HTTP/1.1 400 Bad Request
   {"errors":[{"code":"DIGEST_INVALID","message":"digest mismatch",
     "detail":"the body hashes to sha256:…, not sha256:…"}]}
   ```

   and neither the blob store nor the session changes — a failed upload
   leaves nothing partial behind, and the session stays pending so the
   client can retry.

3. On success the bytes land in the blob store, the `blobs` row links the
   digest into the repository, and the session is completed atomically:

   ```http
   HTTP/1.1 201 Created
   Location: /v2/acme/app/blobs/sha256:9df4d8dd…
   Docker-Content-Digest: sha256:9df4d8dd…
   Content-Length: 0
   ```

A `POST` that already carries `?digest=` is the spec's single-request
monolithic upload: session, bytes, and completion in one round trip, with
the same 201/400 answers. (On a 400 the just-created session stays pending
and simply expires.)

## Sessions

- Sessions live in the `uploads` table (`pending` → `completed`; `cancelled`
  is T2.11's DELETE). The id is 64 hex characters over pid and monotonic
  time — unique across httpd's per-connection processes without shared
  mutable state.
- `PUT` to an unknown id, to a session whose state is no longer `pending`
  (already completed, or raced), or to another repository's path answers
  `404 BLOB_UPLOAD_UNKNOWN`.
- Completing marks the session under a `state = 'pending'` guard and links
  the blob in the same transaction, so a racing twin loses the transition
  and answers 404; the blob link is never double-inserted
  (`INSERT OR IGNORE`).
- Expiry: every `start` first deletes `pending` sessions whose
  `expires_at` passed (an indexed sweep), so abandoned sessions cannot
  accumulate. The TTL is a module constant (`session_ttl_seconds`, 24h) for
  v0.1; a config knob is a follow-up.

## Repository names

`POST` creates the repository row, so `<name>` is validated against the
OCI grammar — per path component, `[a-z0-9]+` separated by `.` or `_` or
`__` or runs of `-`, at most 255 characters — and a violation answers
`400 NAME_INVALID` without creating anything.

## Sizes, methods, and shared routing

- Size limits ride the server framing: a body over `limits.max_body_bytes`
  ([registry-config.md](registry-config.md)) is answered **413** by httpd
  before a handler runs, for both `Content-Length` and chunked framing. The
  stored size comes from the store's verified `put`.
- Both methods on the wrong path shape answer 405: the collection serves
  `POST`, the item serves `PUT` (T2.11 adds `GET`, `PATCH`, `DELETE` to the
  item).
- The uploads family shares the `/blobs/` prefix with the blob GET route
  ([registry-blobs.md](registry-blobs.md)); the router checks the upload
  routes **first**.
- `DbUploadSessions` opens a short-lived SQLite connection per request —
  httpd runs one process per connection, so a shared handle would be forked
  into every request process. The handler depends on the `UploadSessions`
  interface, so the routes run in the interpreter against fakes.

## curl example

```console
$ curl -i -X POST http://127.0.0.1:5000/v2/acme/app/blobs/uploads/
HTTP/1.1 202 Accepted
Location: /v2/acme/app/blobs/uploads/9f2c…
Docker-Upload-UUID: 9f2c…

$ curl -i -X PUT --data-binary @layer.tar.gz \
    "http://127.0.0.1:5000/v2/acme/app/blobs/uploads/9f2c…?digest=sha256:$(sha256sum layer.tar.gz | cut -d' ' -f1 | sed 's/^/sha256:/')"
HTTP/1.1 201 Created
Location: /v2/acme/app/blobs/sha256:9df4d8dd…
Docker-Content-Digest: sha256:9df4d8dd…

$ curl -I http://127.0.0.1:5000/v2/acme/app/blobs/sha256:9df4d8dd…   # finds it
```

## Tests

`test/registry_uploads.emo` covers: the 202 session (both path forms),
single-request POST upload, PUT completion with headers and recorded size,
missing/invalid digest parameters, digest mismatch storing nothing, unknown
and completed sessions, foreign-repository paths, store/lookup/completion
failures (500), duplicate uploads keeping one copy (fake store and the real
`LocalStore`, including the empty blob), the name-grammar table, method
mismatches, path shapes, and router dispatch ahead of the blob GET route.
