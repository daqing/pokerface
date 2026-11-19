#!/usr/bin/env bash
# The M4 end-to-end demo (T4.14): ONE command walks the whole build-and-
# consume path against a LOCAL registry — build the example, push, write
# the lock, resolve, pull into the runtime, run the container, and assert
# its HTTP 200. No Docker Hub, no MinIO: the image is FROM scratch and the
# registry uses the filesystem backend (the S3/MinIO stack is deploy/'s
# business; the protocol coverage lives in e2e-m2.sh).
#
#   ./scripts/e2e.sh          # the demo, chatty
#   ./scripts/e2e.sh --ci     # quiet: step banners only, same assertions
#
# Everything runs in a fresh temp directory; failures keep it (and the
# per-step logs) and print the path. A clean run leaves nothing behind.
# Set KEEP_TMP=1 to keep a successful run's directory too.
#
# NOTE: run WITHOUT piping stdout (./scripts/e2e.sh, not … | tail) — the c
# runtime leaves idle scheduler workers that inherit stdout and hold a pipe
# open after exit (the T1.17 gotcha; this harness redirects to files).

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/pokerface-e2e.XXXXXX")"
KEEP_TMP="${KEEP_TMP:-0}"
QUIET=0
[ "${1:-}" = "--ci" ] && QUIET=1
PORT="${E2E_PORT:-4598}"
REGISTRY_PID=""

cleanup() {
  status=$?
  touch "$TMP/data/registry.shutdown" 2>/dev/null || true
  if [ -n "$REGISTRY_PID" ]; then
    kill -TERM "$REGISTRY_PID" >/dev/null 2>&1 || true
    wait "$REGISTRY_PID" >/dev/null 2>&1 || true
  fi
  if command -v pkill >/dev/null 2>&1; then
    pkill -TERM -f "$TMP/registry" >/dev/null 2>&1 || true
    pkill -TERM -f "$TMP/pokerface" >/dev/null 2>&1 || true
  fi
  if [ "$status" -eq 0 ] && [ "$KEEP_TMP" != "1" ]; then
    rm -rf "$TMP"
  else
    printf 'e2e: kept logs and state in %s\n' "$TMP"
  fi
  exit "$status"
}
trap cleanup EXIT

say() { if [ "$QUIET" -eq 0 ]; then printf '\n== %s\n' "$*"; else printf '[e2e] %s\n' "$*"; fi; }
fail() { printf 'e2e: %s\n' "$*" >&2; exit 1; }

need() { command -v "$1" >/dev/null 2>&1 || fail "missing required tool: $1"; }
need emo
need git
need curl

STARTED="$(date +%s)"
say "build the pokerface CLI and the registry (emo build)"
( cd "$ROOT" && emo build -o "$TMP/pokerface" main.emo ) > "$TMP/build-cli.log" 2>&1 ||
  { cat "$TMP/build-cli.log"; fail "the CLI build failed"; }
( cd "$ROOT" && emo build -o "$TMP/registry" registry/main.emo ) > "$TMP/build-registry.log" 2>&1 ||
  { cat "$TMP/build-registry.log"; fail "the registry build failed"; }
PF="$TMP/pokerface"

say "start the local registry (fs backend, 127.0.0.1:$PORT)"
mkdir -p "$TMP/data" "$TMP/blobs"
cat > "$TMP/registry.yaml" <<EOF
listen:
  host: 127.0.0.1
  port: $PORT
data_dir: $TMP/data
store:
  backend: fs
  root: $TMP/blobs
EOF
"$TMP/registry" --config "$TMP/registry.yaml" > "$TMP/registry.log" 2>&1 &
REGISTRY_PID=$!
for _ in $(seq 1 100); do
  curl -sf "http://127.0.0.1:$PORT/healthz" >/dev/null 2>&1 && break
  kill -0 "$REGISTRY_PID" 2>/dev/null || { cat "$TMP/registry.log"; fail "the registry exited"; }
  sleep 0.1
done
curl -sf "http://127.0.0.1:$PORT/healthz" >/dev/null || fail "the registry is not healthy"

say "prepare the example repository (examples/hello, fresh git, origin remote)"
cp -R "$ROOT/examples/hello" "$TMP/repo"
cd "$TMP/repo"
# The example's committed pokerface.yaml points at the quick start's port;
# this run generates its own so the image and the registry agree on $PORT.
cat > pokerface.yaml <<EOF
version: 1
image: 127.0.0.1:$PORT/hello/app
build:
  context: "."
  dockerfile: Dockerfile
  platforms:
    - linux/amd64
    - linux/arm64
tags:
  - latest
  - "sha-{{ commit.short }}"
registry:
  url: http://127.0.0.1:$PORT
EOF
git init -q -b main .
git config user.email "e2e@example.com"
git config user.name "E2E"
git remote add origin git@github.com:you/hello-app.git
git add . && git commit -q -m "the hello example"

say "pokerface build --write-lock (buildx streams to the log)"
"$PF" build --write-lock > "$TMP/build-push.log" 2>&1 ||
  { tail -20 "$TMP/build-push.log"; fail "build --write-lock failed"; }
grep -q "^(dry run" "$TMP/build-push.log" && fail "the build ran in dry-run mode"
grep -qE '^pushed: ' "$TMP/build-push.log" || fail "the push did not report itself"
[ -f pokerface.lock.yaml ] || fail "the lock was not written"
grep -q 'builder: buildkit' pokerface.lock.yaml || fail "the lock does not name the builder"
DIGEST="$(grep -E '^    digest: ' pokerface.lock.yaml | head -1 | awk '{print $2}')"
[ -n "$DIGEST" ] || fail "the lock has no digest"

say "commit the lock and resolve it from Git"
git add pokerface.lock.yaml && git commit -q -m "pokerface: update pokerface.lock.yaml"
"$PF" resolve "$TMP/repo:main" > "$TMP/resolve.log" 2>&1 ||
  { cat "$TMP/resolve.log"; fail "resolve failed"; }
grep -q "digest:  $DIGEST" "$TMP/resolve.log" || fail "resolve answered a different digest than the lock"

say "pokerface pull into the local runtime"
"$PF" pull "$TMP/repo:main" > "$TMP/pull.log" 2>&1 ||
  { tail -20 "$TMP/pull.log"; fail "pull failed"; }

RUNTIME=""
if command -v docker >/dev/null 2>&1; then
  RUNTIME=docker
elif command -v podman >/dev/null 2>&1; then
  RUNTIME=podman
else
  say "no docker/podman for the run leg — everything before it passed"
  [ "$QUIET" -eq 1 ] && printf '[e2e] PASS (run leg skipped)\n'
  exit 0
fi

say "run the container and assert HTTP 200"
case "$RUNTIME" in
  docker) docker run -d --rm --name pokerface-e2e-hello -p 8081:8080 "127.0.0.1:$PORT/hello/app:latest" > "$TMP/run.log" 2>&1 ||
    { tail -10 "$TMP/run.log"; fail "the container did not start"; } ;;
  podman) podman run -d --rm --name pokerface-e2e-hello -p 8081:8080 "127.0.0.1:$PORT/hello/app:latest" > "$TMP/run.log" 2>&1 ||
    { tail -10 "$TMP/run.log"; fail "the container did not start"; } ;;
esac
HTTP_PORT=8081
CODE=""
for _ in $(seq 1 50); do
  CODE="$(curl -s -o "$TMP/http-body.txt" -w '%{http_code}' "http://127.0.0.1:$HTTP_PORT/" 2>/dev/null || true)"
  [ "$CODE" = "200" ] && break
  sleep 0.2
done
[ "$CODE" = "200" ] || { tail -10 "$TMP/run.log"; fail "the container answered $CODE, want 200"; }
grep -q "hello from a pokerface-built image" "$TMP/http-body.txt" || fail "the body is not the hello message"
curl -sf "http://127.0.0.1:$HTTP_PORT/healthz" | grep -q "ok" || fail "/healthz did not answer ok"
docker stop pokerface-e2e-hello >/dev/null 2>&1 || podman stop pokerface-e2e-hello >/dev/null 2>&1 || true

say "repeat build: identical layers are skipped, the lock stays put"
"$PF" build --write-lock > "$TMP/build-push-2.log" 2>&1 ||
  { tail -20 "$TMP/build-push-2.log"; fail "the repeat build failed"; }
grep -q "skip blob" "$TMP/build-push-2.log" || fail "the repeat push re-uploaded existing blobs"

SECONDS_TAKEN=$(( $(date +%s) - STARTED ))
if [ "$QUIET" -eq 1 ]; then
  printf '[e2e] PASS (%ss)\n' "$SECONDS_TAKEN"
else
  printf '\n== all M4 checks passed (%ss)\n' "$SECONDS_TAKEN"
fi
