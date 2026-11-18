# Error Model, Exit Codes, and Logging (T1.16)

> Status: v0.1, implemented by `src/errors.emo`; the exit-code constants live
> in `src/common.emo`. Command handlers report through `errors.report` /
> `errors.usage_report` / `errors.report_kind`, so every failure has one kind,
> one exit code, and one remediation hint.

## Categories and exit codes

| Kind | Exit | Meaning |
| --- | --- | --- |
| success | 0 | The command completed. |
| `failure` | 1 | Unclassified failure (including "not implemented yet"). |
| `usage` | 2 | Bad command line: unknown command/option, missing argument, invalid `--tag`/`--platform`, tag/platform not in the lock. |
| `git` | 3 | A Git operation failed (ref resolution, mirror initialization, object read). |
| `metadata` | 4 | Repository metadata or configuration: `pokerface.lock.yaml`, config, offline cache misses, registry 404s, a cache that is not pokerface's. |
| `authentication` | 5 | The registry rejected the credentials (401/403, token endpoint failures). |
| `network` | 6 | Connectivity or a transient server failure (connect/refused/timeout, fetch failures, 5xx, give-up-after-retries). |
| `integrity` | 7 | Content does not match what was pinned (manifest/blob digest or size mismatch, truncated transfer, corrupt cache entry, unsupported layout version). |
| `runtime` | 8 | The local container runtime or its tools failed (no runtime, skopeo missing, daemon unreachable, permission denied on the socket). |

Usage errors are the only ones commands force directly; the rest come from
`classify(message)` and can be forced with `report_kind` where the caller
knows better.

## Classification

The classifier lowercases the message and checks, in order:

1. `runtime:` prefix → runtime.
2. Usage phrases (`unknown option`, `expects`, `takes exactly`,
   `invalid platform`, `not in the lock`, `pass --tag`, …).
3. Integrity phrases (`digest mismatch`, `size mismatch`, `corrupted`,
   `truncated`, `does not match`, `missing blob`, `not an OCI image layout`,
   `unsupported imageLayoutVersion`).
4. Network phrases (`cannot connect`, `connection refused`, `timed out`,
   `cannot fetch`, `giving up`, `unexpected EOF`, `status 5`, …).
5. Authentication phrases (`unauthorized`, `401`, `403`, `token endpoint`,
   `token request`, `credentials`, …).
6. Lock/config metadata phrases (`pokerface.lock.yaml`, `lock YAML`,
   `config:`) — these win over the generic Git prefix, because a missing lock
   read through Git is a metadata problem.
7. `git:` / `git cache:` prefix → git.
8. Broader metadata phrases (`not found`, `404`, `cache`, `offline`,
   `registry:`, `blob:`, `oci:`, `redirect`, …).
9. Anything else → `failure`.

The order is deliberate: a network failure inside the token flow stays
`network`, a `runtime:` prefix always wins, and a lock-file error read via
Git stays `metadata`.

## Human output

One line plus one hint on stderr:

```text
pokerface: pull: blob: digest mismatch for https://cdn/app — expected sha256:…, got sha256:…
hint: Retry; if it persists, run `pokerface cache verify` and check the source image and lock digest.
```

Usage errors have no command prefix:

```text
pokerface: unknown option --wat
hint: Run `pokerface --help` (or `pokerface <command> --help`) for usage.
```

## JSON output

With `--json`, failures print one object on **stderr** (stdout stays reserved
for successful results, so a pipeline never confuses an error for data):

```json
{"error": {"kind": "integrity", "message": "blob: digest mismatch for …", "hint": "Retry; …", "exit_code": 7}}
```

The message and hint are JSON-escaped, and URLs in the message are redacted
as described below. `cache verify --json` still prints its report object on
stdout; a remaining-issue failure additionally prints the error object on
stderr and exits 7.

## Remediation hints

Each kind has one default hint (`errors.hint_for`):

| Kind | Hint |
| --- | --- |
| usage | Run `pokerface --help` (or `pokerface <command> --help`) for usage. |
| git | Check the repository URL and your Git access (network, SSH key, or token). |
| metadata | Check `pokerface.lock.yaml` and your configuration; `pokerface cache verify` checks the cache. |
| authentication | Set `POKERFACE_REGISTRY_TOKEN` or configure `registry.token`. |
| network | Check connectivity and retry; use `--offline` with a warm cache if the image was pulled before. |
| integrity | Retry; run `pokerface cache verify` and check the source image and lock digest. |
| runtime | Install/start Docker, Podman, or containerd; imports require skopeo. |
| failure | Run with `--verbose` for detail. |

## Logging

Logging is quiet by default: only command results and warnings go to stdout /
stderr. `--verbose` adds step, request, and command detail through
`errors.Logger`, which writes to stderr:

```text
pokerface: settings: config=… registry_token=<redacted:9> cache_dir=…
pokerface: http GET https://registry.example.com/v2/?<redacted>
pokerface:   Authorization: <redacted>
pokerface:   Accept: application/vnd.oci.image.manifest.v1+json
pokerface: exec skopeo copy oci:/tmp/layout:latest docker-daemon:app:latest
```

Redaction happens before anything reaches the sink:

- **Headers**: `Authorization`, `Proxy-Authorization`, `Cookie`, and
  `Set-Cookie` values are replaced with `<redacted>`.
- **URLs**: userinfo is replaced with `<redacted>@`, and the entire query
  string is replaced with `?<redacted>` — presigned CDN signatures, the token
  endpoint's `service`/`scope`, and any other query values never appear.
- **Free text**: every URL-shaped token in an error or warning is redacted the
  same way, so a redirect `Location` echoed in an error is safe.
- **Secrets**: `settings.redact` keeps the token out of the settings summary;
  request bodies and response bodies are never logged.
- **Commands**: the argv is logged with URL-shaped arguments redacted.

Tests use `BufferSink` to capture logger output; production uses `StderrSink`.
