#!/usr/bin/env bash
# M1 end-to-end (T1.17): local Git repository + Emo mock registry/CDN + the
# real CLI. Everything is local — the lock names 127.0.0.1, so no Docker Hub
# (or any other registry) is contacted. Re-runnable: every run uses a fresh
# temp directory. Set KEEP_TMP=1 to keep that directory and the mock log.
#
# The import leg needs skopeo plus a container runtime (docker/podman/ctr);
# without them the script still exercises resolve + manifest/blob/cache and
# checks that pull exits with the runtime code (8).

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/pokerface-e2e-m1.XXXXXX")"
KEEP_TMP="${KEEP_TMP:-0}"
MOCK_PID=""
IMAGE_REF=""
RUNTIME=""

cleanup() {
  status=$?
  if [ -n "$MOCK_PID" ]; then
    # httpd's accept loop is a child of the mock; stop it, then the mock.
    if command -v pkill >/dev/null 2>&1; then
      pkill -TERM -P "$MOCK_PID" >/dev/null 2>&1 || true
    fi
    kill -TERM "$MOCK_PID" >/dev/null 2>&1 || true
    wait "$MOCK_PID" >/dev/null 2>&1 || true
  fi
  # The c runtime's scheduler keeps idle worker processes after the CLI's
  # main process exits; they are this run's binary path, so stop them all.
  if command -v pkill >/dev/null 2>&1; then
    pkill -TERM -f "$TMP/pokerface" >/dev/null 2>&1 || true
    pkill -TERM -f "$TMP/m1-fixture" >/dev/null 2>&1 || true
  fi
  if [ -n "$IMAGE_REF" ] && [ -n "$RUNTIME" ]; then
    case "$RUNTIME" in
      docker) docker image rm "$IMAGE_REF" >/dev/null 2>&1 || true ;;
      podman) podman image rm "$IMAGE_REF" >/dev/null 2>&1 || true ;;
      containerd) ctr images rm "$IMAGE_REF" >/dev/null 2>&1 || true ;;
    esac
  fi
  if [ "$KEEP_TMP" = "1" ]; then
    printf 'kept temp dir: %s\n' "$TMP"
  else
    rm -rf "$TMP"
  fi
  exit "$status"
}
trap cleanup EXIT

say() { printf '\n== %s\n' "$*"; }
fail() { printf 'e2e: %s\n' "$*" >&2; exit 1; }

sha256() {
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$1" | cut -d' ' -f1
  else
    sha256sum "$1" | cut -d' ' -f1
  fi
}

need() {
  command -v "$1" >/dev/null 2>&1 || fail "missing required tool: $1"
}

need emo
need git
need sed
need grep

say "build the CLI and the mock service"
( cd "$ROOT" && emo build -o "$TMP/pokerface" main.emo )
( cd "$ROOT" && emo build -o "$TMP/m1-fixture" mock/m1_fixture.emo )
PF="$TMP/pokerface"

say "prepare an OCI layout from test/fixtures/oci"
FIXTURES="$ROOT/test/fixtures/oci"
LAYOUT="$TMP/layout"
CONFIG_HEX="$(sha256 "$FIXTURES/config.json")"
LAYER_HEX="$(sha256 "$FIXTURES/layer-0.tar.gz")"
MANIFEST_HEX="$(sha256 "$FIXTURES/manifest.json")"
MANIFEST="sha256:$MANIFEST_HEX"
MANIFEST_SIZE="$(wc -c < "$FIXTURES/manifest.json" | tr -d ' ')"
mkdir -p "$LAYOUT/blobs/sha256"
cp "$FIXTURES/config.json" "$LAYOUT/blobs/sha256/$CONFIG_HEX"
cp "$FIXTURES/layer-0.tar.gz" "$LAYOUT/blobs/sha256/$LAYER_HEX"
cp "$FIXTURES/manifest.json" "$LAYOUT/blobs/sha256/$MANIFEST_HEX"
printf '{"imageLayoutVersion":"1.0.0"}\n' > "$LAYOUT/oci-layout"
printf '{"schemaVersion":2,"mediaType":"application/vnd.oci.image.index.v1+json","manifests":[{"mediaType":"application/vnd.oci.image.manifest.v1+json","digest":"%s","size":%s,"annotations":{"org.opencontainers.image.ref.name":"latest"}}]}\n' \
  "$MANIFEST" "$MANIFEST_SIZE" > "$LAYOUT/index.json"

say "start the mock registry/CDN"
"$TMP/m1-fixture" "$LAYOUT" "$MANIFEST" > "$TMP/mock.log" 2>&1 &
MOCK_PID=$!
i=0
while [ "$i" -lt 100 ]; do
  if grep -q '^REGISTRY=' "$TMP/mock.log" 2>/dev/null; then
    break
  fi
  if ! kill -0 "$MOCK_PID" >/dev/null 2>&1; then
    cat "$TMP/mock.log"
    fail "the mock exited before it reported its port"
  fi
  i=$((i + 1))
  sleep 0.1
done
grep -q '^REGISTRY=' "$TMP/mock.log" || { cat "$TMP/mock.log"; fail "the mock did not report its port"; }
REGISTRY="$(sed -n 's/^REGISTRY=//p' "$TMP/mock.log" | head -1)"
CDN="$(sed -n 's/^CDN=//p' "$TMP/mock.log" | head -1)"
grep -q "^MANIFEST=$MANIFEST$" "$TMP/mock.log" || fail "the mock reported the wrong manifest digest"
printf 'registry: %s\ncdn:      %s\n' "$REGISTRY" "$CDN"

say "create a local Git repository with a lock"
REPO="$TMP/repo"
mkdir -p "$REPO"
git init -q -b main "$REPO"
GIT=(git -C "$REPO" -c user.email=e2e@example.com -c user.name=E2E)
printf 'e2e fixture\n' > "$REPO/README.md"
"${GIT[@]}" add .
"${GIT[@]}" commit -q -m init
COMMIT="$("${GIT[@]}" rev-parse HEAD)"
cat > "$REPO/pokerface.lock.yaml" <<EOF
version: 1
commit: "$COMMIT"
source: github.com/acme/app
images:
  - image: $REGISTRY/acme/app
    tags: [latest]
    digest: $MANIFEST
    manifest_digest: $MANIFEST
    platforms: [linux/amd64]
EOF
"${GIT[@]}" add .
"${GIT[@]}" commit -q -m lock
export POKERFACE_CACHE_DIR="$TMP/cache"

say "resolve"
if ! "$PF" resolve "$REPO:main" > "$TMP/resolve.log" 2>&1; then
  cat "$TMP/resolve.log"
  fail "resolve failed"
fi
cat "$TMP/resolve.log"
grep -q '^commit:  ' "$TMP/resolve.log" || fail "resolve did not print a commit"
grep -q "digest:  $MANIFEST" "$TMP/resolve.log" || fail "resolve printed the wrong digest"
grep -q "^image:   $REGISTRY/acme/app$" "$TMP/resolve.log" || fail "resolve printed the wrong image"

RUNTIME=""
if command -v skopeo >/dev/null 2>&1; then
  if command -v docker >/dev/null 2>&1; then
    RUNTIME=docker
  elif command -v podman >/dev/null 2>&1; then
    RUNTIME=podman
  elif command -v ctr >/dev/null 2>&1; then
    RUNTIME=containerd
  fi
fi

if [ -z "$RUNTIME" ]; then
  say "pull (import leg skipped: needs skopeo plus docker/podman/ctr)"
  set +e
  "$PF" pull "$REPO:main" > "$TMP/pull.log" 2>&1
  PULL_CODE=$?
  set -e
  cat "$TMP/pull.log"
  [ "$PULL_CODE" -eq 8 ] || fail "pull without a runtime should exit 8, got $PULL_CODE"
else
  IMAGE_REF="$REGISTRY/acme/app:latest"
  say "pull and import into $RUNTIME"
  if ! "$PF" pull "$REPO:main" > "$TMP/pull.log" 2>&1; then
    cat "$TMP/pull.log"
    fail "pull failed"
  fi
  cat "$TMP/pull.log"
  grep -q "runtime:  $RUNTIME" "$TMP/pull.log" || fail "pull did not use the $RUNTIME runtime"
  case "$RUNTIME" in
    docker) docker image inspect "$IMAGE_REF" >/dev/null || fail "the imported image is missing from docker" ;;
    podman) podman image inspect "$IMAGE_REF" >/dev/null || fail "the imported image is missing from podman" ;;
    containerd) ctr images ls -q | grep -qx "$IMAGE_REF" || fail "the imported image is missing from containerd" ;;
  esac

  say "stop the mock and pull again offline"
  if command -v pkill >/dev/null 2>&1; then
    pkill -TERM -P "$MOCK_PID" >/dev/null 2>&1 || true
  fi
  kill -TERM "$MOCK_PID" >/dev/null 2>&1 || true
  wait "$MOCK_PID" >/dev/null 2>&1 || true
  MOCK_PID=""
  if ! "$PF" pull "$REPO:main" --offline > "$TMP/offline.log" 2>&1; then
    cat "$TMP/offline.log"
    fail "the offline pull failed"
  fi
  cat "$TMP/offline.log"
  grep -q '^manifest: cached$' "$TMP/offline.log" || fail "the offline pull did not use the cached manifest"
fi

say "cache ls / verify"
"$PF" cache ls > "$TMP/cache-ls.log" 2>&1
cat "$TMP/cache-ls.log"
"$PF" cache verify > "$TMP/cache-verify.log" 2>&1
cat "$TMP/cache-verify.log"
BLOB="$(find "$TMP/cache/blobs/sha256" -type f | head -1)"
[ -n "$BLOB" ] || fail "no blob in the cache"
printf 'corrupt' > "$BLOB"
set +e
"$PF" cache verify --check > "$TMP/cache-check.log" 2>&1
CHECK_CODE=$?
set -e
[ "$CHECK_CODE" -eq 7 ] || { cat "$TMP/cache-check.log"; fail "cache verify --check on a corrupt blob should exit 7, got $CHECK_CODE"; }
"$PF" cache verify > "$TMP/cache-fix.log" 2>&1
cat "$TMP/cache-fix.log"

say "ok — M1 client end-to-end"
