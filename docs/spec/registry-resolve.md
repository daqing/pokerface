# Registry Resolve / Metadata API (T2.13)

> Status: v0.1, implemented by `registry/resolve.emo` (route + metadata
> assembly) and the dispatch/auth wiring in `registry/router.emo`. Tests:
> `test/registry_resolve.emo`.

## Route

`GET /api/v1/resolve?repository=<name>&tag=<tag>`

- Missing or empty query parameters answer `400`; a repository name that
  fails the OCI grammar answers `400 NAME_INVALID`; a tag the repository
  does not have answers `404 MANIFEST_UNKNOWN` with `<repo>:<tag>` as the
  detail. Any other method is a 405.
- Success answers `application/json`:

  ```json
  {
    "repository": "acme/app",
    "tag": "v3",
    "digest": "sha256:720e8b95…",
    "media_type": "application/vnd.oci.image.manifest.v1+json",
    "platforms": [{"architecture": "amd64", "os": "linux"}],
    "revision": "0123abcd"
  }
  ```

- `platforms` comes from an index's own entries (`variant` joins when the
  index carries one) or, for an image manifest, from its **config blob**
  (architecture/os). `revision` is the document's
  `org.opencontainers.image.revision` annotation, present only when set.
- No storage credential ever appears in a response — the endpoint answers
  metadata only, never presigned URLs or store settings. The pokerface CLI
  uses it as the read-only fallback when Git metadata is missing.

## Authentication

The route rides the same gate as /v2/: with auth enabled it needs
`repository:<name>:pull` for the queried repository, answering the standard
401 challenge (scope in `WWW-Authenticate`) for anonymous, wrong-repository,
or pull-less tokens. Without auth it is open.

## Tests

`test/registry_resolve.emo` covers: the full metadata document (digest,
media type, config-derived platforms, revision), the absent-revision shape,
index platforms with variants, missing tag/parameters/name (400/404), store
failures (500), GET-only, and the router legs — dispatch without auth, the
401 challenge with auth enabled, and the pull-scope pass.
