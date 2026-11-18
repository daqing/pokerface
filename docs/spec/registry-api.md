# Registry API Protocol (T2.7)

> Status: v0.1, implemented by `registry/api.emo` (router, error envelope,
> request ids). Tests: `test/registry_api.emo`.

This is the distribution API's outer skin: `/v2/` answers with the API version,
every response carries a request id, and every error is the OCI envelope rather
than plain text — so `docker`, `skopeo`, and `oras` can parse what went wrong.

## `GET /v2/`

```http
HTTP/1.1 200 OK
Docker-Distribution-API-Version: registry/2.0
X-Request-Id: pf-4508-510901862508000
Content-Type: application/json; charset=utf-8
Content-Length: 2

{}
```

`/v2` (no trailing slash) answers the same. Any other method on the route is
`405` with `Allow: GET` and an `UNSUPPORTED` error body.

Unauthenticated mode is this 200. Authentication (T2.14) will turn a missing
token into a `401` with `WWW-Authenticate`; `api.unauthorized(challenge,
detail)` already builds that response (the `UNAUTHORIZED` code, the challenge
header, the JSON body).

## Error envelope

Every error body is:

```json
{"errors":[{"code":"NAME_UNKNOWN","message":"unknown route","detail":"GET /nope"}]}
```

- `code` is one of the OCI distribution codes, exported as constants:
  `BLOB_UNKNOWN`, `BLOB_UPLOAD_INVALID`, `BLOB_UPLOAD_UNKNOWN`,
  `DIGEST_INVALID`, `MANIFEST_BLOB_UNKNOWN`, `MANIFEST_INVALID`,
  `MANIFEST_UNKNOWN`, `NAME_INVALID`, `NAME_UNKNOWN`, `SIZE_INVALID`,
  `TAG_INVALID`, `UNAUTHORIZED`, `DENIED`, `UNSUPPORTED`, `TOOMANYREQUESTS`.
- `message` is a short human-readable sentence.
- `detail` is omitted when empty (the encoder leaves the key out).

Helpers: `error_body`, `error_response(status, code, message, detail)`,
`not_found`, `bad_request`, `method_not_allowed(allow)`, `unauthorized`.

Existing routes and their helpers:

| Situation | Status | Code | Headers |
| --- | --- | --- | --- |
| unknown route (including `/v2/<anything>` until T2.8) | 404 | `NAME_UNKNOWN` | `Content-Type: application/json` |
| method mismatch on `/v2/` | 405 | `UNSUPPORTED` | `Allow`, JSON |
| missing/invalid token (T2.14) | 401 | `UNAUTHORIZED` | `WWW-Authenticate`, JSON |

Health endpoints keep their plain-text bodies (`/healthz`, `/readyz`); the
router decorates them with the common headers like everything else.

## Request ids

Every response carries `X-Request-Id`, on success and errors alike:

- a client-supplied `X-Request-Id` is echoed when it is 1–64 characters of
  `A-Z a-z 0-9 . _ -`; anything else (CR/LF, punctuation, overlong) is replaced,
  so a header cannot be injected through the echo;
- otherwise the id is `pf-<pid>-<monotonic nanoseconds>` — unique without
  shared mutable state, since httpd handles each connection in its own process.

## Routing

`registry/router.emo` owns the dispatch, with a `Service` (config, database
probe, blob store, manifest lookup) carrying what the routes need:

1. `/v2/<name>/manifests/<reference>` → `registry.manifests.handle`
   ([registry-manifests.md](registry-manifests.md)).
2. `/v2` or `/v2/` → 200 `{}` (GET) or 405.
3. `/healthz`, `/readyz` → `registry.health.handle_health`.
4. everything else → 404 `NAME_UNKNOWN` with `detail: "<METHOD> <path>"`.

`registry/api.emo` holds the shared pieces (error envelope, codes, request
id, decoration); `router.handle` decorates whatever a route answered. Later
protocol tasks add their routes ahead of the catch-all.
