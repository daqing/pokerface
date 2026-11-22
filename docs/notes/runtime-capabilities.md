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
- **`os.waitpid` blocks the entire runtime, not just the calling process** —
  a `time.after` watchdog never fires while the parent waits (verified: a
  0.3s watchdog against a 2s child did nothing). Timeouts around subprocesses
  therefore use a double-fork watchdog: the child forks a grandchild that
  closes the pipe fds, sleeps the deadline, then kills the child; the parent
  blocks freely in `waitpid` (see `src/git.emo`'s `RealRunner`).
- `emo deps resolve` writes `package.lock` listing every transitive pin;
  commit it beside the manifest.

## Dependencies pinned by this task

Direct requires in `package.emo`: `os`, `file`, `crypto`, `http`, `yaml`,
`json` — all `0.1.0`, locked in `package.lock` (transitive: `net`, `float`,
`time` through `http`). Not pinned yet, by design: `slog`, `httpd`,
`sqlite3` — they land with the tasks that first require them.

## The socket write limit (T4.13, 2026-11-20)

**A single `conn.write` above roughly 64 KiB can die with
"Resource temporarily unavailable"** — the c runtime's plain-TCP
`emo_net_write_once` calls `send` once and treats `EAGAIN` (socket buffer
full) as a fatal error instead of waiting for writability; the TLS path
already loops on `SSL_ERROR_WANT_WRITE`, the plain path does not. Partial
writes are handled (the outer loop continues on a positive count), so the
failure only fires when a `send` starts while the buffer is full — which
for loopback is any multi-hundred-KiB body whose peer pauses between reads.

Consequences and the workaround, both shipped in T4.13:

- the **push** uploads blobs in 64 KiB PATCH windows (`src/push.emo`
  `push_single_max`/`push_chunk_size`), never one giant body;
- the **registry** serves blob GETs as bounded 206 windows
  (`registry/blobs.emo`, `blob_range_window` = 32 KiB) for `Range:
  bytes=A-` requests, with a Content-Range naming exactly what was sent;
- the **pull** downloader walks those windows: an under-run against the
  declared size continues the loop from the `.meta` offset until the size
  is reached, then the digest verifies (`src/blob.emo`
  `download_blob_with`).

The root-cause fix landed in the emo runtime's `develop` branch on
2026-11-22 (c target, `emo_net_write_once`; unreleased at the time of
writing): a raw `send` that answers `EAGAIN`/`EWOULDBLOCK` now parks the
fiber on writability and retries, toward the connection's timeout — a
deadline past with nothing writable answers "timed out writing to …" —
the same discipline reads and the TLS path already kept. With the fix a
plain 200 GET of a large blob completes for every client (curl, crane,
skopeo), and a `conn.write` above the socket buffer no longer fails. The
window workarounds above stay: they are still correct and keep memory
bounded. Toolchains released before the fix still need the windows for
large transfers.

## The Linux runtime's HTTP stack (T4.16 checklist verification, 2026-11-20)

**Any HTTP exchange through the `http`/`httpd` packages segfaults (or
traps, SIGTRAP) on the Linux c target**; the same code runs fine on macOS.
Found while verifying the compose stack (section 9, item 4) — the Linux
registry binary (`pokerface-registry`) listens and dies on the first request; a minimal Linux
client program dies on the first real response. Evidence, narrowed by
bisection:

- `registry/db_selftest.emo` built for linux/arm64: **135 checks pass** —
  the allocator, strings, sqlite, and the fiber scheduler's basic paths
  are sound.
- Raw `net` over the same connection works, each primitive verified
  separately: `connect`, `write`, `read_line`, `read_exactly(64648)`,
  `read_all`, `set_timeout`.
- `http.request` against a *closed* port answers the clean
  "connection refused"; against any **live** server (MinIO, Python
  http.server, the Emo registry itself) the process dies with no error —
  `EMO_TRACE` shows the fiber dispatched, `""request""` printed, then the
  trap, with no scheduler round-trip.
- Upstream `origin/main` carries no newer fix in `emo_c_runtime.c`
  (`git log HEAD..origin/main -- src/emo_codegen/c/emo_c_runtime.c` is
  empty at 88281e11).

Building for Linux also needs two workarounds already applied in the
T4.16 verification: the runtime uses `offsetof` without `<stddef.h>`
(glibc + `-std=c11` rejects it; inject via a `cc` wrapper), and the
registry needs `sqlite3.h` plus `libsqlite3` at link time. Neither is the
crash.

**Fixed** (2026-11-20, branch `fix/stdlib-http` in the emo repo, worktree
`emo-fix-stdlib-http`): `emo_net_meta_register` left the new
`emo_net_meta`'s `pending`/`pending_len` uninitialized after `malloc`;
glibc's tcache supplies recycled bytes, so the first `read_line` on a
connection read a garbage length, doubled its buffer until it overflowed,
and aborted in `realloc`. macOS's allocator happened to return zeroed
pages, hiding the bug. The fix zeroes the fields on registration (and
drops a reused fd's previous pending bytes); a second commit adds
`<stddef.h>` for the `offsetof` the strict `-std=c11` build needs. With
both, a Linux/arm64 registry serves the full surface — skopeo push, tags,
manifest GET, blob GET, metrics — and the compose stack comes up healthy.
The crash was pinned with an injected `backtrace` handler (no gdb on this
machine) after valgrind proved useless here: under valgrind's allocator
layout the bug stayed dormant.
