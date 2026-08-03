#!/usr/bin/env bash
# query-port-diff.sh — differential gate for the arch-query bash → OCaml port.
#
# The SQL was carried over verbatim, so the only things that can differ are argument binding
# and output rendering. Both are exactly what a unit test would miss, so this runs the OLD
# script and the NEW binary over the same databases with the same arguments and diffs every
# byte of stdout plus the exit code.
#
# RECOVERING THE ORACLE
#
# The bash original is no longer in the tree, and it CANNOT be used unmodified: it hardcoded
# `sqlite3 -box`, with no ARCH_QUERY_FORMAT at all. Handing it to this script as committed would
# compare box output against every other mode and report five modes' worth of differences that
# mean nothing. The loop below therefore prepares the oracle itself — recovering it from a git
# revision and applying exactly one substitution, so the comparison is reproducible from this
# tree rather than from a scratch file someone edited by hand:
#
#   q() { sqlite3 -box "$DB" "$1"; }
#     ->  q() { sqlite3 "-${ARCH_QUERY_FORMAT:-box}" "$DB" "$1"; }
#
# That is the whole patch, and it changes only which sqlite3 renderer runs — which is precisely
# the behaviour under test, since the port reimplements those renderers in OCaml.
#
#   scripts/query-port-diff.sh --from-rev <sha> <new-binary> <db> [<db> ...]
#   scripts/query-port-diff.sh <old-arch-query> <new-binary> <db> [<db> ...]
#
# EXPECTED divergences, declared here rather than discovered as failures. Each is a place the
# port deliberately does not reproduce the original:
#
#  1. MAIN schema, callers-of / callees-of / reachable-from / fan-in: the bash version died with
#     a raw sqlite error (exit 1) because those read calls.caller_name, which exists only on the
#     FLAT schema. The port implements main-schema forms.
#  2. unreachable / escapes with a name that is not in the index: the bash version answered
#     "UNREACHABLE … sound" — a proof about a function that does not exist. The port REFUSES
#     (exit 3).
#  3. Subcommands the oracle revision does not implement, and `stats` on an index carrying
#     tables that revision predates (dead_code_sites, function_effects, mutation_sites). These
#     are feature drift, not port behaviour: the oracle is frozen while the binary keeps moving.
#     Detected from the oracle's own source and from the database, not from a hand-kept list.
#
# Everything else must match byte-for-byte across six output modes on both schemas.
#
# The revision to use is the commit BEFORE the port — the one whose arch-query the port
# replaced. Class 3 grows with every release after it, so a run with a large declared count is
# telling you the gate has drifted, not that the port is fine.
#
#   scripts/query-port-diff.sh --from-rev 22af864^ \
#     _build/default/bin/arch_query/arch_query.exe <flat.db> <main.db>
#
# At the time of writing that reports: 396 comparison(s), 0 unexpected, 180 declared.
set -u

if [ "${1:-}" = "--from-rev" ]; then
  shift
  REV="${1:?--from-rev needs a git revision that still contains the bash arch-query}"; shift
  OLD="$(mktemp)"
  git show "$REV:arch-query" > "$OLD" \
    || { echo "query-port-diff: $REV has no arch-query at the repo root" >&2; exit 2; }
  grep -q 'q()    { sqlite3 -box "\$DB" "\$1"; }' "$OLD" \
    || { echo "query-port-diff: $REV:arch-query does not have the expected q() line — the patch below would silently not apply" >&2; exit 2; }
  sed -i 's|q()    { sqlite3 -box "\$DB" "\$1"; }|q()    { sqlite3 "-${ARCH_QUERY_FORMAT:-box}" "$DB" "$1"; }|' "$OLD"
  chmod +x "$OLD"
  trap 'rm -f "$OLD"' EXIT
  echo "query-port-diff: oracle = $REV:arch-query + the documented ARCH_QUERY_FORMAT patch"
else
  OLD="${1:?usage: query-port-diff.sh [--from-rev <sha>] <old> <new> <db>...}"; shift
fi
NEW="${1:?new binary required}"; shift
fails=0; checked=0; expected=0

# Does the oracle implement this subcommand at all? The bash script dispatches on
# `  <name>)` at a two-space indent, so its own source answers the question — which keeps this
# self-maintaining as the oracle revision moves, instead of a hand-kept list that rots.
oracle_supports() { grep -qE "^  $1\)" "$OLD"; }

# Has this index got tables the oracle predates? `stats` prints a block per table it finds, so on
# an index carrying dead_code_sites / function_effects / mutability columns the port prints more
# than the oracle ever could. On an index without them the two must still match exactly.
db_postdates_oracle() {
  local db="$1"
  [ "$(sqlite3 "$db" "SELECT count(*) FROM sqlite_master WHERE name IN ('dead_code_sites','function_effects');" 2>/dev/null)" != "0" ] && return 0
  [ "$(sqlite3 "$db" "SELECT count(*) FROM pragma_table_info('functions') WHERE name='mutation_sites';" 2>/dev/null)" != "0" ] && return 0
  return 1
}

# A divergence declared in the header above. Counted and printed, never silently skipped: a
# gate that hides its exclusions is how a real regression gets filed under "known".
expect_diff() { # $1=db, rest=args -> 0 if this pair is an expected divergence
  local db="$1"; shift
  oracle_supports "$1" || return 0
  local flat
  flat=$(sqlite3 "$db" "SELECT count(*) FROM pragma_table_info('calls') WHERE name='caller_name';" 2>/dev/null)
  case "$1" in
    callers-of|callees-of|reachable-from|fan-in) [ "${flat:-0}" = "0" ] && return 0 ;;
    stats) db_postdates_oracle "$db" && return 0 ;;
    unreachable|escapes)
      for n in "${@:2}"; do
        [ -z "$n" ] && continue
        [ "$(sqlite3 "$db" "SELECT count(*) FROM functions WHERE name='${n//\'/}';" 2>/dev/null)" = "0" ] \
          && return 0
      done ;;
  esac
  return 1
}

run_both() { # $1=db, rest=args
  local db="$1"; shift
  local oo no oc nc
  oo=$("$OLD" "$db" "$@" 2>/tmp/qp-oe); oc=$?
  no=$("$NEW" "$db" "$@" 2>/tmp/qp-ne); nc=$?
  checked=$((checked+1))
  if expect_diff "$db" "$@"; then
    if [ "$oo" != "$no" ] || [ "$oc" != "$nc" ]; then expected=$((expected+1)); fi
    return 0
  fi
  if [ "$oo" != "$no" ]; then
    echo "DIFF stdout: $(basename "$db") $* [fmt=${ARCH_QUERY_FORMAT:-box}]" >&2
    diff <(printf '%s\n' "$oo") <(printf '%s\n' "$no") | head -10 >&2
    fails=$((fails+1))
  fi
  if [ "$oc" != "$nc" ]; then
    echo "DIFF exit: $(basename "$db") $* — old=$oc new=$nc" >&2
    fails=$((fails+1))
  fi
}

for db in "$@"; do
  [ -f "$db" ] || { echo "skip (no such db): $db" >&2; continue; }
  names=$(sqlite3 "$db" "SELECT name FROM functions LIMIT 6;" 2>/dev/null | tr '\n' ' ')
  for fmt in box list csv markdown line json; do
    export ARCH_QUERY_FORMAT="$fmt"
    run_both "$db" stats
    run_both "$db" exported
    run_both "$db" unresolved
    run_both "$db" fan-in 7
    run_both "$db" find e
    run_both "$db" dead-code
    run_both "$db" pure-fns
    run_both "$db" useless-branches 5
    run_both "$db" dead-blocks 5
    run_both "$db" mutation-density 5
    for n in $names; do
      run_both "$db" callers-of "$n"
      run_both "$db" callees-of "$n"
      run_both "$db" reachable-from "$n"
      run_both "$db" escapes "$n"
    done
    set -- $names
    if [ $# -ge 2 ]; then
      run_both "$db" reaches "$1" "$2"
      run_both "$db" unreachable "$1" "$2"
      run_both "$db" reaches "$1" __absent__
      run_both "$db" unreachable "$1" __absent__
      run_both "$db" unreachable __absent__ "$2"
    fi
  done
  unset ARCH_QUERY_FORMAT
done

echo "query-port-diff: $checked comparison(s), $fails unexpected difference(s), $expected declared divergence(s)"
[ "$fails" -eq 0 ]
