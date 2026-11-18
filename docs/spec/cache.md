# Local Cache (T1.15)

> Status: v0.1, implemented by `src/cache.emo` (primitives) and
> `src/commands/cache.emo` (`cache ls` / `rm` / `verify`). One root holds the
> Git mirrors (T1.7), the manifest cache, the content-addressed blob cache,
> and the ref → commit map that makes a ref pull work offline.

## Layout

```text
<cache_root>/
  .pokerface-cache            marker: "pokerface-cache-v1"
  .lock/                      present while a destructive operation runs
  git/<key>/                  one per Git URL: source-url + mirror.git/
  manifests/<key>.json        one JSON envelope per (image, reference, platform)
  blobs/sha256/<hex>          content-addressed blobs
  refs/<key>                  <git_url + "\n" + ref> -> 40-char commit
```

`<cache_root>` is `POKERFACE_CACHE_DIR`, else `cache_dir` from the config,
else `$XDG_CACHE_HOME/pokerface` / `~/.cache/pokerface`.

`<key>` for manifests is `sha256(<image>@<reference>#<platform>)`; for refs it
is `sha256(<git_url>\n<ref>)`. Both are lowercase hex.

## The marker and adoption

`ensure_root` creates the root, the marker, and the section directories. An
existing directory is adopted only when it already has the marker, or when it
is empty / contains nothing but the known section names (`git`, `manifests`,
`blobs`, `refs`, `.lock`) — the T1.14 layout. Anything else is refused:

```text
cache: refusing to use /path: missing .pokerface-cache and the directory is not empty
```

Read-only commands (`ls`, `verify --check`) treat a missing/empty root as an
empty cache and refuse a populated unmarked directory. Destructive commands
(`rm`, `verify --fix`) additionally refuse any root without the marker. This
is what keeps `cache rm` from deleting an unrelated directory.

## Manifest envelope

The manifest cache is one file per key — a JSON envelope holding the body and
its metadata:

```json
{"body": "<the manifest JSON text>", "media_type": "…", "digest": "sha256:…",
 "platform": "linux/amd64", "reference": "sha256:…", "kind": "manifest"}
```

It is written to `<key>.json.<pid>.part` and renamed into place, so two
processes writing the same key never pair one writer's body with another
writer's metadata: a reader always sees one complete envelope. Reading
validates the body hash, the media type, the reference kind, the platform,
and the lock's expected digest.

## TTL and size limit

| Variable | Format | Meaning |
| --- | --- | --- |
| `POKERFACE_CACHE_TTL` | seconds or `<n>s/m/h/d` | Entries older than this are evicted. `0`/unset disables. |
| `POKERFACE_CACHE_MAX_SIZE` | bytes or `<n>K/M/G/T` (1024-based) | After TTL eviction, the oldest entries are evicted until the total fits. `0`/unset disables. |

Limits are enforced after every successful pull (best effort — an enforcement
failure never fails the pull) and are shown by `cache ls`. Eviction considers
blobs, manifest envelopes, ref entries, and whole Git mirror directories; the
oldest mtime goes first. A concurrent pull may miss an entry evicted by
another process and re-download it (online); offline, it reports the missing
entry.

## Commands

### `cache ls`

Human output lists each section with entry count and size, then the total and
the configured limits. `--json` prints:

```json
{"root": "…", "sections": [{"name": "git", "entries": 1, "bytes": 28000,
 "oldest": 1700000000, "newest": 1700000000}, …], "total_entries": 5,
 "total_bytes": 30700000, "ttl": 0, "max_bytes": 0}
```

### `cache verify [--check]`

Verifies every entry:

- **blobs** — the file hashes to its name; `.part`/`.meta` leftovers and
  unexpected names are problems;
- **manifests** — the envelope parses, the body hashes to the metadata digest,
  the media type is an image manifest, and the reference kind is consistent;
- **refs** — each file holds a 40-character lowercase commit SHA;
- **git** — each entry has `mirror.git/HEAD` and passes
  `git fsck --no-progress --no-dangling`.

By default it **repairs**: every problem is evicted. `--check` only reports,
and exits 1 when any issue remains. Exit 0 means no issues remain; a failed
eviction keeps the exit code at 1. `--json` reports `checked`, `issues`,
`evicted`, and the issue notes.

### `cache rm [--all | --git | --manifests | --blobs | --refs]`

Removes the selected sections (default: all) and recreates them empty. The
root, the marker, and anything outside the known section directories are
never touched; removals never follow symlinks. A missing root is a no-op.
Destructive commands take `<root>/.lock`; if it exists, the command fails with
a hint to remove a stale lock.

## Concurrency

- Cache writes are atomic (`write_atomic` → per-process `.part` + rename).
- Blobs and refs are single files; manifests are one envelope, so there is no
  body/meta pair to tear.
- Destructive operations (`rm`, `verify --fix`, limit enforcement) serialize
  on the `.lock` directory; limit enforcement skips silently when another
  operation holds it.
- Blob downloads keep T1.11's digest/size verification before the final
  rename, so concurrent writers of the same blob can at worst waste a
  transfer; the committed file is always complete.

## Offline mode

`--offline` reads only the cache. The ref → commit map makes a **ref name**
(not just a full SHA) work offline after one successful online resolution;
the lock comes from the Git mirror via `git show`, and manifests/blobs come
from their caches. A cold cache produces a clear "no cached …" error.
