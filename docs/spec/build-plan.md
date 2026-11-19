# The Build Plan (T4.1)

> Status: v0.1, implemented by `src/commands/build.emo` and `src/build.emo`
> (task T4.1). The build plan is the whole input of a build: the image
> reference, the rendered tags, the platforms, the build args, and the
> context/Dockerfile paths. `pokerface build --dry-run` prints it; the T4.2
> adapter (BuildKit/podman) executes it. The file it comes from is
> `pokerface.yaml` (`docs/spec/pokerface-yaml.md`).

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
| commit | `git -C <context> rev-parse --short=8 HEAD` | hard error — every build is built from a commit |
| git.tag | `git -C <context> describe --tags --exact-match HEAD` | `""` — the build was not tag-triggered |
| branch | `git -C <context> rev-parse --abbrev-ref HEAD` | `""` |
| version | `git -C <context> describe --tags --abbrev=0` | `""` — a `{{ version }}` tag then fails the charset check with a clear message |

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

`--dry-run` performs no build and no network requests. Running without it
is a usage error until the T4.2 adapter lands
(`executing the plan is not implemented yet — pass --dry-run`).
