# Registry S3 / MinIO Backend (T2.6)

> Status: v0.1, implemented by `registry/s3_blobstore.emo` on top of
> `registry/sigv4.emo` (T2.5) and the T2.4 BlobStore interface. Tests:
> `test/registry_s3.emo` — protocol tests with an injected transport plus a
> real round trip when `POKERFACE_TEST_S3_ENDPOINT` is set.

## Configuration

`store.backend: s3` selects the backend; `store.root` is then unused. The
`store.s3` mapping:

| Field | Default | Notes |
| --- | --- | --- |
| `endpoint` | — | required; `http://host[:port]` or `https://host[:port]`, no path |
| `bucket` | — | required; the bucket must already exist |
| `region` | `us-east-1` | SigV4 credential scope |
| `access_key` | — | required; `POKERFACE_REGISTRY_S3_ACCESS_KEY` keeps it out of the file |
| `secret_key` | — | required; `POKERFACE_REGISTRY_S3_SECRET_KEY` likewise |
| `path_style` | `true` | `endpoint/bucket/key`; `false` gives `bucket.endpoint/key` |
| `prefix` | `""` | key prefix; surrounding slashes are trimmed |
| `ca_file` | `""` | replaces the system trust store with this CA bundle |
| `verify_tls` | `true` | `false` disables certificate verification (development only) |
| `presign_ttl` | `900` | default validity for `presign_get`, seconds; 0–604800, `0` disables presigning (blobs stream through the registry) |

The service summary prints the endpoint, bucket, prefix, and
`access_key=<set>` — never the key itself or the secret.

## Keys

Objects are content-addressed: `[prefix/]sha256/<hex>`. Path-style addressing
puts the bucket in the path (`<endpoint>/<bucket>/<prefix>/sha256/<hex>`);
virtual-host style puts it in the host (`<bucket>.<endpoint>/<prefix>/sha256/<hex>`).

## Startup

`open` builds the signer and transport, then sends a signed `HEAD` for the
bucket. A missing bucket exits start-up with its name and the endpoint
("create it, or point store.s3.bucket at an existing bucket"); a 403 names the
two credential settings without their values. `/readyz` repeats that HEAD per
request.

## Requests

Every request is signed with SigV4. The signed header set is `host`,
`x-amz-content-sha256`, and whatever else the call adds (`content-type`,
`range`, the session token when configured). The Host value the signer uses is
the one the HTTP client puts on the wire — the default port is dropped
(`http://host:80` signs `host`), so the signature and the received Host agree.
Because the stdlib client writes Host itself, the signed Host entry is removed
from the transmitted header list.

`PUT` sends `application/octet-stream` and the payload's SHA-256; `GET`,
`DELETE`, and the bucket probe sign the empty-body hash. Bodies are read
whole — the stack has no streaming HTTP — which is also the upload model
(T2.10).

`head` uses a ranged `GET` (`bytes=0-0`) rather than `HEAD`: the stdlib HTTP
client reads `Content-Length` bytes even on a HEAD response, and S3 announces
the object size there with no body. The 206's `Content-Range` supplies the
total; a 416 (empty object) falls back to a plain GET, and a server that
ignores Range is accepted by counting the body.

## Retries and errors

Transport failures and 5xx answers retry three times with a short backoff
(0.1 s, 0.2 s); 4xx answers do not. Messages name the method, URL, and the S3
error `<Code>` when the body carries one — never the body itself (it can echo
the access key id) and never either key:

```text
s3: PUT http://minio:9000/bucket/sha256/… failed: HTTP 400 (InvalidRequest)
s3: GET https://… failed after 3 attempts: connection refused
s3: bucket 'missing' not found at http://minio:9000 (create it, or point store.s3.bucket at an existing bucket)
```

A 404 on an object maps to the BlobStore's `blobstore: not found:` error; a
404 on delete answers `false`; a missing bucket at start-up is a hard error.

## Presigning

`presign_get(digest, ttl)` returns a direct URL signed with `UNSIGNED-PAYLOAD`
and `host` as the only signed header, so a route can answer 307 without
proxying the bytes. A ttl of `0` (or less) uses `store.s3.presign_ttl`; values
above AWS's 604800 s ceiling are clamped. `store.s3.presign_ttl: 0` disables
presigning outright — the empty answer routes blob GETs through the registry's
own store read, which is what a single-entrypoint deployment (one public
Caddy, MinIO on the internal network) needs. The URL's validity window is
`[signed_at, signed_at + ttl)` and the policy carries the secret nowhere — the
signature is the only credential material in it.

## Tests

`test/registry_s3.emo` injects a transport and pins the protocol: bucket HEAD,
missing-bucket and access-denied messages (and their redaction), PUT URL/body/
headers, digest-mismatch rejection before sending, GET/HEAD/DELETE mappings,
the range header and the 200-fallback, retries for drops and 5xx, the error
`<Code>`, presign URL shape and expiry math, virtual-host addressing, and
path-prefix key building.

The last test runs a live round trip when `POKERFACE_TEST_S3_ENDPOINT`,
`_BUCKET`, `_ACCESS_KEY`, and `_SECRET_KEY` are set: put, get, head, range,
presigned fetch, an expired presigned fetch (403), and delete. Point those at
MinIO to use the real service; `scripts/e2e-s3.sh` runs the same test against
`mock/s3_fixture.emo`, a local endpoint that verifies SigV4 signatures and
presigned expiries and stores objects on disk. Without the endpoint the test
returns without touching the network.
