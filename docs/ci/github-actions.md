# Publishing with GitHub Actions (T4.6)

The template lives at
[`.github/workflows/publish.yaml`](../../.github/workflows/publish.yaml) —
copy it into an application repository that carries a `pokerface.yaml`.
It implements ADR 0001's trigger contract exactly: **branch pushes**,
**`v*` tag pushes**, and **manual `workflow_dispatch`** runs; nothing else
starts a build.

## What the workflow does

1. **Checkout with the full history** (`fetch-depth: 0`) — the tag renderer
   needs the Git facts: the exact-match tag, the newest reachable tag for
   `{{ version }}`, the branch, and the commit.
2. **Install pokerface, pinned** — `POKERFACE_VERSION` names the release;
   the install script (T4.7) puts the `pokerface` binary on the runner's
   PATH.
3. **`pokerface build --write-lock`** — one command builds (buildx, streamed
   logs), pushes to the registry named in `pokerface.yaml`'s image, and
   writes `pokerface.lock.yaml` next to `pokerface.yaml`
   (`docs/spec/build-plan.md`, `docs/spec/push.md`,
   `docs/spec/pokerface-lock.md`). Push is driven by the `registry` section
   — there is no separate `--push` flag to forget.
4. **Commit the lock back** — only when it actually changed, with the
   message `pokerface: update pokerface.lock.yaml [skip ci]`, pushed to the
   branch. `pokerface resolve` then consumes the lock from Git
   (`docs/spec/pull.md`).

## The loop guards (belt and suspenders)

The lock commit touches the repository, which would re-trigger the
workflow — the build would run again on a commit that changed nothing but
the lock, and so on. Two independent guards break the cycle:

- **`paths-ignore: pokerface.lock.yaml`** on `push` — a commit that only
  touches the lock starts no pipeline (works on GitHub, Gitea, and any
  paths-aware CI).
- **`[skip ci]` in the commit message** — GitHub skips the pipeline for
  such commits outright; other CI systems that honor the marker are
  covered too.

Either guard alone is sufficient; both are in the template because a
single misconfigured fork of it should not become an infinite build loop.

## Secrets stay out of the way

- `POKERFACE_REGISTRY_TOKEN` — a repository secret holding a registry
  token with the push scope. It reaches the CLI **as an environment
  variable for the build step only**: never written to disk, never echoed,
  and never present in the lock (the lock's schema has no credential
  field — `docs/spec/pokerface-lock.md`). Masked in logs by Actions'
  secret redaction.
- `permissions: contents: write` — the job can write the lock back and
  nothing else. No `packages`, no registry-scoped GITHUB_TOKEN: the
  registry authenticates with its own token, not GitHub's.

## Verification

```console
$ actionlint .github/workflows/publish.yaml
```

passes (v1.7.7; note `hashFiles` is only valid in step-level `if`, which is
why the no-pokerface.yaml guard sits on the steps, not the job).

## What the example repository shows

Running the workflow on an application repository (`pokerface.yaml` at the
root, `POKERFACE_REGISTRY_TOKEN` set) builds on every branch push with
`sha-<commit>` tags, on every `v*` tag with the verbatim tag, and on
demand — and every build that pushed leaves the lock updated at that
commit, so `pokerface resolve github.com/<owner>/<repo>:<ref>` works from
Git alone. Branch names outside the OCI tag charset (e.g. `feat/x` with
`{{ branch }}` in the tags) fail the renderer with a clear error — ADR
0001's tag rules say which tags to use per trigger.
