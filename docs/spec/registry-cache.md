# Registry Cache Headers and CDN Behavior (T2.15)

> Status: v0.1, implemented by `registry/cache.emo` (the policy) wired into
> `registry/blobs.emo` and `registry/manifests.emo`. Tests:
> `test/registry_cache.emo`.

## The policy

| Content | ETag | Cache-Control |
| --- | --- | --- |
| Blob (`GET|HEAD …/blobs/<digest>`) | `"sha256:…"` (the digest) | `public, max-age=31536000, immutable` |
| Manifest by digest | `"sha256:…"` | `public, max-age=31536000, immutable` |
| Manifest by tag | `"sha256:…"` | `public, max-age=60, must-revalidate` |
| Presigned 307 redirect | — | `no-cache` |

- Blobs are content-addressed, so the digest is the validator and the cache
  key: a CDN can hold a layer for a year and a re-pull of the same layer is
  the same bytes, always.
- Manifests are mutable through tags. A tag response stays fresh for at most
  a minute and `must-revalidate` sends the CDN back to the origin after
  that — a tag update therefore takes effect within a minute everywhere,
  and never pins an old manifest longer. A manifest fetched **by digest** is
  immutable and caches like a blob.
- `If-None-Match` hits answer `304 Not Modified` with the same validators
  and no body. The comparison follows RFC 7232: `*`, weak `W/` prefixes,
  comma lists, and optional quoting all match; a mismatch answers 200 with
  the fresh body.
- A tag update invalidates immediately on the origin: the next request
  revalidates against the new digest, and the old ETag misses. A CDN that
  honors `max-age=60` serves stale for at most those sixty seconds; one
  configured to revalidate on `must-revalidate` sees updates right away.
- The 307 to a presigned URL is `no-cache`: a cached redirect could hand out
  an expired signature. The object bytes themselves are served by MinIO with
  its own headers — set the bucket/CDN policy there for blob-edge caching
  ([registry-s3.md](registry-s3.md), and the operations guide in T4.12).

## Tests

`test/registry_cache.emo` covers: the ETag matcher table (quoted/unquoted,
weak, lists, `*`), blob GET/HEAD headers, blob 304 on quoted/star/weak and
the 200 on a mismatch, no-cache on the 307, the short policy on tag
manifests versus the immutable one on digest manifests, manifest 304, and
HEAD carrying the validators.
