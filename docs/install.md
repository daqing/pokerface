# Installing pokerface (T4.7)

One line installs the `pokerface` CLI and the `pokerface-registry` server for your
platform (macOS on Apple Silicon, Linux on amd64 and arm64):

```console
$ curl -fsSL https://raw.githubusercontent.com/daqing/pokerface/main/install.sh | sh
```

The script runs under POSIX `sh` (dash, bash, and zsh all work) and does
four things: detects the OS and architecture, downloads the release tarball
and its `checksums.txt` from GitHub Releases, **verifies the sha256
checksum** (a mismatch aborts with exit 1 before anything is written), and
installs the 0755 binaries into `~/.local/bin`.

`pokerface version` then answers, e.g. `pokerface 0.1.0`.

## Overrides

| Variable | Meaning | Default |
| --- | --- | --- |
| `POKERFACE_VERSION` | A release tag to pin, e.g. `v0.1.0` | the latest release |
| `POKERFACE_INSTALL_DIR` | Where the binaries go | `~/.local/bin` |
| `POKERFACE_DOWNLOAD_BASE` | The artifact base URL (mirrors) | the GitHub Releases of `daqing/pokerface` |

Example — a pinned version into a writable prefix:

```console
$ POKERFACE_VERSION=v0.1.0 POKERFACE_INSTALL_DIR=/opt/pokerface/bin \
    sh install.sh
```

If `~/.local/bin` is not on your `PATH`, add it once:

```console
$ export PATH="$HOME/.local/bin:$PATH"
```

The installer never touches your shell configuration — the PATH line above
is yours to add.

## Verifying by hand

Every release carries `checksums.txt`; the installer checks it for you.
To verify manually:

```console
$ shasum -a 256 -c <(grep darwin-arm64 checksums.txt)   # macOS
$ sha256sum -c <(grep linux-amd64 checksums.txt)        # Linux
```

## How releases are built

`.github/workflows/release.yaml` cuts a release on every `v*` tag: the CLI
and the registry build natively on three runners (linux-amd64, linux-arm64,
darwin-arm64 — no cross-compilation, no emulation), land as
`pokerface-<platform>.tar.gz` with per-platform `.sha256` files and a
combined `checksums.txt`, and publish as a GitHub Release. The binaries are
built with the published Emo toolchain (the binary release pinned by
`EMO_VERSION`).

## Building from source

The toolchain is the Emo compiler (`emo-lang/emo`); with it on your PATH:

```console
$ emo build -o /usr/local/bin/pokerface main.emo
$ emo build -o /usr/local/bin/pokerface-registry registry/main.emo
```

The registry links `libsqlite3` (install the dev package); the CLI links
nothing beyond libc.
