# Registry Metrics and Observability (T2.18)

> Status: v0.1, implemented by `registry/metrics.emo` (counter sink +
> Prometheus rendering), the slog access/audit lines in
> `registry/router.emo`, and the `observability` config section. Tests:
> `test/registry_metrics.emo` and the compiled `db_selftest` (counter
> bumps and the rendered histogram).

## Access logs

One JSON line per request on stdout (`slog`, JSON format):

```json
{"level":"info","logger":"registry","msg":"request","ts":"2026-11-18T18:21:40.310Z",
 "id":"pf-84197-536773893599000","method":"GET","path":"/v2/",
 "status":"200","duration_ms":"0","bytes_in":"0","bytes_out":"2"}
```

- `ts` and `id` carry the same request id the response header
  (`X-Request-Id`) echoes, so a client report matches a log line.
- The line logs method, path, status, duration, and byte counts — **never**
  the query string, headers, or bodies, so no token, password, or presigned
  signature can leak into a log.
- Lines parse with `jq` (or any JSON reader) as a stream.

## Audit events

Every authentication failure — missing token, bad signature, expired,
insufficient scope, wrong password — emits one `warn` record:

```json
{"level":"warn","msg":"auth failure","event":"auth_failure","method":"GET",
 "path":"/v2/","reason":"registry: auth: token signature mismatch", …}
```

The reason names a state, never a credential.

## Metrics

`GET /metrics` renders the Prometheus text exposition (public; `GET` only):

```
# HELP pokerface_requests_total Total HTTP requests.
# TYPE pokerface_requests_total counter
pokerface_requests_total 4
# TYPE pokerface_errors_total counter
pokerface_errors_total 2
# TYPE pokerface_upload_bytes_total counter
pokerface_upload_bytes_total 4096
# TYPE pokerface_download_bytes_total counter
pokerface_download_bytes_total 1024
# TYPE pokerface_request_latency_seconds histogram
pokerface_request_latency_seconds_bucket{le="0.005"} 0
…
pokerface_request_latency_seconds_bucket{le="+Inf"} 4
pokerface_request_latency_seconds_sum 0.123
pokerface_request_latency_seconds_count 4
```

- Counters: requests total, errors (4xx + 5xx), upload bytes (upload
  sessions and manifest PUTs), download bytes (blob and manifest reads).
- The latency histogram uses the standard edges (5 ms … 10 s, +Inf),
  rendering cumulatively with `_sum` and `_count`.
- Counters live in SQLite (migration 3) — httpd's per-connection processes
  bump rows with UPSERTs in one short transaction per request, so the
  numbers aggregate across the fleet of connection processes. The write
  happens after the response is built: a failing database cannot fail a
  request that already succeeded. A fresh process renders a full document
  with zeros (every bucket edge present).
- The `/metrics` route is public (it exposes counts, never credentials) and
  excluded from the auth gate.

## Configuration

```yaml
observability:
  access_log: true    # default
  metrics: true       # default
```

Environment: `POKERFACE_REGISTRY_ACCESS_LOG`, `POKERFACE_REGISTRY_METRICS`.
The start-up summary reports both switches.

## Tests

`test/registry_metrics.emo` covers: the bucket edges, the route grouping
(upload/blob/manifest/tags/metadata/health/auth/other), the `/metrics`
endpoint (public, text/plain, POST refused), per-request recording through
the sink, and the config section (defaults, YAML, env overrides, unknown
fields, summary switches). The compiled `db_selftest` pins the counter
accumulation (UPSERTs across bumps), the cumulative histogram buckets, the
seconds-shaped sum, and the fresh-store zeros.
