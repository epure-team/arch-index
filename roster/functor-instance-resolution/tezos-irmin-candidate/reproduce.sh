#!/usr/bin/env bash
# Re-run only the bounded syntactic catalogue. No Dune/build/install occurs.
set -euo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../../.." && pwd)
TEZOS_ROOT=/home/mathias/dev/tezos/tezos
MANIFEST="$HERE/manifest-410.tsv"
BIN="$ROOT/_build/default/bin/arch_callgraph_ocaml/arch_callgraph_ocaml.exe"
QUERY="$ROOT/_build/default/bin/arch_query/arch_query.exe"
SCHEMA="$ROOT/architecture-schema.sql"

test -x "$BIN" && test -x "$QUERY" && test -r "$SCHEMA"
test -r "$MANIFEST"

# The CMT sourcefile fields are Tezos-root-relative. Creating the reversible
# corpus below Tezos/_build makes the producer derive that root correctly.
CORPUS=$(mktemp -d "$TEZOS_ROOT/_build/arch-index-functor-candidate.XXXXXX")
DB=$(mktemp /tmp/arch-index-functor-candidate.XXXXXX.db)
cleanup() {
  rm -rf "$CORPUS" "$DB" "$DB-wal" "$DB-shm"
}
trap cleanup EXIT

while IFS=$'\t' read -r slice sha path; do
  case "$slice" in ''|'#'*) continue ;; esac
  test "$(sha256sum "$path" | awk '{print $1}')" = "$sha"
  mkdir -p "$CORPUS/$slice"
  ln -s "$path" "$CORPUS/$slice/$(basename "$path")"
done < "$MANIFEST"

printf 'manifest_entries='; awk 'BEGIN { n=0 } $1 !~ /^#/ && NF { n++ } END { print n }' "$MANIFEST"
printf 'manifest_sha256='; sha256sum "$MANIFEST" | awk '{print $1}'
"$BIN" --build-dir "$CORPUS" --db-path "$DB" --schema-path "$SCHEMA"
printf '%s\n' '--- raw: functor-applications 0 ---'
ARCH_QUERY_FORMAT=json "$QUERY" "$DB" functor-applications 0
printf '%s\n' '--- raw: stats ---'
ARCH_QUERY_FORMAT=json "$QUERY" "$DB" stats
printf '%s\n' '--- derived: applications by source slice ---'
ARCH_QUERY_FORMAT=json "$QUERY" "$DB" functor-applications 2000 |
  jq -s -c '.[1] | map(if (.source|startswith("irmin/lib_irmin_pack/unix/")) then "irmin-pack-unix" elif (.source|startswith("irmin/lib_irmin_pack/")) then "irmin-pack" elif (.source|startswith("irmin/lib_irmin/")) then "irmin-core" elif (.source|startswith("src/proto_alpha/lib_protocol/")) then "proto-alpha" else "other" end) | group_by(.) | map({slice:.[0],applications:length})'
printf '%s\n' '--- derived: diagnostics ---'
ARCH_QUERY_FORMAT=json "$QUERY" "$DB" functor-applications 2000 |
  jq -s -c '.[1] | group_by(.diagnostics) | map({diagnostics:.[0].diagnostics,count:length}) | sort_by(-.count)'
