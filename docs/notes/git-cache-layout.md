# Git mirror cache layout (T1.7)

> Implemented by `src/git_cache.emo`. The cache holds one bare mirror per
> Git URL under the cache root (XDG_CACHE_HOME, else `$HOME/.cache`,
> plus `/pokerface` — the full precedence table lands with T1.8).

## Layout

```text
<cache_root>/git/<key>/
  source-url                 the Git URL this mirror is for (debugging)
  mirror.git/                a bare repository: git init --bare, fetched on demand
```

`<key>` is the first 16 hex characters of `sha256(<git_url>)` — deterministic
so the same URL always lands in the same directory, and two different URLs
never share a mirror.

## Read flow

`read_lock(runner, git_url, commit, ref_hint, cache_root, timeout)`:

1. Ensure the directory chain and the bare mirror exist (`mirror.git/HEAD`
   is the readiness marker; racing initializers re-check HEAD and retry).
2. Try `git show <commit>:pokerface.lock.yaml` in the mirror. Success ends
   the read — **no fetch runs**, which is what makes the same commit
   readable offline after the first read.
3. On failure, fetch from the URL, then show again:
   - `ref_hint` is a full SHA → `git fetch <url> <sha>` (local transports
     allow this; remote servers need `uploadpack.allowAnySHA1InWant`, which
     the error mentions when the fetch fails);
   - `ref_hint` is an exact `refs/...` name → fetch that ref;
   - `ref_hint` is a branch or tag name → try the branch refspec, then the
     tag refspec (git fails a whole fetch when any refspec has no match);
   - anything else (`""`, `latest`, `HEAD`, a short SHA) → fetch all heads
     and tags.
4. Classify the outcome:
   - fetch failed → `git cache: cannot fetch <url> into the mirror: …` (the
     missing-repository / network error);
   - show failed with "does not exist" → `git cache: <url> has no
     pokerface.lock.yaml at commit <sha>` (the missing-file error);
   - anything else → `git cache: cannot read pokerface.lock.yaml at commit
     <sha>: …`.

`load_lock(...)` wraps `read_lock` with `src.lockfile.load`; an invalid lock
document is its own error (`… is not valid lock YAML: …`).

## Invariants

- **The user's working tree is never touched.** All git invocations run with
  `-C <mirror>` inside the cache directory; `test_user_working_tree_untouched`
  snapshots the working directory before and after a read.
- **Concurrent readers are safe.** git's own ref/object locks serialize
  fetches; racing `git init --bare` and lock-file contention are retried with
  short sleeps (`test_concurrent_fetches_do_not_corrupt_cache` races a real
  forked process against the parent on one fresh cache).
- **The mirror only ever grows.** Nothing prunes objects in v0.1; size
  limits and eviction are T1.15's job.
- **All git traffic is argv-array, never shell**, through the same
  `CommandRunner` abstraction as T1.6, with the double-fork watchdog timeout.
