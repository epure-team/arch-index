#!/usr/bin/env bash
# check-no-score.sh — FR-015. No output path emits a mutation score, ratio, percentage or
# threshold.
#
# docs/mutation-testing.md refuses the mutation score ON RECORD, for the reason a coverage
# percentage is refused: a single number is exactly as gameable as the thing it summarises,
# and a campaign whose verdicts are KILLED / SURVIVED / UNKNOWN / UNKNOWN_NO_CONTRACT /
# ERROR / PENDING has no denominator that means anything. Two of those six verdicts say
# "we do not know", so any fraction built from them silently decides what an UNKNOWN counts
# as — and whichever way it decides, it is wrong for half its readers.
#
# What is scanned, after OCaml comments are stripped (a comment SAYING there is no score is
# not a score, and this file's own subject matter guarantees the word appears in prose):
#   * a literal percent sign in a format string ("%%"), which only ever renders a rate;
#   * the words score / ratio / percent / percentage / threshold inside a string literal
#     that reaches an output path;
#   * float arithmetic (`/.`, `*.`, `float_of_int`) anywhere in the campaign's code, which
#     is how a rate gets computed in the first place — the campaign counts things, and a
#     count needs no floats at all.
#
# Usage:  scripts/check-no-score.sh [dir ...]   (default: bin/arch_mutants)
# Exit:   0 = no score, ratio, percentage or threshold on any output path
#         1 = at least one, named with file:line
#         2 = harness error

set -uo pipefail

command -v awk >/dev/null 2>&1 || { echo "check-no-score: awk is required" >&2; exit 2; }

if [ "$#" -gt 0 ]; then
  DIRS=("$@")
else
  ROOT="$(git rev-parse --show-toplevel 2>/dev/null)"
  [ -n "$ROOT" ] || { echo "check-no-score: cannot determine tree root" >&2; exit 2; }
  DIRS=("$ROOT/bin/arch_mutants")
fi

FILES=""
for d in "${DIRS[@]}"; do
  [ -d "$d" ] || { echo "check-no-score: no such directory: $d" >&2; exit 2; }
  FILES="$FILES $(find "$d" -name '*.ml' -type f | sort)"
done
[ -n "$(printf '%s' "$FILES" | tr -d ' ')" ] || { echo "check-no-score: no .ml files to scan" >&2; exit 2; }

hits=0
lines=0

for f in $FILES; do
  out=$(awk '
    # OCaml comments nest. Strip them, keeping the line numbering intact so a hit still
    # names the line a reader can open.
    BEGIN { depth = 0; nline = 0 }
    {
      raw = $0; out = ""; i = 1; n = length(raw)
      while (i <= n) {
        two = substr(raw, i, 2)
        if (depth == 0 && two == "(*") { depth = 1; i += 2; continue }
        if (depth > 0 && two == "(*") { depth++; i += 2; continue }
        if (depth > 0 && two == "*)") { depth--; i += 2; continue }
        if (depth == 0) out = out substr(raw, i, 1)
        i++
      }
      nline++

      if (out ~ /%%/)
        printf "%s:%d: a literal percent sign in a format string\n", FILENAME, NR
      # Word-bounded, and awk has no \b: "migration" contains "ratio" and a relative
      # path contains "/.", so an unbounded pattern flags the ppx_blob line that embeds
      # the schema migration and nothing else. A guard that cries wolf on its own
      # neighbours gets disabled, which is worse than not having one.
      if (out ~ /"[^"]*(^|[^A-Za-z])([Ss]core|[Rr]atio|[Pp]ercent|[Tt]hreshold)([^A-Za-z]|$)[^"]*"/ \
          || out ~ /"[^"]*(^|[^A-Za-z])([Ss]core|[Rr]atio|[Pp]ercent|[Tt]hreshold)s?[^A-Za-z][^"]*"/)
        printf "%s:%d: a string literal naming a score, ratio, percentage or threshold\n", FILENAME, NR
      if (out ~ /[ \t]\/\.[ \t]|[ \t]\*\.[ \t]|float_of_int|Float\./)
        printf "%s:%d: float arithmetic on a path that should only ever count\n", FILENAME, NR
    }
    END { printf "#lines\t%d\n", nline }
  ' "$f")

  bad=$(printf '%s\n' "$out" | grep -v '^#lines' | grep -v '^$' || true)
  lines=$((lines + $(printf '%s\n' "$out" | grep '^#lines' | cut -f2)))
  if [ -n "$bad" ]; then
    printf '%s\n' "$bad"
    hits=$((hits + $(printf '%s\n' "$bad" | wc -l)))
  fi
done

echo "check-no-score: inspected $lines line(s) of code (comments stripped) across ${DIRS[*]}"
if [ "$hits" -gt 0 ]; then
  echo "check-no-score: FAIL — $hits site(s) could emit a score, ratio, percentage or threshold" >&2
  exit 1
fi
echo "check-no-score: PASS — 0 offending site(s). One would have been a \"%%\" in a format"
echo "  string, the word score/ratio/percent/threshold inside a string literal, or float"
echo "  arithmetic (/. *. float_of_int) in code that has nothing to divide."
exit 0
