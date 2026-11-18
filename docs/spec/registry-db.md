# Registry Data Layer (T2.2)

> Status: v0.1, implemented by `registry/db.emo`. The compiled checks live in
> `registry/db_selftest.emo`.

The registry keeps its metadata in one SQLite database at `db_path`
(default `<data_dir>/registry.db`): repositories, manifests, tags, blob
references, and upload sessions. Blob bytes themselves live in the BlobStore
(T2.4); the `blobs` table is the per-repository index.

## Connection setup

Every connection runs these pragmas before it is handed out:

| Pragma | Value | Why |
| --- | --- | --- |
| `journal_mode` | `WAL` | readers run while a writer commits |
| `synchronous` | `NORMAL` | WAL-safe durability at one fsync per checkpoint |
| `busy_timeout` | `5000` ms | a second writer waits instead of failing with `SQLITE_BUSY` |
| `foreign_keys` | `ON` | SQLite leaves the references above off by default |

`journal_mode` is persisted in the database file, the rest are per connection.
Concurrent readers therefore do not fail while another connection holds a
write transaction.

## Schema (version 1)

```text
repositories(id INTEGER PK AUTOINCREMENT, name TEXT NOT NULL UNIQUE, created_at INTEGER NOT NULL)
manifests(id INTEGER PK AUTOINCREMENT, repository_id INTEGER NOT NULL REFERENCES repositories(id) ON DELETE CASCADE,
          digest TEXT NOT NULL, media_type TEXT NOT NULL, size INTEGER NOT NULL CHECK (size >= 0),
          body TEXT NOT NULL, created_at INTEGER NOT NULL, UNIQUE (repository_id, digest))
tags(repository_id INTEGER NOT NULL REFERENCES repositories(id) ON DELETE CASCADE, tag TEXT NOT NULL,
     digest TEXT NOT NULL, updated_at INTEGER NOT NULL, PRIMARY KEY (repository_id, tag),
     FOREIGN KEY (repository_id, digest) REFERENCES manifests(repository_id, digest) ON DELETE CASCADE)
blobs(repository_id INTEGER NOT NULL REFERENCES repositories(id) ON DELETE CASCADE, digest TEXT NOT NULL,
      size INTEGER NOT NULL CHECK (size >= 0), created_at INTEGER NOT NULL,
      PRIMARY KEY (repository_id, digest))
uploads(id TEXT PRIMARY KEY, repository_id INTEGER NOT NULL REFERENCES repositories(id) ON DELETE CASCADE,
        state TEXT NOT NULL CHECK (state IN ('pending', 'completed', 'cancelled')),
        created_at INTEGER NOT NULL, expires_at INTEGER NOT NULL,
        offset_bytes INTEGER NOT NULL DEFAULT 0)
```

Migration 2 (T2.11) added `uploads.offset_bytes` — the authoritative count
of chunk bytes a session holds — as an `ALTER TABLE`; sessions created
before it answer 0. The migration list is append-only: a released migration
is never edited, and a deployed database applies only the versions it is
missing.

Indexes: `idx_tags_digest` (tag → manifest lookups) and `idx_uploads_expiry`
(the expiry sweep).

A repository delete cascades to its manifests, tags, blobs, and uploads; a
manifest delete drops the tags that pointed at it. A tag cannot name a
manifest the repository does not have — T2.8 writes the manifest row first.

Timestamps are Unix seconds. Manifest `body` is the exact stored bytes as
text, so the registry serves back what it received.

## Migrations

`migrations()` is the ordered list; each entry carries a version, a name, and
its statements. `migrate()` creates `schema_version(version, applied_at)` when
absent, then applies each missing migration inside `BEGIN IMMEDIATE` — the
write lock makes a second starting server wait, and the version is re-checked
inside the transaction so only one of them records it.

Migrations are append-only: never edit a released one, add the next version.
Re-running `migrate()` on a current database executes no DDL.

Emo has no catch construct, so a failing migration statement ends the process
and SQLite rolls the open transaction back when the connection closes. The
service exits 1 and prints SQLite's own message; a half-applied migration
cannot be recorded.

## API shape

Emo has no `Option`, so lookups use sentinels:

| Value | Absent |
| --- | --- |
| repository id, upload repository id | `0` (AUTOINCREMENT starts at 1) |
| size (`blob_size`, `manifest_size`) | `-1` |
| text (`manifest_body`, `tag_digest`, `upload_state`, `schema_sql`) | `""` |

Writes that are idempotent by identity — `ensure_repository`, `put_manifest`,
`put_blob` — answer whether a row was inserted and ignore duplicates.
`put_tag` replaces, bumping `updated_at`.

`begin()` / `commit()` / `rollback()` expose the transaction the multi-row
writes of T2.8 will use.

## Readiness

`registry.db.Health` is the `/readyz` check. It opens a short-lived connection
per probe rather than sharing the start-up handle: httpd runs one process per
connection, and a long-lived connection would be forked into every request
process. It first reads the 16-byte SQLite header, so a missing file, a
directory in the way, a permissions problem, or a non-database file answers
`503 not ready: db: <path> …` instead of dropping the connection.

Start-up runs the migrations once, then closes that handle.

## Testing

The sqlite3 package is `c`-target only and the interpreter refuses foreign
calls (E3009), so the coverage is split:

```console
$ emo test                     # migration table, pragmas, path helpers
$ scripts/check-registry-db.sh # compiled: real CRUD, constraints, restart, two connections
```

`registry/db_selftest.emo` is the compiled half: it creates a database under
`TMPDIR`, exercises every CRUD path, proves the foreign-key cascade and the
`CHECK` constraints from `schema_sql`, reopens the file to prove migrations do
not re-run, and runs a writer and a reader side by side. It prints one line per
check and exits 0 only when all pass.
