# Registry Authentication (T2.14)

> Status: v0.1, implemented by `registry/auth.emo` (tokens, scopes, gate,
> `/token`) and the `auth` section of `registry/config.emo`. Tests:
> `test/registry_auth.emo` and the config cases beside it.

## The flow

Docker's Bearer flow, HS256 edition (D6: pre-shared accounts from the config
file, no OAuth):

1. Any protected route without a token answers the challenge:

   ```http
   HTTP/1.1 401 Unauthorized
   WWW-Authenticate: Bearer realm="http://127.0.0.1:5000/token",
     service="pokerface-registry",scope="repository:acme/app:pull"
   {"errors":[{"code":"UNAUTHORIZED","message":"authentication required",…}]}
   ```

   The realm defaults to `http://<listen>/token`; `service` defaults to
   `pokerface-registry`.

2. The client exchanges Basic credentials for a token:

   ```console
   $ curl -u alice:wonderland "http://127.0.0.1:5000/token?service=pokerface-registry&scope=repository:acme/app:pull,push"
   {"token":"eyJhbGciOi…","expires_in":3600,"issued_at":"2026-11-19T…"}
   ```

   - Unknown accounts and wrong passwords answer the **same** 401 — the
     response never distinguishes them, and the password comparison is
     constant time.
   - Scopes are space-separated; a comma inside one joins its actions
     (`repository:a:pull,push`). Malformed scopes — a bad repository name, an
     unknown action — answer `400` and grant nothing. v0.1 accounts may
     request anything; the limitation is the token's own scope set.
   - No scope requested → a token valid only for the `/v2/` probe.

3. The token is an HS256 JWT: `{"exp","nbf","iat","iss","sub","access":[
   {"type":"repository","name":"…","actions":"pull,push"}]}`. The gate
   verifies the signature (constant-time), the window (`expired_token` for
   `error=`), the issuer, and the scope; a mismatch of any of them is 401
   with a fresh challenge, so a client can re-auth with the scope it is
   missing (`error="insufficient_scope"`).

## What each route needs

| Route | Scope |
| --- | --- |
| `/healthz`, `/readyz`, `/token` | public |
| `/v2/` probe | any verified token |
| `GET|HEAD` manifests and blobs | `repository:<name>:pull` |
| `PUT` manifests, uploads (`POST`/`PATCH`/`PUT`/`GET` offset/`DELETE`) | `repository:<name>:push` |
| unknown routes | public (they 404 on their own) |

A pull-only token cannot push: the PUT/upload answers 401 with
`error="insufficient_scope"`. Cross-repository tokens are denied the same
way. 401 (never 403) keeps docker-style clients re-authing with the scope
they need.

## Configuration

```yaml
auth:
  enabled: true
  realm: "https://registry.example.com/token"   # optional, default http://<listen>/token
  service: "pokerface-registry"                  # optional
  issuer: "pokerface-registry"                   # optional
  token_ttl: 3600                                # optional, >= 60
  signing_key_file: /etc/pokerface/signing-key   # or signing_key: "…"
  users:
    - username: alice
      password_file: /etc/pokerface/alice        # or password: "…"
```

- With `enabled: true`, a signing key and at least one account are required;
  missing ones are start-up errors.
- `signing_key_file` / `password_file` are read **once at load**; trailing
  newlines are trimmed. Setting both the inline value and the file is an
  error.
- Environment: `POKERFACE_REGISTRY_AUTH_SIGNING_KEY` overrides the key;
  `POKERFACE_REGISTRY_AUTH_ENABLED` flips the switch.
- The start-up summary prints `auth=enabled users=<n> ttl=… signing_key=<set>`
  — passwords and the key never reach the log, and error messages never name
  them either.

## curl example

```console
$ curl -i http://127.0.0.1:5000/v2/            # 401 + challenge
$ TOKEN=$(curl -s -u alice:wonderland \
    "http://127.0.0.1:5000/token?service=pokerface-registry&scope=repository:acme/app:pull" \
    | sed -n 's/.*"token":"\([^"]*\)".*/\1/p')
$ curl -i -H "Authorization: Bearer $TOKEN" http://127.0.0.1:5000/v2/   # 200
```

Or the whole dance with a real client: `skopeo login --username alice
--password wonderland 127.0.0.1:5000`, then `skopeo copy` as usual.

## Tests

`test/registry_auth.emo` covers: base64url round trips and refusals,
mint/verify (foreign key, expiry, not-before, tampering, malformed, foreign
issuer), scope matching, the challenge shape, the token endpoint (scoped
issuance, the identical 401 for wrong password and unknown user, invalid
scopes, methods), `check_token` decisions (probe, pull/push split,
cross-repository, expiry), `required_access` kinds, the router with auth
enabled (challenges, insufficient_scope, public health/token), and the
config section (users with inline and file passwords, the key file, the env
override, unknown fields, missing-key validation, summary redaction).
