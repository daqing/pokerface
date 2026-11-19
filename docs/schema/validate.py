#!/usr/bin/env python3
# The schema validator (T4.11): every example under examples/ must validate
# against the JSON Schemas in docs/schema/. Wired into the docs workflow
# (.github/workflows/docs.yaml), so an example that drifts from its schema
# fails the build. Dependencies: pyyaml + jsonschema (pinned in the
# workflow; python3 -c 'import yaml, jsonschema' locally).

import json
import sys
from pathlib import Path

import jsonschema
import yaml

ROOT = Path(__file__).resolve().parent.parent.parent
SCHEMA_DIR = ROOT / "docs" / "schema"
EXAMPLES = ROOT / "examples"

PAIRS = [
    ("pokerface.yaml", "pokerface-yaml.schema.json"),
    ("pokerface.lock.yaml", "pokerface-lock.schema.json"),
]


def main() -> int:
    failures = []
    for example, schema_name in PAIRS:
        doc = yaml.safe_load((EXAMPLES / example).read_text(encoding="utf-8"))
        schema = jsonschema.Draft202012Validator(
            json.loads((SCHEMA_DIR / schema_name).read_text(encoding="utf-8"))
        )
        for error in sorted(schema.iter_errors(doc), key=lambda e: e.json_path):
            failures.append(f"{example}: {error.json_path}: {error.message}")
    if failures:
        print("schema validation failed:", file=sys.stderr)
        for failure in failures:
            print(f"  - {failure}", file=sys.stderr)
        return 1
    print(f"schema validation: {len(PAIRS)} examples ok")
    return 0


if __name__ == "__main__":
    sys.exit(main())
