# Runtime Capability Notes (T1.2)

> Verified 2026-11-17 with emo `v0.26.1115-alpha` on macOS (arm64), c target
> plus the interpreter run. Spike: `emo run spike/runtime.emo`; offline checks:
> `test/capabilities.emo` (25/25 passing). These notes record what the M1
> client can rely on and what it cannot.

## Verified capabilities

| Capability | Package | Result | Evidence |
| --- | --- | --- | --- |
| SHA-256 one-shot + streaming | `crypto.sha2` | works; RFC vector `sha256("abc")` matches | `test_sha256_known_vector` |
| Bytes ↔ text | `text.to_bytes()`, `crypto.hex_encode/decode` | works; hex is lowercase, strict on decode | `test_sha256_hex_roundtrip` |
| Constant-time compare | `crypto.constant_time_compare` | works | same test |
| Subprocess (fork/execvp/waitpid) | `os` | works; stdout capture via `os.pipe` + `os.dup2`; exit codes decoded by `os.wait_*` | `test_subprocess_git_version`, spike |
| exec failure path | `os.execvp` | returns in the child; the child must `os._exit(127)` itself | `test_subprocess_missing_binary_exits_127` |
| HTTPS GET | `http` | works; 200 + headers + body length | spike, below |
| Redirects | `http` | **never followed**; a 301 comes back as an ordinary response with `Location` intact | spike, below |
| YAML decode/encode | `yaml` | works for block mappings, nesting, ints, strings; malformed input is `(R.error, reason)` starting `yaml:` | `test_yaml_decode_and_encode` |
| JSON decode/encode | `json` | works; encode is compact; accessors raise on kind mismatch | `test_json_roundtrip` |
| Whole-file IO | `file` | `write` answers bytes written, `read` reads back exactly | `test_file_write_and_read` |
| Temp directories | `os.mkdir/list_dir/rmdir/unlink` | work; `list_dir` sorts byte-order, no `.`/`..` | `test_temp_directory_lifecycle` |
| Environment | `os.getenv` | works; unset variable is `(R.error, "os: getenv NAME: is not set")` | `temp_base()` helper |

## Spike output (2026-11-17)

```text
ok   sha256 — ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad
ok   git subprocess — git version 2.54.0 (Apple Git-157)
ok   https get — status 200, 577 bytes, content-type text/html; charset=utf-8
ok   redirect not followed — status 301, location https://github.com/
spike: all checks passed
```

## The http client's limits and the T1.11 plan

Confirmed limits, as the task brief warned:

1. **Redirects are never followed.** A 3xx is a response like any other.
2. **The whole response body is read into memory.** `http.get` has no streaming
   form; a 200 MB layer would sit in one String.

Plan for the pull path (recorded now, executed in T1.10/T1.11):

- Manifests, tokens, and the `/v2/` probe stay on `http`: small bodies, and the
  no-follow rule is exactly what the blob flow needs — a registry 307 must be
  read by us, not silently followed.
- Large blobs (config, layers) go through `net` directly: `net.tls_connect`
  (or plain `net.connect` for a presigned URL the registry hands out), send a
  minimal GET, then stream the body through `bufio` into the temp file while
  updating the SHA-256 digest incrementally. A 307 from the manifest step is
  handled by re-issuing one GET to the presigned `Location` and verifying the
  final digest after download.
- The spike evidence for this decision: the 301 check above, and the memory
  point stands because `resp.body` is one String with no size control.
- If `net` streaming proves awkward for chunked responses, fall back to
  `http` for blobs under a configured size cap and document the memory
  trade-off; decide again at T1.11 with real numbers.

## Gotchas found while verifying

- `R` has exactly two members: `ok` and `error`. There is no `ok2` to rename
  destructured bindings with.
- **A bare `.` YAML scalar resolves as a float** (`YamlFloat`), and
  `yaml.encode` renders it `0.0`. This bites `pokerface.yaml`'s
  `build: context: .` directly — T1.4's parser must quote `"."` in examples
  and treat a float context as an error, or the round trip corrupts the file.
- `is()` narrowing works on a bound name, not on a call expression: bind
  `const tags = doc.get("tags")` before `tags.is(json.JsonArray)`.
- `get(key)` is on the `Json`/`Yaml` interface; `items()`/`entries()` are only
  on the concrete `JsonArray`/`YamlObject` classes.
- `Array` has no `index_of` (only `String` does); scan arrays with a loop.
- `String` has no `contains`/`upper`; use `index_of(needle) >= 0` and `lower()`.
- `String.substring(start, length)` is length-based, not end-based.
- Under the interpreter, top-level statements run in order and do not see
  `def`s that appear after them; in entry files put defs first, or call into a
  `def` at the bottom.
- `os._exit(status)` works under both the interpreter and the c binary, and
  stdout is flushed before it.
- `emo deps resolve` writes `package.lock` listing every transitive pin;
  commit it beside the manifest.

## Dependencies pinned by this task

Direct requires in `package.emo`: `os`, `file`, `crypto`, `http`, `yaml`,
`json` — all `0.1.0`, locked in `package.lock` (transitive: `net`, `float`,
`time` through `http`). Not pinned yet, by design: `slog`, `httpd`,
`sqlite3` — they land with the tasks that first require them.
