#!/usr/bin/env bash
# M2 end-to-end (T2.19): the REAL registry service (fs backend) driven by
# real clients — skopeo pushes, the pokerface CLI pulls, curl exercises the
# protocol edges. Everything is local (127.0.0.1); nothing contacts Docker
# Hub or any external registry. Re-runnable: every run uses a fresh temp
# directory. Set KEEP_TMP=1 to keep it and the logs.
#
# The auth leg needs nothing beyond the registry itself. The import leg
# needs skopeo plus a container runtime (docker/podman/ctr); without them
# the script still exercises push/pull-free protocol checks and reports the
# skipped leg.
#
# NOTE: run this script WITHOUT piping its stdout (./scripts/e2e-m2.sh, not
# ./scripts/e2e-m2.sh | tail) — the c runtime leaves idle scheduler worker
# processes that inherit stdout and hold the pipe open after the script
# exits (the T1.17 gotcha; the harness runs everything redirected to files
# for the same reason).

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/pokerface-e2e-m2.XXXXXX")"
KEEP_TMP="${KEEP_TMP:-0}"
REGISTRY_PID=""
IMAGE_REF=""
RUNTIME=""

cleanup() {
  status=$?
  # The server's main process answers the marker file; the c runtime also
  # leaves idle scheduler workers holding the port, so match the binary path.
  if [ -n "$REGISTRY_PID" ]; then
    touch "$TMP/data/registry.shutdown" 2>/dev/null || true
    kill -TERM "$REGISTRY_PID" >/dev/null 2>&1 || true
    wait "$REGISTRY_PID" >/dev/null 2>&1 || true
  fi
  if command -v pkill >/dev/null 2>&1; then
    # The server binary and the CLI's idle scheduler workers (the pull's
    # workers carry the CLI path) both match by temp-dir path.
    pkill -TERM -f "$TMP/registry" >/dev/null 2>&1 || true
    pkill -TERM -f "$TMP/pokerface" >/dev/null 2>&1 || true
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
fail() { printf 'e2e-m2: %s\n' "$*" >&2; exit 1; }

sha256() {
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$1" | cut -d' ' -f1
  else
    sha256sum "$1" | cut -d' ' -f1
  fi
}

need() { command -v "$1" >/dev/null 2>&1 || fail "missing required tool: $1"; }

need emo
need git
need curl
need sed
need grep

say "build the CLI and the registry service"
( cd "$ROOT" && emo build -o "$TMP/pokerface" main.emo )
( cd "$ROOT" && emo build -o "$TMP/registry" registry/main.emo )
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

start_registry() { # $1 = config file, $2 = log file
  "$TMP/registry" --config "$1" > "$2" 2>&1 &
  REGISTRY_PID=$!
  local i=0
  while [ "$i" -lt 100 ]; do
    if grep -q '^LISTEN=' "$2" 2>/dev/null; then
      break
    fi
    if ! kill -0 "$REGISTRY_PID" >/dev/null 2>&1; then
      cat "$2"
      fail "the registry exited before it reported its port"
    fi
    i=$((i + 1))
    sleep 0.1
  done
  grep -q '^LISTEN=' "$2" || { cat "$2"; fail "the registry did not report its port"; }
  sed -i '' -e '' "$2" 2>/dev/null || true
}

stop_registry() {
  [ -n "$REGISTRY_PID" ] || return 0
  # The server ignores SIGTERM by design; the shutdown marker is the
  # documented stop protocol (the entrypoint plays the same role in the
  # container). The idle scheduler workers die with a SIGTERM by path.
  touch "$TMP/data/registry.shutdown"
  wait "$REGISTRY_PID" >/dev/null 2>&1 || true
  if command -v pkill >/dev/null 2>&1; then
    pkill -TERM -f "$TMP/registry" >/dev/null 2>&1 || true
  fi
  sleep 0.3
  REGISTRY_PID=""
}

write_config() { # $1 = path, $2 = port (0 = ephemeral), $3 = auth enabled or disabled
  cat > "$1" <<EOF
listen:
  host: 127.0.0.1
  port: $2
data_dir: $TMP/data
store:
  backend: fs
  root: $TMP/blobs
auth:
  enabled: $3
  signing_key: "e2e-signing-key"
  users:
    - username: alice
      password: wonderland
EOF
}

# A fixed port keeps every client URL deterministic; 4590 is an uncommon
# high port and collisions just fail the run loudly.
PORT="${E2E_M2_PORT:-4590}"
write_config "$TMP/registry.yaml" "$PORT" false
start_registry "$TMP/registry.yaml" "$TMP/registry.log"
REGISTRY_URL="http://127.0.0.1:$PORT"
printf 'registry: %s\n' "$REGISTRY_URL"

curl -sf -o /dev/null "$REGISTRY_URL/healthz" || fail "the registry is not healthy"

say "skopeo push (a real client)"
need skopeo
skopeo copy --dest-tls-verify=false "oci:$LAYOUT:latest" "docker://127.0.0.1:$PORT/smoke/app:v1" > "$TMP/push.log" 2>&1 \
  || { cat "$TMP/push.log"; fail "skopeo push failed"; }
tail -1 "$TMP/push.log"

say "manifest read-back by tag"
ACCEPT="application/vnd.oci.image.manifest.v1+json"
GOT_DIGEST="$(curl -sf -H "Accept: $ACCEPT" -D "$TMP/manifest.headers" "$REGISTRY_URL/v2/smoke/app/manifests/v1" -o "$TMP/manifest.json" \
  && sed -n 's/^[Dd]ocker-[Cc]ontent-[Dd]igest: //p' "$TMP/manifest.headers" | tr -d '\r' | head -1)"
[ "$GOT_DIGEST" = "$MANIFEST" ] || fail "the served manifest digest is $GOT_DIGEST, want $MANIFEST"
cmp -s "$TMP/manifest.json" "$FIXTURES/manifest.json" || fail "the served manifest bytes differ from the pushed ones"

say "tags list and pagination"
curl -sf -o /dev/null -X PUT -H "Content-Type: $ACCEPT" --data-binary @"$FIXTURES/manifest.json" "$REGISTRY_URL/v2/smoke/app/manifests/v2" \
  || fail "the second tag push failed"
LIST="$(curl -sf "$REGISTRY_URL/v2/smoke/app/tags/list")"
printf '%s\n' "$LIST" | grep -q '"name":"smoke/app"' || fail "the tag list names the wrong repository"
printf '%s\n' "$LIST" | grep -q '"tags":\["v1","v2"\]' || fail "the tag list is wrong: $LIST"
LINKED="$(curl -sf -D - -o /dev/null "$REGISTRY_URL/v2/smoke/app/tags/list?n=1" | sed -n 's/^[Ll]ink: //p' | tr -d '\r')"
printf '%s\n' "$LINKED" | grep -q '</v2/smoke/app/tags/list?n=1&last=v1>; rel="next"' || fail "the Link header is wrong: $LINKED"

say "resolve API"
RESOLVED="$(curl -sf "$REGISTRY_URL/api/v1/resolve?repository=smoke/app&tag=v1")"
printf '%s\n' "$RESOLVED" | grep -q "\"digest\":\"$MANIFEST\"" || fail "resolve returned the wrong digest"
printf '%s\n' "$RESOLVED" | grep -q '"architecture":"amd64"' || fail "resolve returned no platform"

say "cache: ETag and If-None-Match"
curl -sf -o /dev/null -w '' -D "$TMP/cache.headers" "$REGISTRY_URL/v2/smoke/app/blobs/sha256:$LAYER_HEX"
# The wire headers end CRLF; drop the CRs once so the line anchors work.
tr -d '\r' < "$TMP/cache.headers" > "$TMP/cache.headers.clean"
grep -qi "^etag: \"sha256:$LAYER_HEX\"$" "$TMP/cache.headers.clean" || fail "the blob response carries no digest ETag"
grep -qi "^cache-control: public, max-age=31536000, immutable$" "$TMP/cache.headers.clean" || fail "the blob response carries no immutable policy"
CODE="$(curl -s -o /dev/null -w '%{http_code}' -H "If-None-Match: \"sha256:$LAYER_HEX\"" "$REGISTRY_URL/v2/smoke/app/blobs/sha256:$LAYER_HEX")"
[ "$CODE" = "304" ] || fail "the blob re-validation answered $CODE, want 304"

say "negative: unknown tag, unknown blob, digest mismatch"
CODE="$(curl -s -o /dev/null -w '%{http_code}' "$REGISTRY_URL/v2/smoke/app/manifests/nope")"
[ "$CODE" = "404" ] || fail "an unknown manifest answered $CODE, want 404"
CODE="$(curl -s -o /dev/null -w '%{http_code}' "$REGISTRY_URL/v2/smoke/app/blobs/sha256:1111111111111111111111111111111111111111111111111111111111111111")"
[ "$CODE" = "404" ] || fail "an unknown blob answered $CODE, want 404"
CODE="$(curl -s -o /dev/null -w '%{http_code}' -X PUT -H "Content-Type: $ACCEPT" --data-binary @"$FIXTURES/manifest.json" "$REGISTRY_URL/v2/smoke/app/manifests/sha256:0000000000000000000000000000000000000000000000000000000000000000")"
[ "$CODE" = "400" ] || fail "a digest-mismatch push answered $CODE, want 400"

say "create a local Git repository with a lock naming this registry"
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
  - image: 127.0.0.1:$PORT/smoke/app
    tags: [v1]
    digest: $MANIFEST
    manifest_digest: $MANIFEST
    platforms: [linux/amd64]
EOF
"${GIT[@]}" add .
"${GIT[@]}" commit -q -m lock
export POKERFACE_CACHE_DIR="$TMP/cache"

say "pokerface resolve"
if ! "$PF" resolve "$REPO:main" > "$TMP/resolve.log" 2>&1; then
  cat "$TMP/resolve.log"
  fail "resolve failed"
fi
cat "$TMP/resolve.log"
grep -q "digest:  $MANIFEST" "$TMP/resolve.log" || fail "resolve printed the wrong digest"

RUNTIME=""
if command -v docker >/dev/null 2>&1; then
  RUNTIME=docker
elif command -v podman >/dev/null 2>&1; then
  RUNTIME=podman
elif command -v ctr >/dev/null 2>&1; then
  RUNTIME=containerd
fi

if [ -z "$RUNTIME" ]; then
  say "pokerface pull skipped (needs docker/podman/ctr for the import leg)"
else
  IMAGE_REF="127.0.0.1:$PORT/smoke/app:v1"
  say "pokerface pull and import into $RUNTIME"
  if ! "$PF" pull "$REPO:main" > "$TMP/pull.log" 2>&1; then
    cat "$TMP/pull.log"
    fail "pull failed"
  fi
  cat "$TMP/pull.log"
  case "$RUNTIME" in
    docker) docker image inspect "$IMAGE_REF" >/dev/null || fail "the imported image is missing from docker" ;;
    podman) podman image inspect "$IMAGE_REF" >/dev/null || fail "the imported image is missing from podman" ;;
    containerd) ctr images ls -q | grep -qx "$IMAGE_REF" || fail "the imported image is missing from containerd" ;;
  esac
fi

say "auth leg: anonymous requests are challenged"
stop_registry
write_config "$TMP/registry-auth.yaml" "$PORT" true
start_registry "$TMP/registry-auth.yaml" "$TMP/registry-auth.log"
PORT="$(sed -n 's/^LISTEN=127.0.0.1://p' "$TMP/registry-auth.log" | head -1)"
REGISTRY_URL="http://127.0.0.1:$PORT"

# 401 is the expected answer here, so no -f: capture the challenge headers.
CHALLENGE="$(curl -s -D - -o /dev/null "$REGISTRY_URL/v2/" | sed -n 's/^[Ww][Ww][Ww]-[Aa]uthenticate: //p' | tr -d '\r')"
printf '%s\n' "$CHALLENGE" | grep -q 'Bearer realm=' || fail "the /v2/ probe carried no Bearer challenge"
CODE="$(curl -s -o /dev/null -w '%{http_code}' "$REGISTRY_URL/v2/smoke/app/manifests/v1")"
[ "$CODE" = "401" ] || fail "an anonymous manifest read answered $CODE, want 401"

say "auth leg: skopeo login and push"
if command -v skopeo >/dev/null 2>&1; then
  skopeo login --tls-verify=false --username alice --password wonderland "127.0.0.1:$PORT" > "$TMP/login.log" 2>&1 \
    || { cat "$TMP/login.log"; fail "skopeo login failed"; }
  skopeo copy --dest-tls-verify=false "oci:$LAYOUT:latest" "docker://127.0.0.1:$PORT/smoke/auth:v1" > "$TMP/auth-push.log" 2>&1 \
    || { cat "$TMP/auth-push.log"; fail "the authenticated push failed"; }
  CODE="$(curl -s -o /dev/null -w '%{http_code}' "$REGISTRY_URL/v2/smoke/auth/manifests/v1")"
  [ "$CODE" = "401" ] || fail "anonymous reads should be rejected, got $CODE"
  skopeo logout "127.0.0.1:$PORT" >/dev/null 2>&1 || true
else
  say "auth push leg skipped (skopeo missing)"
fi

say "auth leg: a pull-only scope cannot push"
TOKEN="$(curl -sf -u alice:wonderland "$REGISTRY_URL/token?service=pokerface-registry&scope=repository:smoke/auth:pull" | sed -n 's/.*"token":"\([^"]*\)".*/\1/p')"
[ -n "$TOKEN" ] || fail "the token exchange failed"
CODE="$(curl -s -o /dev/null -w '%{http_code}' -X PUT -H "Authorization: Bearer $TOKEN" -H "Content-Type: $ACCEPT" --data-binary @"$FIXTURES/manifest.json" "$REGISTRY_URL/v2/smoke/auth/manifests/v9")"
[ "$CODE" = "401" ] || fail "a pull-only token pushed: $CODE, want 401"
CHALLENGE="$(curl -s -D - -o /dev/null -X PUT -H "Authorization: Bearer $TOKEN" -H "Content-Type: $ACCEPT" --data-binary @"$FIXTURES/manifest.json" "$REGISTRY_URL/v2/smoke/auth/manifests/v9" | sed -n 's/^[Ww][Ww][Ww]-[Aa]uthenticate: //p' | tr -d '\r')"
printf '%s\n' "$CHALLENGE" | grep -q 'error="insufficient_scope"' || fail "the push challenge names no insufficient_scope: $CHALLENGE"

say "all M2 checks passed"
