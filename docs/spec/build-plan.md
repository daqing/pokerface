# The Build Plan (T4.1, T4.2)

> Status: v0.1. The plan model and the dry run are implemented by
> `src/commands/build.emo` and `src/build.emo` (task T4.1); the execution
> adapter is the same module (task T4.2). The build plan is the whole input
> of a build: the image reference, the rendered tags, the platforms, the
> build args, and the context/Dockerfile paths. `pokerface build --dry-run`
> prints it; without the flag the adapter executes it. The file it comes
> from is `pokerface.yaml` (`docs/spec/pokerface-yaml.md`).

## Config discovery

`pokerface build` reads the **build** config — a different file from the
client's `config.yaml` (`docs/spec/config.md`), parsed by
`src.config.load`, never by `src.settings.load`. The path resolves as:

1. `--config <path>` (the global flag) names the file directly; or
2. `pokerface.yaml` in the current working directory.

A missing file is a single-line error
(`build: cannot read <path>: …`).

## Git metadata

The renderer's facts are captured from the **context directory** (the
repository being built), not from the CLI's working directory:

| Fact | Git invocation | When it fails |
| --- | --- | --- |
| commit | `git -C <context> rev-parse HEAD` (the full SHA; `{{ commit.short }}` is its first 8 characters) | hard error — every build is built from a commit |
| git.tag | `git -C <context> describe --tags --exact-match HEAD` | `""` — the build was not tag-triggered |
| branch | `git -C <context> rev-parse --abbrev-ref HEAD` | `""` |
| version | `git -C <context> describe --tags --abbrev=0` | `""` — a `{{ version }}` tag then fails the charset check with a clear message |
| origin | `git -C <context> remote get-url origin` | `""` — the source label is then omitted |

## Tag rendering

Each `tags` entry is rendered against the metadata
(`docs/spec/pokerface-yaml.md` has the placeholder table). Validation:

- an unknown placeholder or an unterminated hole is an error naming the
  template;
- the rendered tag must satisfy the OCI tag charset (lowercase
  `[a-z0-9._-]`, no leading `.` or `-`); an empty render (a lone
  `{{ git.tag }}` on an untagged build) fails the same check;
- two rules rendering to the same string collide, even when the rules are
  distinct (`{{ branch }}` and `{{ git.tag }}` both render `main` on a
  tag-triggered main build). The error names both positions:
  `tags[1] ('{{ git.tag }}') collides with tags[0] — both render to 'main'`.

## Path resolution

Relative paths in `pokerface.yaml` resolve against the config file's
directory (the T1.4 convention), shared by the plan and the Git capture:

- `build.context` → `<config_dir>/<context>`; a context of `.` joins to
  `<config_dir>/.` and the `/.` tail is dropped;
- `build.dockerfile` → `<context>/<dockerfile>`; an absolute path is kept.

`--platform` (repeatable) replaces the configured platforms for this run;
the config's list is untouched.

## Validation order

Nothing prints until everything validates:

1. the config parses (`pokerface.yaml: …` errors);
2. the context directory exists (`build.context: cannot open <path>: …`);
3. the Git facts are captured (`git: cannot read the commit: …`);
4. the tags render without collisions (`tag template '…': …`);
5. the Dockerfile exists (`build.dockerfile: cannot read <path>: …`).

## Output

The human output has a stable field order, matching the `--json` keys:

```text
image:      registry.example.com/acme/app
tags:       latest, sha-01234567
platforms:  linux/amd64
target:     runtime
dockerfile: /path/to/Dockerfile
context:    /path/to
args:       NODE_ENV=production
(dry run — no build performed)
```

`target` and `args` lines appear only when configured. `--json` prints one
object: `image`, `tags`, `platforms`, `target` (when set), `dockerfile`,
`context`, `args` (a list of `{name, value}`).

`--dry-run` performs no build and no network requests. Without it the plan
executes — the next section.

## Execution (T4.2)

The adapter wraps the local build tool and answers a validated OCI layout:

- **Detection** — `docker buildx version` first; `podman --version` when
  docker is missing. Neither answers
  `runtime: no build tool found — install docker (with buildx) or podman`,
  classified as a runtime problem (exit 8).
- **The build streams.** The child inherits stdout/stderr, so buildx's
  progress log appears live; nothing is captured and re-printed. A failure
  surfaces as `'docker' exited with code 1` (exit 1) with the original log
  above it; the watchdog kills a run after 30 minutes.
- **docker path** — one
  `buildx build --output=type=oci,dest=<work>/build.tar` invocation with
  every platform (`--platform=a,b` — buildx answers an image index for
  several, a single manifest for one), every rendered tag as `--tag`
  (index.json then carries one descriptor per tag), and `tar -xf` unpacking
  the tar into the layout directory. `--provenance=false --sbom=false`
  keeps the layout to exactly the image manifests the plan asked for (no
  attestation manifests).
- **podman path** — `podman build --format=oci` into podman's store, then
  `podman save --format=oci-dir` exports the layout directory. The save
  takes one image, so the layout carries the first tag; push applies the
  rest anyway.
- **OCI labels** on the image config: `org.opencontainers.image.revision`
  (the full commit SHA), `org.opencontainers.image.source` (the origin
  remote URL, omitted when there is none), `org.opencontainers.image.version`
  (omitted when the repo has no tags), and
  `org.opencontainers.image.created` (UTC, RFC 3339).
- **Work directory** — `<TMPDIR>/pokerface-build-<pid>/`, with `layout/`
  inside. Transient: push consumes it within the same invocation.
- **Validation** — the layout is verified (oci-layout version, every
  descriptor against its blob's digest and size) before the command
  answers, so a truncated build fails at build time, not at push time.

The human report:

```text
tool:       docker
layout:     /tmp/pokerface-build-4242/layout
digest:     sha256:5f42… (application/vnd.oci.image.manifest.v1+json)
tags:       latest, sha-0123abcd
pushed:     127.0.0.1:4599/acme/app (3 uploaded, 0 skipped)
```

One `digest:` line per unique digest (a multi-platform build reports the
index). When `pokerface.yaml` has a `registry` section, the layout then
goes to that registry — the push pipeline is
[push.md](push.md); without one the report says so and the image stays
local. `--json` prints `tool`, `layout`, `digests`, `tags`, `platforms`,
`pushed`, `digest`.
