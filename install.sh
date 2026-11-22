#!/bin/sh
# The pokerface installer (T4.7): detects the OS and architecture, downloads
# the matching release artifact and its checksums, verifies the checksum,
# and installs the binaries into ~/.local/bin (or $POKERFACE_INSTALL_DIR).
#
#   curl -fsSL https://raw.githubusercontent.com/daqing/pokerface/main/install.sh | sh
#
# Overrides:
#   POKERFACE_VERSION      a release tag (v0.1.0); default: the latest release
#   POKERFACE_INSTALL_DIR  the target directory; default: ~/.local/bin
#   POKERFACE_DOWNLOAD_BASE the artifact base URL; default: the GitHub releases
#
# The script runs under POSIX sh (dash, bash, zsh all work), writes nothing
# but a 0700 temp directory and the 0755 binaries, and never touches shell
# configuration.

set -eu

REPO="daqing/pokerface"
DOWNLOAD_BASE="${POKERFACE_DOWNLOAD_BASE:-https://github.com/$REPO/releases/download}"
INSTALL_DIR="${POKERFACE_INSTALL_DIR:-$HOME/.local/bin}"

say() { printf '%s\n' "$*"; }
fail() { printf 'install: %s\n' "$*" >&2; exit 1; }

need() { command -v "$1" >/dev/null 2>&1 || fail "missing required tool: $1"; }
need curl
need tar
need sha256sum || need shasum

# darwin-arm64, linux-amd64, linux-arm64 — the release workflow's matrix
# (docs/workflow: .github/workflows/release.yaml).
detect_platform() {
  os="$(uname -s)"
  arch="$(uname -m)"
  case "$os" in
    Darwin) platform="darwin" ;;
    Linux) platform="linux" ;;
    *) fail "unsupported operating system: $os" ;;
  esac
  if [ "$os" = Darwin ] && [ "$arch" != arm64 ]; then
    fail "no Intel macOS build — pokerface ships macOS for Apple Silicon only"
  fi
  case "$arch" in
    x86_64|amd64) platform="$platform-amd64" ;;
    arm64|aarch64) platform="$platform-arm64" ;;
    *) fail "unsupported architecture: $arch" ;;
  esac
  printf '%s' "$platform"
}

# The version: the pin wins; otherwise the latest release tag (the redirect
# avoids the API and its rate limits).
resolve_version() {
  if [ -n "${POKERFACE_VERSION:-}" ]; then
    printf '%s' "$POKERFACE_VERSION"
    return
  fi
  latest="$(curl -fsSL -o /dev/null -w '%{url_effective}' "https://github.com/$REPO/releases/latest")" ||
    fail "cannot resolve the latest release (set POKERFACE_VERSION to a tag like v0.1.0)"
  printf '%s' "${latest##*/}"
}

sha_of() { # a file's sha256, portable across GNU coreutils and macOS
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | cut -d' ' -f1
  else
    shasum -a 256 "$1" | cut -d' ' -f1
  fi
}

PLATFORM="$(detect_platform)"
VERSION="$(resolve_version)"
case "$VERSION" in
  v*) ;;
  *) VERSION="v$VERSION" ;;
esac
BASE="$DOWNLOAD_BASE/$VERSION"

# A private temp directory: the artifacts pass through here and nowhere
# else, and it goes away however the script ends.
TMPDIR_INSTALL="$(mktemp -d "${TMPDIR:-/tmp}/pokerface-install.XXXXXX")"
chmod 700 "$TMPDIR_INSTALL"
cleanup() { rm -rf "$TMPDIR_INSTALL"; }
trap cleanup EXIT INT TERM

say "installing pokerface $VERSION for $PLATFORM"

ARTIFACT="pokerface-$PLATFORM.tar.gz"
curl -fsSL -o "$TMPDIR_INSTALL/$ARTIFACT" "$BASE/$ARTIFACT" ||
  fail "cannot download $BASE/$ARTIFACT (does the release carry $PLATFORM?)"
curl -fsSL -o "$TMPDIR_INSTALL/checksums.txt" "$BASE/checksums.txt" ||
  fail "cannot download $BASE/checksums.txt"

# The checksum decides: a mismatch aborts before anything is installed.
WANT="$(awk -v f="$ARTIFACT" '$2 == f || $2 == "*"f { print $1 }' "$TMPDIR_INSTALL/checksums.txt" | head -n 1)"
[ -n "$WANT" ] || fail "checksums.txt does not name $ARTIFACT"
GOT="$(sha_of "$TMPDIR_INSTALL/$ARTIFACT")"
if [ "$GOT" != "$WANT" ]; then
  fail "checksum mismatch for $ARTIFACT — expected $WANT, got $GOT (do not install it)"
fi
say "checksum verified ($GOT)"

tar -xzf "$TMPDIR_INSTALL/$ARTIFACT" -C "$TMPDIR_INSTALL"

mkdir -p "$INSTALL_DIR"
for bin in pokerface pokerface-registry; do
  if [ -f "$TMPDIR_INSTALL/$bin" ]; then
    chmod 755 "$TMPDIR_INSTALL/$bin"
    mv "$TMPDIR_INSTALL/$bin" "$INSTALL_DIR/$bin"
  fi
done
# The macOS tarball carries the OpenSSL dylibs the binaries load from
# @executable_path; they sit beside the binaries and nowhere else.
for lib in "$TMPDIR_INSTALL"/libssl.*.dylib "$TMPDIR_INSTALL"/libcrypto.*.dylib; do
  if [ -f "$lib" ]; then
    chmod 755 "$lib"
    mv "$lib" "$INSTALL_DIR/"
  fi
done

if ! command -v pokerface >/dev/null 2>&1; then
  say ""
  say "add $INSTALL_DIR to your PATH, e.g. in your shell profile:"
  say "  export PATH=\"$INSTALL_DIR:\$PATH\""
fi

"$INSTALL_DIR/pokerface" version
