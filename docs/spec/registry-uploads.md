# Registry Blob Uploads (T2.10/T2.11)

> Status: v0.1, implemented by `registry/uploads.emo`. Tests:
> `test/registry_uploads.emo` (routes with fakes) and the compiled
> `registry/db_selftest.emo` (`DbUploadSessions`).

## The flows

The OCI distribution upload has three shapes; the registry answers all of
them.

**Monolithic, POST then PUT** (T2.10): `POST /v2/<name>/blobs/uploads/`
opens a session —

```http
HTTP/1.1 202 Accepted
Location: /v2/acme/app/blobs/uploads/9f2c…64-hex
Docker-Upload-UUID: 9f2c…64-hex
Content-Length: 0
```

(the path without the trailing slash is accepted as the same collection; the
Location is relative) — and `PUT <Location>?digest=sha256:<hex>` uploads the
whole body. A `POST` that already carries `?digest=` is the spec's
single-request monolithic upload: session, bytes, and completion in one
round trip. In both cases the body is hashed **before anything is stored**: a
mismatch answers

```http
HTTP/1.1 400 Bad Request
{"errors":[{"code":"DIGEST_INVALID","message":"digest mismatch",
  "detail":"the body hashes to sha256:…, not sha256:…"}]}
```

and neither the blob store nor the session changes — nothing partial
survives a failed upload. Success answers

```http
HTTP/1.1 201 Created
Location: /v2/acme/app/blobs/sha256:9df4d8dd…
Docker-Content-Digest: sha256:9df4d8dd…
```

**Chunked** (T2.11): `PATCH` appends each chunk, `GET` reports the offset,
`PUT` closes the session — with the final chunk riding the PATCHes or the
PUT itself:

- `PATCH <Location>` carries `Content-Range: <start>-<end>` (the spec's bare
  form, inclusive on both ends, `^[0-9]+-[0-9]+$`). The start must equal the
  session's recorded offset; an out-of-order chunk answers

  ```http
  HTTP/1.1 416 Requested Range Not Satisfiable
  {"errors":[{"code":"BLOB_UPLOAD_INVALID","message":"chunk does not
    continue the upload at its current offset","detail":"uploads: offset
    mismatch: session holds 11 bytes, the chunk starts at 0"}]}
  ```

  and an end that disagrees with the body length answers
  `400 BLOB_UPLOAD_INVALID`. A PATCH **without** Content-Range streams
  blindly — the shape `skopeo` uses for whole-layer uploads.

- Each successful PATCH answers `202 Accepted` with `Location`,
  `Docker-Upload-UUID`, and `Range: 0-<last byte>` (the header is omitted
  while the session holds nothing, since `0-0` would claim one byte).

- `GET <Location>` answers `204 No Content` with the same headers — the
  resume path after a 416.

- The closing `PUT ?digest=` MAY carry the final chunk with its own
  Content-Range (same offset rules; an out-of-order final chunk is 416). The
  digest covers everything the session received: the part file is streamed
  into the blob store (`put_file`, which hashes while copying — both
  backends' mismatch failures are recognized and mapped to
  `400 DIGEST_INVALID`), the blob link and completion commit atomically, and
  the part file is removed. A mismatch leaves the session pending with its
  data intact, so the client can inspect (`GET`) and restart.

- `DELETE <Location>` cancels: `204 No Content`, the session becomes
  `cancelled` and every later PATCH/GET/PUT/DELETE on it answers
  `404 BLOB_UPLOAD_UNKNOWN`. (The OCI error envelope rides the 4xx/5xx
  answers throughout.)

Wrong methods answer 405: the collection serves `POST`, the item serves
`GET, PATCH, PUT, DELETE`. A PUT/GET/DELETE to another repository's path —
or to an unknown, completed, or cancelled id — is
`404 BLOB_UPLOAD_UNKNOWN`.

## Sessions and chunk data

- Sessions live in the `uploads` table (`pending` → `completed` /
  `cancelled`); migration 2 added `offset_bytes`, the authoritative count of
  received bytes. The id is 64 hex characters over pid and monotonic time —
  unique across httpd's per-connection processes without shared mutable
  state.
- Chunk data accumulates in `<data_dir>/uploads/<id>.part`
  (`os.open_append`). The database offset is the reference every
  Content-Range is checked against; a crash between the file append and the
  offset commit leaves the file longer than the recorded offset, which the
  digest check at PUT time converts into a clean 400 (restart the upload) —
  no corruption can be served.
- Concurrency: every append runs inside `BEGIN IMMEDIATE`, so writers
  serialize and the offset check is a compare-and-set — two PATCHes claiming
  the same offset cannot both land; the loser answers 416. The PUT
  finalization (store copy, link, completion) holds the same window, which
  serializes the registry's writers for the duration — a deliberate v0.1
  tradeoff; per-session exclusion without the global lock is future work.
- Expiry: every `start` first deletes `pending` sessions whose `expires_at`
  passed (an indexed sweep) and removes their part files, so abandoned
  uploads cannot accumulate. The TTL is a module constant
  (`session_ttl_seconds`, 24h) for v0.1; a config knob is a follow-up.

## Repository names

`POST` creates the repository row, so `<name>` is validated against the OCI
grammar — per path component, `[a-z0-9]+` separated by `.` or `_` or `__`
or runs of `-`, at most 255 characters — and a violation answers
`400 NAME_INVALID` without creating anything.

## Sizes and shared routing

- Size limits ride the server framing: a body over `limits.max_body_bytes`
  ([registry-config.md](registry-config.md)) is answered **413** by httpd
  before a handler runs, for both `Content-Length` and chunked framing. The
  stored size comes from the store's verified `put`/`put_file`.
- The uploads family shares the `/blobs/` prefix with the blob GET route
  ([registry-blobs.md](registry-blobs.md)); the router checks the upload
  routes **first**.
- `DbUploadSessions` opens a short-lived SQLite connection per request —
  httpd runs one process per connection, so a shared handle would be forked
  into every request process. The handler depends on the `UploadSessions`
  interface, so the routes run in the interpreter against fakes.

## curl examples

```console
# chunked, with Content-Range on every chunk
$ curl -i -X POST http://127.0.0.1:5000/v2/acme/app/blobs/uploads/
HTTP/1.1 202 Accepted
Location: /v2/acme/app/blobs/uploads/9f2c…

$ curl -i -X PATCH --data-binary @chunk1.bin -H "Content-Range: 0-1048575" \
    -H "Content-Length: 1048576" \
    "http://127.0.0.1:5000/v2/acme/app/blobs/uploads/9f2c…"
HTTP/1.1 202 Accepted
Range: 0-1048575

$ curl -i -X PATCH --data-binary @chunk2.bin -H "Content-Range: 1048576-2097151" \
    -H "Content-Length: 1048576" \
    "http://127.0.0.1:5000/v2/acme/app/blobs/uploads/9f2c…"

# ask for the offset (e.g. after a 416), then continue from Range + 1
$ curl -i "http://127.0.0.1:5000/v2/acme/app/blobs/uploads/9f2c…"
HTTP/1.1 204 No Content
Range: 0-1048575

# close the session (the final chunk may also ride the PUT with Content-Range)
$ curl -i -X PUT --data-binary @chunk3.bin \
    "http://127.0.0.1:5000/v2/acme/app/blobs/uploads/9f2c…?digest=sha256:…"
HTTP/1.1 201 Created
Docker-Content-Digest: sha256:9df4d8dd…

# give up and release the session
$ curl -i -X DELETE "http://127.0.0.1:5000/v2/acme/app/blobs/uploads/9f2c…"
HTTP/1.1 204 No Content
```

## Tests

`test/registry_uploads.emo` covers: the 202 session (both path forms),
single-request POST upload, streaming and ranged PATCHes, out-of-order and
gapped chunks (416), Content-Range/body disagreements and malformed ranges
(400), GET progress (204, `Range` present once anything was received),
DELETE (204, the session unusable afterwards, second DELETE 404), foreign
repository paths, store/append/lookup/completion/cancel failures (500),
multi-chunk flows against the real `LocalStore` with real part files
(PATCH+PATCH+PUT, the final chunk riding the PUT, the skopeo streaming
shape, digest mismatch keeping the session and its data, the empty blob),
duplicate uploads keeping one copy, the name-grammar table, method
mismatches, path shapes, Content-Range parsing, and router dispatch. The
compiled `db_selftest` covers the SQLite session layer: id shape, offsets
advancing and round-tripping, the part file holding the chunks in order,
out-of-order appends, completion linking the blob and removing the part
file, cancellation, and the expiry sweep cleaning rows and files.
