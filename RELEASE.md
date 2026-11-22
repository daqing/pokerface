# Release Checklist (T4.16)

How to cut a pokerface release. The release workflow
(`.github/workflows/release.yaml`) does the building and publishing; this
checklist is the human part before and after it runs.

## 1. Version

- The binary's version string lives in `src/common.emo` (`const version`).
  Bump it **in the same commit as the change it belongs to** — a tag must
  point at a commit whose code and version string agree.
- The release tag is `vX.Y.Z` (annotated, with a one-line message, per the
  project's tag rules). The version and the tag must match modulo the `v`.
- Consumer-facing metadata (`pokerface.lock.yaml`, OCI labels) never
  carries the CLI version — nothing else to bump.

## 2. Changelog

- Add a `CHANGELOG.md` section for the version: one bullet per user-visible
  change (commands, protocol behavior, fixes), ordered M-milestone-first.
- Changes that are pure docs or task bookkeeping get one line at most.

## 3. Pre-tag gates

```bash
emo test                       # the full suite, green
emo build -o /tmp/pf-check main.emo
emo build -o /tmp/pokerface-registry-check registry/main.emo
./scripts/e2e.sh               # the M4 path: build → push → lock → resolve → pull → HTTP 200
./scripts/e2e-m2.sh            # the registry protocol edges
./scripts/e2e-m1.sh            # the client loop
```

- `docs/` gates run in CI (dead links, example↔schema validation, the
  help-text drift warning), but run `python3 docs-site/build.py` locally
  before tagging anyway.
- The workflows pass `actionlint`:
  `actionlint .github/workflows/*.yaml`.
- A local `emo build` of the CLI now links OpenSSL (the release binaries
  ship HTTPS support): install the OpenSSL development files, or pass
  `--cclib=-L<openssl-lib-dir>` (Homebrew's `openssl@3`/`openssl@4`). The
  registry does not use TLS and links no OpenSSL.

## 4. Tag and publish

```bash
git tag -a vX.Y.Z -m "pokerface vX.Y.Z"
git push origin vX.Y.Z
```

- The `v*` tag triggers `release.yaml`: three native platform builds
  (linux/amd64, linux/arm64, darwin/arm64), per-platform
  tarballs (`pokerface` + `pokerface-registry`) with `.sha256` files and a combined
  `checksums.txt`, published as a GitHub Release with generated notes.
- Both platforms build the Emo toolchain from source at the workflow's
  `EMO_REF` commit — the fixes the binaries need are not in a published emo
  release. That commit must be pushed to `github.com/emo-lang/emo`, because
  opam pins it by full SHA; a local-only commit fails the build at the pin.
- Watch the run; a red arm64 job is still a red release (`fail-fast` is
  off, so all three finish — check each).

## 5. Post-release verification

```bash
POKERFACE_VERSION=vX.Y.Z POKERFACE_INSTALL_DIR=/tmp/pf-release-check \
  sh install.sh            # downloads the real release, verifies the checksum
/tmp/pf-release-check/pokerface version   # must print vX.Y.Z's version
```

- Confirm the release page carries three tarballs + `checksums.txt`.
- `skopeo` sanity on the published binaries is not a thing — the binaries
  are static (the CLI); the registry needs libsqlite3 at runtime (document
  it in the release notes when it changes).

## 6. Rollback

- A broken release: delete the GitHub Release **and its tag** only if
  nothing consumed it yet; otherwise publish a `vX.Y.(Z+1)` fix release and
  point the install instructions at it — the installer defaults to
  "latest release", so a corrected newest release is the rollback.
- The registry does not roll back with the CLI: data written by a newer
  version (schema migrations) is append-only and older binaries read it
  fine; never run an older registry against a database migrated forward
  without checking `docs/spec/registry-db.md`.
- Installers that pinned `POKERFACE_VERSION` keep the old binary — that is
  what the pin is for.

## Known limitations to state in the notes

- The binaries are built with an Emo toolchain compiled from source at the
  workflow's `EMO_REF` commit — that pin carries the runtime fixes the
  release needs, which are not in a published emo release yet. Move the pin
  (and this note) once they are released.
- The registry and the CLI link OpenSSL at build time (the toolchain's
  reachability walk counts the httpd TLS tier). Linux binaries load the
  system `libssl3` at run time — present in mainstream distributions and in
  the compose image's `debian:bookworm-slim`. The macOS tarball bundles
  `libssl`/`libcrypto` with `@executable_path` install names, and
  `install.sh` places them beside the binaries; without the installer,
  keep all files from the archive together. The registry additionally needs
  `libsqlite3` at run time.
