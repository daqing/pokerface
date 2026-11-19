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
emo build -o /tmp/registry-check registry/main.emo
./scripts/e2e.sh               # the M4 path: build → push → lock → resolve → pull → HTTP 200
./scripts/e2e-m2.sh            # the registry protocol edges
./scripts/e2e-m1.sh            # the client loop
```

- `docs/` gates run in CI (dead links, example↔schema validation, the
  help-text drift warning), but run `python3 docs-site/build.py` locally
  before tagging anyway.
- The workflows pass `actionlint`:
  `actionlint .github/workflows/*.yaml`.

## 4. Tag and publish

```bash
git tag -a vX.Y.Z -m "pokerface vX.Y.Z"
git push origin vX.Y.Z
```

- The `v*` tag triggers `release.yaml`: four native platform builds
  (linux/amd64, linux/arm64, darwin/arm64, darwin-amd64), per-platform
  tarballs (`pokerface` + `registry`) with `.sha256` files and a combined
  `checksums.txt`, published as a GitHub Release with generated notes.
- Watch the run; a red arm64 job is still a red release (`fail-fast` is
  off, so all four finish — check each).

## 5. Post-release verification

```bash
POKERFACE_VERSION=vX.Y.Z POKERFACE_INSTALL_DIR=/tmp/pf-release-check \
  sh install.sh            # downloads the real release, verifies the checksum
/tmp/pf-release-check/pokerface version   # must print vX.Y.Z's version
```

- Confirm the release page carries four tarballs + `checksums.txt`.
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

- The Emo toolchain builds the release from source (opam pin); a published
  builder image will replace that step.
- Plain-HTTP GET responses larger than ~64 KiB can die mid-transfer (the
  runtime's socket-write limitation, `docs/notes/runtime-capabilities.md`);
  `pokerface`'s own push/pull walk bounded windows and are unaffected.
