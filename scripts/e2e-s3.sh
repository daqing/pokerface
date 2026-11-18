#!/usr/bin/env bash
# Run the S3 adapter's integration test against the local fixture (T2.6).
#
# The fixture (mock/s3_fixture.emo) verifies SigV4 signatures and presigned
# expiries and keeps objects on disk, so the whole adapter path — bucket check,
# put, get, ranged get, ranged head, presigned fetch and expiry, delete — runs
# without MinIO or network. To run the same test against MinIO instead, set
# POKERFACE_TEST_S3_ENDPOINT/BUCKET/ACCESS_KEY/SECRET_KEY yourself and run
# `emo test`; the test skips when the endpoint is unset.
#
#   scripts/e2e-s3.sh

set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
tmp="${TMPDIR:-/tmp}/pokerface-s3-e2e-$$"
mkdir -p "$tmp/root"

cd "$root"
emo build -o .emo-build/s3-fixture mock/s3_fixture.emo

"./.emo-build/s3-fixture" "$tmp/root" 0 > "$tmp/fixture.log" 2>&1 &
fixture=$!
cleanup() {
  # The httpd server runs its accept loop in a child; stop both so the
  # script's stdout is not held open by an orphan.
  pkill -P "$fixture" 2>/dev/null || true
  kill "$fixture" 2>/dev/null || true
}
trap cleanup EXIT

for _ in $(seq 1 100); do
  grep -q '^LISTEN=' "$tmp/fixture.log" 2>/dev/null && break
  sleep 0.1
done
listen="$(grep '^LISTEN=' "$tmp/fixture.log" | head -1 | cut -d= -f2)"
if [ -z "$listen" ]; then
  echo "s3 fixture did not start:" >&2
  cat "$tmp/fixture.log" >&2
  exit 1
fi

echo "s3 fixture listening on $listen (root $tmp/root)"

export POKERFACE_TEST_S3_ENDPOINT="http://$listen"
export POKERFACE_TEST_S3_BUCKET="pokerface"
export POKERFACE_TEST_S3_ACCESS_KEY="AKIAEXAMPLE"
export POKERFACE_TEST_S3_SECRET_KEY="secret-value"

emo test
