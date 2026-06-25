#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

TMPDIR="${TMPDIR:-/mnt/ssd-external-2to/whitehat-buildcache/tmp}"
DUNE_CACHE_ROOT="${DUNE_CACHE_ROOT:-/mnt/ssd-external-2to/whitehat-buildcache/dune}"
export TMPDIR DUNE_CACHE_ROOT

opam exec -- dune build

echo "Build successful."
echo "Binaries:"
echo "  ./_build/install/default/bin/arch_index_cli"
echo "  ./_build/install/default/bin/arch_callgraph_ocaml"
