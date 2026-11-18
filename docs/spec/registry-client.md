# Registry Client Specification (T1.10)

> Status: v0.1, implemented by `src/registry.emo`. The client speaks the
> subset of the OCI Distribution Spec that the pull path needs: `/v2/` probe,
> Bearer-token authentication, manifest (and index) fetch by tag or digest
> with digest verification, and platform selection from an index.
> Compatibility target: D9 — smoke-tested against our own registry; full
> Docker-client compatibility is not promised.

## Supported media types

| Purpose | Media type |
| --- | --- |
| Image manifest (OCI) | `application/vnd.oci.image.manifest.v1+json` |
| Image index (OCI) | `application/vnd.oci.image.index.v1+json` |
| Image manifest (Docker v2) | `application/vnd.docker.distribution.manifest.v2+json` |
| Manifest list (Docker v2) | `application/vnd.docker.distribution.manifest.list.v2+json` |
| Image config (OCI) | `application/vnd.oci.image.config.v1+json` *(parsed from T1.11 on)* |
| Image config (Docker) | `application/vnd.docker.container.image.v1+json` *(from T1.11)* |
| Layer (OCI, gzipped) | `application/vnd.oci.image.layer.v1.tar+gzip` *(from T1.11)* |
| Layer (Docker, gzipped) | `application/vnd.docker.image.rootfs.diff.tar.gzip` *(from T1.11)* |

Manifest requests carry an `Accept` header listing the four manifest/index
types; the response body's own `mediaType` field is the authoritative answer
for what was fetched, falling back to `Content-Type`.

## Authentication flow

1. `GET <base>/v2/` with `Authorization: Bearer <token>` when a token is
   already known (from settings).
2. `200` → authenticated (possibly anonymously). `401` → the Bearer dance:
   parse `WWW-Authenticate: Bearer realm="…",service="…",scope="…"`
   (`realm` required; only Bearer is supported), fetch
   `<realm>?service=<enc>&scope=<enc>` and read the JSON `token` (or
   `access_token`) field, store the token, and verify with a second probe.
3. Any other probe status, a token endpoint failure, or a probe that stays
   401 after the token is a hard error; there is no Basic-auth fallback in
   v0.1 (T2.14 defines the server side).

`service` and `scope` are percent-encoded (RFC 3986 unreserved characters
pass, uppercase hex for the rest).

## Manifest fetch

`GET <base>/v2/<name>/manifests/<reference>` where `<name>` may contain `/`
and `<reference>` is a tag or a `sha256:` digest. Status handling:

| Status | Meaning |
| --- | --- |
| 200 | Verify `Docker-Content-Digest` (when present) against the body's SHA-256 (constant-time compare); a mismatch is a hard error naming both digests. |
| 401 | Run the dance and retry **once**; the retry rebuilds the headers so the fresh token is actually sent. |
| 404 | `manifest not found (404 MANIFEST_UNKNOWN)`. |
| 3xx | Hard error: "redirects are never followed", naming the `Location`. (The blob path handles 307 deliberately in T1.11; manifests must never be redirected silently.) |
| 5xx | `registry error (status N)`. |
| other | `manifest request returned status N`. |

## Index platform selection

An index body's `manifests[]` entries carry `digest` and
`platform.os` / `platform.architecture`. `select_platform(body, os, arch)`
answers the matching child's digest; a miss is an error listing the
available platforms. A missing `platform` on an entry is surfaced in that
list rather than silently skipped. `variant` is not matched in v0.1.

## Host discipline

Every URL the client builds derives from the configured `base`
(`https://<host>` with no trailing slash) — `/v2/`, manifests, everything.
The token endpoint is the one exception: it lives at the `realm` the
registry itself advertises in the challenge. Redirects would move requests
off both, which is one more reason they are errors here. The mock tests
assert every recorded call starts with the registry or auth host.

## Transport

`Transport` is an injectable interface; `HttpTransport` maps the stdlib
`http` package onto it (one request per call, `timeout` seconds per request,
no redirect following), and `MockTransport` answers from an ordered route
table matched on URL substring plus Authorization state (`any` / `none` /
`contains`) — the same injectable pattern as `CommandRunner` (T1.6) and
`EnvSource` (T1.8). Client fields that change after construction (the
token) live in a `Box`, since class fields freeze after `init`.
