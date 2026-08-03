#!/usr/bin/env bash
# Reproduce the PoC reports. Usage: ./run.sh <dir> [<dir> ...]
set -euo pipefail
cd "$(dirname "$0")"
dune build --root . 2>/dev/null
exec ./_build/default/bin/decision_lint.exe "$@"
