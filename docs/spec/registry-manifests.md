# Registry Manifests (T2.8)

> Status: v0.1, implemented by `registry/manifests.emo` (route + SQLite
> lookup). Tests: `test/registry_manifests.emo` (handler with a fake store)
> and the compiled `registry/db_selftest.emo` (the real `DbManifests`).

## Route

`GET|HEAD /v2/<name>/manifests/<reference>`

- `<name>` is a repository name and may contain slashes; the route splits on
  `/manifests/`, so `acme/team/app` works.
- `<reference>` is one path segment: a tag, or a digest (`sha256:<64 hex>`).
- Any other method answers 405 with `Allow: GET, HEAD` and an `UNSUPPORTED`
  error.

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

## Storage access

`DbManifests` opens a short-lived SQLite connection per request (httpd runs one
process per connection, so a shared handle would be forked into every request
process) and closes it before answering. The handler depends on the
`ManifestStore` interface, so the routing, Accept, HEAD, and verification
logic run in the interpreter against a fake in `test/registry_manifests.emo`;
the compiled `db_selftest` exercises `DbManifests` against a real database
(tag and digest reads, unknown tag, unknown repository).
