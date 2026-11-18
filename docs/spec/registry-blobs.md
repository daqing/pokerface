# Registry Blobs (T2.9)

> Status: v0.1, implemented by `registry/blobs.emo`. Tests:
> `test/registry_blobs.emo` (route with fakes) and the compiled
> `registry/db_selftest.emo` (`DbBlobLinks`).

## Route

`GET|HEAD /v2/<name>/blobs/<digest>`

- `<name>` may contain slashes; the route splits on `/blobs/`.
- `<digest>` must be `sha256:<64 lowercase hex>`; anything else is
  `400 DIGEST_INVALID` before any lookup.
- Other methods answer 405 with `Allow: GET, HEAD`.

The blob must be linked to the repository — the `blobs` table is that
relation — and present in the backend. Either miss is
`404 BLOB_UNKNOWN` with `<repository>@<digest>` as the detail.

## S3: 307 to a presigned URL

With the S3 backend, GET answers

```http
HTTP/1.1 307
Location: http://minio:9000/pokerface/blobs/sha256/…?X-Amz-Algorithm=AWS4-HMAC-SHA256&…&X-Amz-Signature=…
Docker-Content-Digest: sha256:…
Content-Length: 0
```

so the client downloads straight from the object store; the registry never
proxies layer bytes. The URL's lifetime is `store.s3.presign_ttl`
([registry-s3.md](registry-s3.md)). Existence is checked first (a ranged head
on the store): a presigned URL for a missing object would answer 404 at the
CDN instead of here.

## Local filesystem: 200 with the bytes

```http
HTTP/1.1 200 OK
Content-Type: application/octet-stream
Docker-Content-Digest: sha256:9df4d8dd…
Content-Length: 20

hello pokerface blob
```

`presign_get` answers `""` for this backend, and the route falls back to
`store.get` — the T2.4 contract.

## HEAD

HEAD never redirects: it answers metadata directly in both modes, with
`Content-Type`, `Docker-Content-Digest`, and `Content-Length` taken from the
store's size record (falling back to the database's recorded size when the
backend does not know it). A redirect would cost the client a second request
just to learn a length.

## Lookups

`BlobLinks.linked(repository, digest)` is the lookup interface; `DbBlobLinks`
opens a short-lived SQLite connection per request and answers the recorded
size. The handler depends on the interface, so the route runs in the
interpreter against fakes; the compiled `db_selftest` covers the SQLite
implementation (linked digest, unlinked digest, unknown repository).

## Tests

`test/registry_blobs.emo` covers: local GET with the headers, S3 GET with the
presigned Location, HEAD in both modes (and the size fallback), missing links,
a linked blob missing from the store, store/link failures (500), a store
not-found during GET, invalid digests (400), method mismatch (405), path
shapes, and router dispatch with the common headers.
