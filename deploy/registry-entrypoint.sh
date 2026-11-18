#!/bin/sh
# The registry entrypoint (T2.17): turns SIGTERM/SIGINT into the shutdown
# marker file the service's main loop watches — the server ignores signals
# by design, so the container's PID 1 owns the signal translation — then
# waits for the drain to finish before exiting.

set -e

shutdown_file="${POKERFACE_REGISTRY_SHUTDOWN_FILE:-/data/registry.shutdown}"
registry_bin="${REGISTRY_BIN:-/usr/local/bin/registry}"
term_handler() {
  echo "registry: shutdown requested" >&2
  touch "$shutdown_file"
}
trap term_handler TERM INT

"$registry_bin" "$@" &
server_pid=$!

# Reap the server's exit and drop the stale marker for the next start. A
# trapped signal interrupts `wait`, so the reap loops until the server is
# really gone — leaving early would cancel the in-flight drain.
set +e
while kill -0 "$server_pid" 2>/dev/null; do
  wait "$server_pid"
done
wait "$server_pid" 2>/dev/null
status=$?
rm -f "$shutdown_file"
exit "$status"
