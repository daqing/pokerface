#!/usr/bin/env bash
# Run the compiled SQLite data-layer checks (T2.2).
#
# `emo test` always interprets, and the sqlite3 package refuses interpreted
# foreign calls (E3009), so the CRUD coverage is a compiled program:
# registry/db_selftest.emo. It opens a fresh database under TMPDIR, exercises
# every CRUD path and the schema constraints, reopens it, and runs two
# connections side by side. Exit 0 means every check passed.
#
#   scripts/check-registry-db.sh

set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
out="$root/.emo-build/db-selftest"

cd "$root"
emo build -o "$out" registry/db_selftest.emo
exec "$out"
