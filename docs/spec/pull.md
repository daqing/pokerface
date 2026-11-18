# The `pull` Command (T1.14)

> Status: v0.1, implemented by `src/commands/pull.emo`. Chains the pieces from
> T1.9-T1.13 into one command:

```text
resolve (Git) -> manifest -> blobs -> verify -> OCI layout -> runtime import
```

The client only talks to the Git remote named by the reference, the registry
host named by the lock's `image`, and redirect targets that registry hands
out. Docker Hub is never contacted.

## Options

| Option | Effect |
| --- | --- |
| `--platform <os>/<arch>` | Select the platform; must be in the lock's `platforms` list. Default: the lock's first platform. |
| `--tag <tag>` | Image tag to import; must be one of the lock's `tags`. Default: the reference's ref name when it is a listed tag, else the only tag, else `latest`. |
| `--keep-temp` | Keep the assembled OCI layout (and a containerd archive) after success or failure and print its path. |
| `--offline` | Use only the local cache: no registry, no blob downloads, no Git fetches. A ref name resolves from the cache's ref → commit map (written by an earlier online run); a cache miss is an error. |

Global flags (`--config`, `--verbose`, `--json`) apply as elsewhere.
`--verbose` prints the settings summary (token redacted), the resolved chain,
manifest source, blob counts, and the layout path. `--json` emits:

```json
{"image": "registry/acme/app:latest", "digest": "sha256:…", "commit": "…",
 "platform": "linux/amd64", "runtime": "docker", "runtime_ref": "…",
 "manifest_cached": false, "blobs_downloaded": 2, "blobs_cached": 0}
```

## Failure policy

| Stage | Failure | Behavior |
| --- | --- | --- |
| Git resolution / lock read | any | **Hard error**, exit 1. Never falls back to a stale cache; the same-commit mirror read stays offline-friendly. |
| Manifest | network / 5xx | Fall back to the cached manifest for the same `(image, reference, platform)`, after re-verifying its digest against the lock. A warning names the original error. |
| Manifest | digest mismatch | The cached manifest is still usable only if it matches the lock; otherwise hard error. |
| Blob | transient | Retried per blob by T1.11 (backoff, Range resume), verified before it enters the cache/layout. A cached blob that verifies is never re-downloaded. |
| Blob | 4xx / digest mismatch | Hard error; corrupted bytes never reach the layout. |
| Layout / import | any | The temp layout is removed (T1.13 also removes its archive and a partially imported tag); with `--keep-temp` the layout is kept and its path is appended to the error. |

## Manifest selection

The lock's `manifest_digest` is the manifest for the platform it was selected
for — the first entry of `platforms`. Pulling that platform fetches the
manifest directly by `manifest_digest`. Any other platform fetches the lock's
`digest` (an index when multi-platform), lets the registry client select the
child by platform, and fetches that child by digest. Every fetch is verified:

- the body fetched for a digest must hash to that digest;
- the selected child must hash to the digest the index named;
- when the lock pins `manifest_digest`, the final manifest must match it.

## Cache

The cache is owned by T1.15 (`docs/spec/cache.md`). Pull uses:

```text
<cache_root>/
  .pokerface-cache                         marker
  manifests/<sha256(image@reference#platform)>.json   one JSON envelope: body + metadata
  blobs/sha256/<hex>                       content-addressed blobs
  refs/<sha256(git_url\nref)>              ref -> commit map for offline pulls
```

`<cache_root>` is `POKERFACE_CACHE_DIR`, else `cache_dir` from the config,
else `$XDG_CACHE_HOME/pokerface` / `~/.cache/pokerface`. A pull errors clearly
when no cache directory can be determined.

Manifest envelopes and ref maps are written atomically (per-process `.part` +
rename), and writes are best effort — a read-only cache never fails a pull.
Blob cache files are verified by digest and size on every use; an online pull
re-downloads a corrupted entry, while an offline pull reports it. The cache
limit environment variables (`POKERFACE_CACHE_TTL`,
`POKERFACE_CACHE_MAX_SIZE`) are enforced after each successful pull, best
effort.

## Offline mode

- Git: a ref name is resolved through the cached ref → commit map; a full
  40-character commit SHA works without it. The lock is read with
  `git show <sha>:pokerface.lock.yaml` from the mirror cache, never fetched.
- Manifest: read only from the manifest cache; the cached digest must match
  the lock.
- Blobs: read only from the blob cache; a missing or corrupted blob is an
  error naming the digest.
- Runtime import uses the local tools only.

## Registry host discipline

`registry_base` is `https://<host>` from the lock's `image`, except loopback
hosts (`localhost`, `127.0.0.1`) which use `http://`, and an explicit
`registry.url` / `POKERFACE_REGISTRY_URL` which overrides the base entirely.
Blob URLs are `<base>/v2/<repository>/blobs/<digest>`; a 307 to a presigned
URL is followed by the blob transport, which sends the Bearer token on the
first hop only — the CDN never receives it.
