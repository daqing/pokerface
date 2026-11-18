# Registry SigV4 Signing (T2.5)

> Status: v0.1, implemented by `registry/sigv4.emo`. Tests:
> `test/registry_sigv4.emo` under `emo test`.

AWS Signature Version 4 for the S3 / MinIO adapter (T2.6). The module is pure
functions over an injected `time.Time`, so the official vectors run on a fixed
clock and the S3 adapter can sign requests without a second copy of the
algorithm.

## Surface

| Function | Purpose |
| --- | --- |
| `sign_request(credentials, method, path, query, headers, payload_hash, at)` | Answers the headers to send, with `x-amz-date`, the session token when configured, and `authorization` last. |
| `presign(credentials, method, scheme, host, path, expires_in, at)` | Answers a `PresignedUrl` for a shareable link (`UNSIGNED-PAYLOAD`, `host` signed). |
| `canonical_request`, `string_to_sign`, `signing_key`, `signature`, `authorization` | The individual steps, public for the test vectors. |
| `canonical_query`, `canonical_uri`, `uri_encode`, `canonical_headers`, `signed_header_names` | The encoding and canonicalization rules. |
| `amz_date`, `date_stamp`, `scope` | `YYYYMMDD'T'HHMMSS'Z'`, `YYYYMMDD`, and `date/region/service/aws4_request`. |
| `sha256_hex` | The payload-hash helper (`sha256_hex("")` is the empty-body hash). |
| `PresignedUrl.valid_at(now)` / `expires_at()` | The validity window, in epoch seconds. |

`Credentials` carries `access_key`, `secret_key`, `region`, `service`, and an
optional `session_token`.

## Algorithm

```text
canonical request = method \n canonical-uri \n canonical-query \n
                    canonical-headers \n signed-header-names \n payload-hash
string to sign    = AWS4-HMAC-SHA256 \n timestamp \n scope \n sha256(canonical request)
signing key       = HMAC(HMAC(HMAC(HMAC("AWS4"+secret, date), region), service), "aws4_request")
signature         = HMAC(signing key, string to sign), lowercase hex
```

`sign_request` adds `x-amz-date` itself (replacing a caller-supplied one, and
dropping any `authorization`), so the timestamp in the scope and the header on
the wire cannot disagree. `payload_hash` is the caller's: the body's SHA-256,
or `UNSIGNED-PAYLOAD` when the transport does not hash.

Presigning puts the parameters in the query string — `X-Amz-Algorithm`,
`X-Amz-Credential`, `X-Amz-Date`, `X-Amz-Expires`, `X-Amz-SignedHeaders`, and
`X-Amz-Security-Token` when a token is configured — canonically sorted, with
`X-Amz-Signature` appended last. The URL is usable from `signed_at` up to, but
not including, `signed_at + expires_in`; `valid_at` implements exactly that.
AWS's own ceiling for `X-Amz-Expires` is 604800 seconds (`max_presign_seconds()`);
callers validate their configuration against it.

## Encoding

SigV4's, not form encoding:

- unreserved `A-Z a-z 0-9 - _ . ~` pass through;
- everything else is percent-encoded per UTF-8 byte with uppercase hex
  (`ü` → `%C3%BC`, space → `%20`, never `+`);
- the canonical URI leaves `/` alone, query names and values encode it
  (`a/b` → `a%2Fb`);
- query pairs sort by encoded name, then encoded value;
- headers lowercase names, trim values, collapse internal whitespace runs to
  one space, sort by name, and comma-join repeated names.

## Secrets

`secret_key` is used only as HMAC key material; the module logs nothing and
never puts the secret or the session token's signing inputs anywhere except
the signature computation. Callers must not log `Authorization` headers or
presigned URLs without redaction — a presigned URL's query carries the
signature, and `docs/spec/errors.md`'s redaction already strips URL queries.

## Test vectors

`test/registry_sigv4.emo` pins AWS's published values:

| Vector | Inputs | Expected |
| --- | --- | --- |
| sig-v4 suite `get-vanilla` | `AKIDEXAMPLE` / `wJalr…EXAMPLEKEY`, `us-east-1`, service `service`, `20150830T123600Z`, `GET /` | `Signature=5fa00fa31553b73ebf1942676e86291e8372ff2a2260956d9b8aae1d763fbf31` |
| sig-v4 suite `get-vanilla-query-order-key` | same clock, `?Param1=Value1&Param1=value2` | `Signature=eedbc4e291e521cf13422ffca22be7d2eb8146eecf653089df300a15b2382bd1` |
| S3 presigned GET | `AKIAIOSFODNN7EXAMPLE` / `wJalr…EXAMPLEKEY`, `us-east-1`, `s3`, `20130524T000000Z`, 86400 s, `https://examplebucket.s3.amazonaws.com/test.txt` | `X-Amz-Signature=aeeed9bbccd4d02ee5c0109b86d86835f995330da4c265957d157751f604d404` |

Further tests cover URI/query/header canonicalization, session tokens in both
modes, caller date/authorization replacement, clock/secret sensitivity, the
validity window's boundary second, the 604800 ceiling, and UTF-8 paths.
