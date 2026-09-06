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
phys=0

for f in $FILES; do
  out=$(awk '
    # OCaml comments nest. Strip them, keeping the line numbering intact so a hit still
    # names the line a reader can open.
    #
    # A comment delimiter INSIDE A STRING LITERAL is not a delimiter. This scanner used to
    # ignore that, and the cost was total: `count(*)` inside a SQL string in
    # arch_mutants.ml opened a phantom comment that never closed, leaving end-of-file depth
    # 3 and only 789 of the 2215 lines in that file with any code left to scan. A
    # `Printf.printf "  score %d%% ..."` injected past that point — the two exact hits this
    # file names in its own header — produced PASS. So string state is tracked FIRST, the
    # way scripts/check-status-provenance.sh strips strings before counting brackets, and
    # only then are (* and *) recognised. String literals are KEPT in the scanned text,
    # because they are precisely what the patterns below have to match.
    BEGIN { depth = 0; nline = 0; nphys = 0; instr = 0; inraw = 0 }
    {
      raw = $0; out = ""; i = 1; n = length(raw)
      while (i <= n) {
        c = substr(raw, i, 1); two = substr(raw, i, 2)
        # {| ... |} raw string: no escapes, and no comment delimiters inside it either.
        if (inraw) {
          if (two == "|}") { inraw = 0; if (depth == 0) out = out two; i += 2; continue }
          if (depth == 0) out = out c
          i++; continue
        }
        # "..." with backslash escapes. A trailing backslash is the OCaml line
        # continuation, so the string state deliberately survives to the next line —
        # which is what the multi-line SQL literal needs.
        if (instr) {
          if (c == "\\") { if (depth == 0) out = out substr(raw, i, 2); i += 2; continue }
          if (c == "\"") { instr = 0; if (depth == 0) out = out c; i++; continue }
          if (depth == 0) out = out c
          i++; continue
        }
        if (c == "\"") { instr = 1; if (depth == 0) out = out c; i++; continue }
        if (two == "{|") { inraw = 1; if (depth == 0) out = out two; i += 2; continue }
        if (two == "(*") { depth++; i += 2; continue }
        if (depth > 0 && two == "*)") { depth--; i += 2; continue }
        if (depth == 0) out = out c
        i++
      }
      nphys++
      # Count the lines actually SCANNED — the ones that contributed code at depth 0 —
      # not the physical lines read. A line swallowed whole by a comment (phantom or
      # real) contributes nothing, and reporting it as inspected is reporting coverage
      # this check did not have. That number was the only visible symptom of the bug
      # above, and it lied.
      if (out ~ /[^ \t]/) nline++

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
    END {
      if (depth != 0)
        printf "%s:%d: UNBALANCED comment depth %d at end of file — the scanner lost its place\n", FILENAME, NR, depth
      if (instr || inraw)
        printf "%s:%d: UNTERMINATED string literal at end of file — the scanner lost its place\n", FILENAME, NR
      printf "#lines\t%d\t%d\n", nline, nphys
    }
  ' "$f")

  bad=$(printf '%s\n' "$out" | grep -v '^#lines' | grep -v '^$' || true)
  lines=$((lines + $(printf '%s\n' "$out" | grep '^#lines' | cut -f2)))
  phys=$((phys + $(printf '%s\n' "$out" | grep '^#lines' | cut -f3)))
  if [ -n "$bad" ]; then
    printf '%s\n' "$bad"
    hits=$((hits + $(printf '%s\n' "$bad" | wc -l)))
  fi
done

echo "check-no-score: scanned $lines line(s) of code at comment depth 0, out of $phys physical line(s), across ${DIRS[*]}"
if [ "$hits" -gt 0 ]; then
  echo "check-no-score: FAIL — $hits site(s) could emit a score, ratio, percentage or threshold" >&2
  exit 1
fi
echo "check-no-score: PASS — 0 offending site(s). One would have been a \"%%\" in a format"
echo "  string, the word score/ratio/percent/threshold inside a string literal, or float"
echo "  arithmetic (/. *. float_of_int) in code that has nothing to divide."
exit 0
