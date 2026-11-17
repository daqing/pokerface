# CLI Reference

> Status: skeleton (task T1.1). `--help` and `version` work; every other
> command reports "not implemented yet" on stderr and exits 1 until its task
> lands. The plan lives in `docs/TASKS.md`.

## Usage

```text
pokerface [global flags] <command> [args]
```

## Commands

| Command  | Status          | Description                                                    |
| -------- | --------------- | -------------------------------------------------------------- |
| resolve  | not implemented | Print the resolution chain of a repository reference (T1.9)    |
| pull     | not implemented | Fetch an image, verify it, and import it into the runtime (T1.14) |
| build    | not implemented | Build and push the image described by `pokerface.yaml` (T4.1)  |
| config   | not implemented | Show the effective configuration (T1.8)                        |
| cache    | not implemented | Inspect and manage the local cache (T1.15)                     |
| version  | implemented     | Print the version; `--json` prints `{"name": ..., "version": ...}` |

## Global flags

Flags are parsed before the first positional argument; the value form
`--config=<path>` is also accepted.

| Flag             | Effect                                                     |
| ---------------- | ---------------------------------------------------------- |
| `--config <path>` | Configuration file path (read once T1.8 lands)            |
| `--verbose`       | Verbose logging (wired up in T1.16)                       |
| `--json`          | Machine-readable output where supported (`version` today) |
| `-h`, `--help`    | Show the help text and exit 0                             |

## Exit codes

| Code | Meaning                                                                |
| ---- | ---------------------------------------------------------------------- |
| 0    | Success                                                                 |
| 1    | Command failure, including "not implemented yet"                        |
| 2    | Usage error: unknown command or option, missing `--config` value, no command |

T1.16 (`docs/spec/errors.md`) turns this into the full, stable table.

## Repository reference syntax

A repository reference names a Git repository and an optional ref (decision
D3). The parser (`src/ref.emo`, task T1.3) accepts three forms:

```text
github.com/acme/app:latest                  # bare form
https://github.com/acme/app.git:v1.2.0      # https:// form
git@github.com:acme/app.git:main            # git@ form
```

- The ref defaults to `latest`. It separates at the last `:` that is not
  followed by a `/`; an earlier `:` is a host port
  (`gitea.example.com:3000/acme/app`).
- The `.git` suffix is stripped from the repo, whatever the input form.
- The normalized result carries `host`, `owner`, `repo`, `git_url`, and
  `ref`; `git_url` is always `https://<host>[:<port>]/<owner>/<repo>.git`.
- `http://` and URL credentials are rejected. Refs containing `/` and path
  shapes other than `<owner>/<repo>` after the host are rejected with an
  error naming the offending field.
