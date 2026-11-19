#!/bin/sh
# The docs site's local preview (T4.8): builds docs-site/site/ and serves
# it at http://127.0.0.1:8080. Needs python3 and the `markdown` package
# (pip install markdown); the same build runs in the Pages workflow.
set -eu
DIR="$(cd "$(dirname "$0")" && pwd)"
python3 "$DIR/build.py"
exec python3 -m http.server 8080 --bind 127.0.0.1 --directory "$DIR/site"
