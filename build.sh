#!/usr/bin/env bash
# build.sh — rebuild vendored binaries. Pass a target or rebuild all.
# Usage:
#   ./build.sh                    — build everything
#   ./build.sh go                 — build arch-callgraph-go (Go, no extra deps)
#   ./build.sh ocaml              — build arch_index_cli (OCaml, needs EPURE_SRC + opam)
#   ./build.sh ocaml-callgraph    — build arch-callgraph-ocaml (OCaml, needs EPURE_SRC + opam)
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET="${1:-all}"

build_go() {
  echo "building arch-callgraph-go ..."
  ( cd "$HERE/callgraph-go" && go build -o "$HERE/bin/arch-callgraph-go" . )
  chmod +x "$HERE/bin/arch-callgraph-go"
  echo "ok: bin/arch-callgraph-go"
}

build_ocaml() {
  EPURE_SRC="${EPURE_SRC:-$HOME/dev/epure}"
  [ -d "$EPURE_SRC/src/arch_index" ] || { echo "build.sh: epure source not found at $EPURE_SRC (set EPURE_SRC)" >&2; exit 2; }
  echo "building arch_index_cli from $EPURE_SRC ..."
  ( cd "$EPURE_SRC" && opam exec -- dune build tools/arch_index_cli.exe )
  cp "$EPURE_SRC/_build/default/tools/arch_index_cli.exe" "$HERE/bin/arch_index_cli"
  cp "$EPURE_SRC/docs/architecture-schema.sql" "$HERE/architecture-schema.sql"
  chmod +x "$HERE/bin/arch_index_cli"
  echo "ok: bin/arch_index_cli + architecture-schema.sql refreshed"
  echo "NOTE: a clean standalone extraction (epure_arch_index as its own opam lib, epic e63 #419)"
  echo "      would remove the epure-checkout dependency. Until then this rebuilds from EPURE_SRC."
}

build_ocaml_callgraph() {
  EPURE_SRC="${EPURE_SRC:-$HOME/dev/epure}"
  [ -f "$EPURE_SRC/tools/arch_callgraph_ocaml.ml" ] || { echo "build.sh: arch_callgraph_ocaml.ml not found at $EPURE_SRC (set EPURE_SRC)" >&2; exit 2; }
  echo "building arch-callgraph-ocaml from $EPURE_SRC ..."
  ( cd "$EPURE_SRC" && opam exec -- dune build tools/arch_callgraph_ocaml.exe )
  cp "$EPURE_SRC/_build/default/tools/arch_callgraph_ocaml.exe" "$HERE/bin/arch-callgraph-ocaml"
  chmod +x "$HERE/bin/arch-callgraph-ocaml"
  echo "ok: bin/arch-callgraph-ocaml"
}

case "$TARGET" in
  go)               build_go ;;
  ocaml)            build_ocaml ;;
  ocaml-callgraph)  build_ocaml_callgraph ;;
  all)              build_go; build_ocaml; build_ocaml_callgraph ;;
  *)                echo "build.sh: unknown target '$TARGET' (go|ocaml|ocaml-callgraph|all)" >&2; exit 2 ;;
esac
