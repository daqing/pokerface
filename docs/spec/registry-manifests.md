# Registry Manifests (T2.8/T2.12)

> Status: v0.1, implemented by `registry/manifests.emo` (route + SQLite
> lookup + write half). Tests: `test/registry_manifests.emo` (GET/HEAD with a
> fake store), `test/registry_manifest_put.emo` (PUT with fakes), and the
> compiled `registry/db_selftest.emo` (the real `DbManifests`).

## Route

`GET|HEAD /v2/<name>/manifests/<reference>`

- `<name>` is a repository name and may contain slashes; the route splits on
  `/manifests/`, so `acme/team/app` works.
- `<reference>` is one path segment: a tag, or a digest (`sha256:<64 hex>`).
- Any other method answers 405 with `Allow: GET, HEAD, PUT` and an
  `UNSUPPORTED` error.

Examples:

```console
$ curl -i http://127.0.0.1:5000/v2/acme/app/manifests/latest
HTTP/1.1 200 OK
Content-Type: application/vnd.oci.image.manifest.v1+json
Docker-Content-Digest: sha256:eca47388…
Content-Length: 246
…

$ curl -I http://127.0.0.1:5000/v2/acme/app/manifests/latest
HTTP/1.1 200 OK
Content-Type: application/vnd.oci.image.manifest.v1+json
Docker-Content-Digest: sha256:eca47388…
Content-Length: 246
```

HEAD carries the same headers and no body (the handler sets `Content-Length`
explicitly; httpd strips the body).

## Resolution

1. The repository name becomes a `repositories.id`; unknown → 404.
2. A digest-shaped reference is used directly; a tag goes through the `tags`
   table.
3. The stored body, media type, and digest come from `manifests`.

Any miss answers `404` with `MANIFEST_UNKNOWN` and the detail
`<repository>:<reference>`.

A reference that starts with `sha256:` but is not a valid digest (wrong
length, non-hex, uppercase) answers `400 DIGEST_INVALID` rather than a 404.

## Integrity

Every read hashes the stored bytes and compares them with the digest the row
(and the response header) names. A mismatch is the server's own corruption —
it would serve bytes that contradict their digest — so the answer is
`500 UNKNOWN` with both digests in the detail, never the bytes.

## Accept

An absent `Accept` accepts anything. Otherwise the header is split on commas,
parameters (`;q=…`) and surrounding whitespace are stripped, and the request
is served only when a listed type equals the stored media type
(case-insensitively) or is `*/*`. A mismatch answers 404 `MANIFEST_UNKNOWN`
with the stored type in the detail — the client asked for something this
registry cannot give it.

Indexes are served like any other manifest: the stored bytes are returned
verbatim, so a multi-arch index reaches the client intact.

## PUT (T2.12)

`PUT /v2/<name>/manifests/<tag|digest>` stores the bytes **verbatim** and,
for a tag reference, points the tag at the digest:

- Validation runs before any write. The body must parse as one of the four
  supported media types (OCI manifest/index, Docker v2 manifest/list — the
  T2.3 parser; Content-Type and the body's `mediaType` must agree, one may
  stand in for the other). A digest reference must match the body's hash
  (`400 DIGEST_INVALID`, both digests named); a tag reference must satisfy
  the OCI tag grammar `[a-zA-Z0-9_][a-zA-Z0-9._-]{0,127}`
  (`400 TAG_INVALID`); the repository name is checked because PUT creates
  the row (`400 NAME_INVALID`).
- Every reference the document makes must exist in the repository: a
  manifest's config and layers must be linked blobs, an index's children
  must be stored manifests. The first miss answers

  ```http
  HTTP/1.1 404 Not Found
  {"errors":[{"code":"MANIFEST_BLOB_UNKNOWN","message":"manifest references
    content unknown to the repository","detail":"sha256:…"}]}
  ```

  and nothing is written. The `subject` descriptor is deliberately not
  checked — the distribution spec requires accepting a manifest whose
  subject is absent (the parser drops it).
- Success answers `201 Created` with `Location: /v2/<name>/manifests/<digest>`
  and `Docker-Content-Digest`. Re-pushing identical bytes is a no-op (one
  row). A tag update is a single `INSERT OR REPLACE` — atomic, and a failure
  before it never disturbs the old tag. The manifest row lands before the
  tag write; a crash between the two leaves an untagged manifest row, which
  is harmless.

## Storage access

`DbManifests` opens a short-lived SQLite connection per request (httpd runs one
process per connection, so a shared handle would be forked into every request
process) and closes it before answering. The handler depends on the
`ManifestStore` interface, so the routing, Accept, HEAD, and verification
logic run in the interpreter against a fake in `test/registry_manifests.emo`,
and the PUT flow (parse → digest → references → store → tag) against fakes in
`test/registry_manifest_put.emo`; the compiled `db_selftest` exercises
`DbManifests` against a real database (tag and digest reads, unknown tag,
unknown repository, verbatim writes, re-put no-ops, tag updates).
