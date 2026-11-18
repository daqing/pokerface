# Registry Blob Store (T2.4)

> Status: v0.1, implemented by `registry/blobstore.emo`. Tests:
> `test/registry_blobstore.emo` under `emo test`.

Blobs are immutable bytes named by digest. The interface is what the
distribution routes and the upload sessions call; the local filesystem backend
is the development and test implementation. The S3 backend (T2.6) implements
the same interface.

## Interface

```emo
put(digest, body)            (R, BlobInfo)
put_file(digest, source)     (R, BlobInfo)
get(digest)                  (R, String)
read_range(digest, offset, length) (R, String)
head(digest)                 (R, BlobInfo)
delete(digest)               (R, Bool)
presign_get(digest, ttl_seconds) String
```

`BlobInfo` carries `digest`, `size`, and `exists`. Size `-1` means "present,
size unknown" — see the size record below.

`presign_get` answers `""` when the backend cannot presign (the local one).
The caller then streams the bytes itself; the S3 backend returns a real URL.
`is_not_found(reason)` recognizes a missing blob so the route layer can map
it to 404 `BLOB_UNKNOWN`; any other error is a backend failure.

## Local backend layout

`LocalStore` (created with `open(root)`, which makes `<root>/sha256`) stores
one blob per digest:

```text
<root>/sha256/<hex>        the bytes
<root>/sha256/<hex>.size   the byte count, decimal
<root>/sha256/.tmp-...     a write in progress
```

The size record exists because Emo's `os` has no `stat` and `file` only reads
whole files: without it, `head` and `Content-Length` would have to read a
multi-megabyte layer from disk. Records are tiny and immutable alongside their
blob.

## Write path

`put(digest, body)` hashes the body, rejects a digest that does not match, and
writes it through the same commit path as `put_file`. `put_file(digest,
source)` streams the source in 64 KiB chunks, hashing and counting as it
writes `<root>/sha256/.tmp-<pid>-<hex>`, then:

1. verifies the computed digest against the key (a mismatch removes the temp
   file and stores nothing);
2. writes the size record through its own temp-and-rename;
3. renames the temp blob onto `<hex>` — the commit point.

A reader therefore never sees a partial blob: until the final rename the bytes
live under a `.tmp-` name that is never served. If a crash lands between the
two renames, the result is an orphan `.size` record, which is harmless (the
next put rewrites it) — never a blob whose length is unknown.

Putting an existing digest is a no-op (one copy, one record): the store checks
for the blob and its record first and returns without copying. If the record
is missing, the put repairs it.

Writes are per-process temp names (`pid` + digest hex), so concurrent
connection processes do not collide; `rename(2)` makes the replace atomic.

## Reads

- `get` reads the whole blob (`file` has no streaming reader); a missing blob
  is `blobstore: not found: <digest>`.
- `read_range(digest, offset, length)` validates both as non-negative, errors
  when `offset` is past the end, and otherwise clips `length` at EOF — so
  `(size, 1)` answers `""` and `(size - 1, 10)` answers the last byte.
- `head` answers `exists = false` for a missing blob, and `size = -1` when the
  bytes are there but the size record is missing or unreadable; callers can
  fall back to the body length from `get`.
- `delete` removes the blob and the record and answers whether the blob
  existed; deleting a missing blob is `false`, not an error.

## Path safety

Paths are built from `registry.digest.hex(digest)` only — `sha256:` plus 64
lowercase hex characters — so `..`, `/`, absolute paths, other algorithms, and
uppercase hex are rejected before any filesystem call
(`blobstore: invalid digest '…'`). The hex is validated in one shared place
(`registry/digest.emo`) that the document parser uses too.

## Startup

`registry/main.emo` opens the local store at start-up (creating the digest
directory); a store root that is a file or cannot be created exits 1 with the
path and the reason. `/readyz` still probes writability independently.

## Tests

`test/registry_blobstore.emo` runs in the interpreter (no foreign code):
round-trip and restart, deduplication (one copy), digest-mismatch rejection
with no leftovers, streamed `put_file` over 64 KiB chunks, not-found
semantics, range clipping and the past-the-end error, path-escape attempts
for `put`/`get`/`delete`, delete idempotency, the empty blob, `presign_get`
returning empty, a missing size record reporting `-1` and being repaired by
the next put, interface conformance, and a root that is a file.
