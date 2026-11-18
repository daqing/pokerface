# Registry Service Configuration (T2.1)

> Status: v0.1, implemented by `registry/config.emo`, `registry/health.emo`,
> and the entry point `registry/main.emo`. Build and run:

```console
$ emo build -o .emo-build/registry registry/main.emo
$ scripts/run-registry.sh .emo-build/registry --config registry.yaml
```

## Configuration precedence

1. `--config <path>` (and `--config=<path>`).
2. `POKERFACE_REGISTRY_CONFIG`.
3. `./registry.yaml`.

**The file is required.** A missing file is a startup error naming the path
and the two ways to supply one:

```text
registry: config ./registry.yaml not found: file: cannot read ./registry.yaml: No such file or directory (create ./registry.yaml or pass --config)
```

Environment variables override individual file values. Relative paths are
resolved against the process working directory.

## Example

```yaml
listen:
  host: 127.0.0.1
  port: 5000
data_dir: ./data
store:
  backend: fs
  root: ./data/blobs
limits:
  max_body_bytes: 16777216
  max_header_bytes: 1048576
  read_timeout: 30
  idle_timeout: 5
# shutdown_file: ./data/registry.shutdown   # optional; this is the default
```

A copy lives at `registry/registry.example.yaml`.

## Fields

| Field | Type | Default | Validation |
| --- | --- | --- | --- |
| `listen.host` | string | `127.0.0.1` | non-empty |
| `listen.port` | integer | `5000` | 0–65535; `0` picks an ephemeral port and the server prints the real one |
| `data_dir` | string | `./data` | non-empty |
| `store.backend` | string | `fs` | `fs` or `s3` |
| `store.root` | string | `./data/blobs` | non-empty; for `fs`, the blob directory |
| `limits.max_body_bytes` | integer | `16777216` (16 MiB) | positive; oversized request bodies get 413 |
| `limits.max_header_bytes` | integer | `1048576` (1 MiB) | positive; oversized header blocks get 431 |
| `limits.read_timeout` | integer seconds | `30` | ≥ 0; `0` = unbounded |
| `limits.idle_timeout` | integer seconds | `5` | ≥ 0; bounds keep-alive idling and `server.wait()` during shutdown |
| `shutdown_file` | string | `<data_dir>/registry.shutdown` | the marker the main loop watches |

Unknown fields are rejected at every level (`registry: <path>: listen.bogus:
unknown field …`), and invalid values name the field. Invalid environment
values name the variable.

## Environment overrides

| Variable | Overrides |
| --- | --- |
| `POKERFACE_REGISTRY_CONFIG` | config file path (when `--config` is absent) |
| `POKERFACE_REGISTRY_LISTEN` | `host:port` |
| `POKERFACE_REGISTRY_DATA_DIR` | `data_dir` |
| `POKERFACE_REGISTRY_STORE_BACKEND` | `store.backend` |
| `POKERFACE_REGISTRY_STORE_ROOT` | `store.root` |
| `POKERFACE_REGISTRY_MAX_BODY_BYTES` | `limits.max_body_bytes` |
| `POKERFACE_REGISTRY_MAX_HEADER_BYTES` | `limits.max_header_bytes` |
| `POKERFACE_REGISTRY_READ_TIMEOUT` | `limits.read_timeout` (seconds) |
| `POKERFACE_REGISTRY_IDLE_TIMEOUT` | `limits.idle_timeout` (seconds) |
| `POKERFACE_REGISTRY_SHUTDOWN_FILE` | `shutdown_file` (set by the launcher) |

## Endpoints

| Route | Behavior |
| --- | --- |
| `GET /healthz` | 200 `ok` — the process is answering. |
| `GET /readyz` | 200 `ready` when every readiness check passes; 503 `not ready: <check>: <reason>; …` otherwise. |
| `GET /v2/` | 200 `{}` — a placeholder so a standard registry probe succeeds until T2.7 implements the distribution protocol. |
| anything else | 404. `POST`/`PUT`/… on a known GET route: 405 with `Allow: GET`. |

Readiness checks in v0.1:

- `data_dir` — the directory exists (created when absent) and a probe file can
  be written and removed. This is where T2.2's SQLite database will live, and
  T2.2 adds a database check.
- `store` — for `fs`, the blob root is usable the same way. `s3` reports not
  ready with "s3 backend is not implemented until T2.6". T2.4/T2.6 replace
  the check with the real store.

The check runs per request, so a directory that becomes unwritable flips
`/readyz` to 503 without a restart.

## Shutdown

Emo exposes no custom signal handler. The server therefore:

1. ignores `SIGTERM`/`SIGINT`;
2. removes any stale `shutdown_file` before serving;
3. polls `shutdown_file` every 100 ms while `httpd` serves in its own process;
4. on the marker, calls `server.stop()` (close the listener, no new
   connections) and `server.wait()` (drain in-flight requests; keep-alive idle
   connections end by `idle_timeout`).

`scripts/run-registry.sh <binary> [args…]` owns the signals: it sets
`POKERFACE_REGISTRY_SHUTDOWN_FILE` (a temp path unless already set), starts
the server, and on `SIGTERM`/`SIGINT` touches the marker and waits for the
child to exit. Run the service through the launcher (or implement the same
touch in your supervisor). A signal sent directly to the server binary is
ignored — that is deliberate, because there is no way to act on it safely.

The server prints `LISTEN=<host>:<port>` and `SHUTDOWN_FILE=<path>` on stdout
(raw fd writes) for supervisors, and a one-line configuration summary on
stderr.

## Exit codes

| Code | Meaning |
| --- | --- |
| 0 | Clean shutdown (or `--help`). |
| 1 | Missing/invalid configuration, bind failure. |
| 2 | Bad command line (unknown option, `--config` without a value). |
