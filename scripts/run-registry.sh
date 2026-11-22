#!/usr/bin/env bash
# Run the registry under a signal-aware supervisor (T2.1).
#
# Emo exposes no custom signal handler. The server therefore ignores SIGTERM /
# SIGINT and watches a shutdown file; this launcher owns the signals: on
# SIGTERM/SIGINT it creates the file and waits for the server to stop accepting
# and drain in-flight requests. Run the service through this script (or set
# POKERFACE_REGISTRY_SHUTDOWN_FILE yourself and touch that file).
#
#   scripts/run-registry.sh .emo-build/pokerface-registry --config registry.yaml

set -euo pipefail

if [ "$#" -lt 1 ]; then
  printf 'usage: %s <registry-binary> [--config <path>]\n' "$0" >&2
  exit 2
fi

bin="$1"
shift

if [ -n "${POKERFACE_REGISTRY_SHUTDOWN_FILE:-}" ]; then
  shutdown_file="$POKERFACE_REGISTRY_SHUTDOWN_FILE"
else
  shutdown_file="${TMPDIR:-/tmp}/pokerface-registry-shutdown-$$"
  export POKERFACE_REGISTRY_SHUTDOWN_FILE="$shutdown_file"
fi
rm -f "$shutdown_file"

"$bin" "$@" &
child=$!

terminate() {
  : > "$shutdown_file"
}

trap terminate TERM INT

set +e
wait "$child"
status=$?
# A trapped signal interrupts wait with 128+; wait again for the drain.
if [ "$status" -ge 128 ]; then
  wait "$child"
  status=$?
fi
rm -f "$shutdown_file"
exit "$status"
