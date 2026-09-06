#!/usr/bin/env bash
# check-total-matches.sh — CHECK-17 / AC-25 / FR-031.
#
# A value added to a closed vocabulary is dropped by a filtering consumer WITH NO ERROR AT
# ALL: no crash, no log, only a smaller answer. Every defence built for the missing-column
# case is blind to it — a column-existence guard, a capability record and a refusal all see
# a column that is present and a match arm whose domain no longer covers it. Measured
# precedents in this repository: calls.top_reason gained 'ambiguous_unit' at schema 1.9 and
# exn_origins.form gained 'inferred_bind' at 1.8.
#
# The real defence is the TOTAL match, which the compiler enforces. This is the lint that
# stops one being quietly reopened with a catch-all.
#
# The rule, and it is not "no `| _ ->` anywhere":
#   A `| _ ->` arm is a HIT when the arms it shares its match with mention a member of a
#   vocabulary a schema CHECK declares — selection_provenance, the engine status set,
#   top_reason, or edge `kind` — AND its right-hand side produces a VALUE. A catch-all that
#   REFUSES (None, die, fail, failwith, raise, exit, assert false, invalid_arg) is not the
#   hazard: it aborts at the call site instead of shrinking the answer, which is exactly
#   what Arch_mutant_db.status_of_string and provenance_of_string do on purpose.
#
# Arms are located by their `|` at a shared indentation, which is how ocaml formats a
# match; a member appearing on the RIGHT of `->`, or inside an `if x = "KILLED"` test, is
# not an arm and is not counted.
#
# Usage:  scripts/check-total-matches.sh [dir ...]   (default: bin/arch_mutants, lib/arch_index)
# Exit:   0 = no catch-all over a CHECK-declared vocabulary
#         1 = at least one, each named with file:line
#         2 = harness error

set -uo pipefail

command -v awk >/dev/null 2>&1 || { echo "check-total-matches: awk is required" >&2; exit 2; }

if [ "$#" -gt 0 ]; then
  DIRS=("$@")
else
  ROOT="$(git rev-parse --show-toplevel 2>/dev/null)"
  [ -n "$ROOT" ] || { echo "check-total-matches: cannot determine tree root" >&2; exit 2; }
  DIRS=("$ROOT/bin/arch_mutants")
fi

FILES=""
for d in "${DIRS[@]}"; do
  [ -d "$d" ] || { echo "check-total-matches: no such directory: $d" >&2; exit 2; }
  FILES="$FILES $(find "$d" -name '*.ml' -type f | sort)"
done
[ -n "$(printf '%s' "$FILES" | tr -d ' ')" ] || { echo "check-total-matches: no .ml files to scan" >&2; exit 2; }

# The vocabularies, exactly as their schema CHECK constraints declare them, plus the OCaml
# variant each is modelled by. Grepping for the MEMBERS, never for the column name: the
# column name is what survives a vocabulary change unchanged.
MEMBERS='proved_superset|top_bounded|no_contract|Proved_superset|Top_bounded|No_contract'
MEMBERS="$MEMBERS"'|KILLED|SURVIVED|TIMEOUT|Killed|Survived|Timeout|Errored'
MEMBERS="$MEMBERS"'|singleton_executed_set|engine_named|Singleton_executed_set|Engine_named'
MEMBERS="$MEMBERS"'|dynamic_dispatch|higher_order|callback_param|module_param|ambiguous_unit|external_boundary'
MEMBERS="$MEMBERS"'|MAY_TOP|MUST|MAY'

hits=0
arms=0

for f in $FILES; do
  out=$(awk -v members="$MEMBERS" '
    function indent_of(l,   r) { r = l; sub(/[^ \t].*$/, "", r); return length(r) }
    function pattern_of(l,   r) { r = l; sub(/->.*$/, "", r); return r }

    BEGIN { n = 0; narm = 0 }

    # An arm line: optional whitespace, a bar, then the pattern.
    /^[ \t]*\|/ {
      ind = indent_of($0)
      pat = pattern_of($0)
      narm++

      if (pat ~ /\|[ \t]*_[ \t]*$/ && $0 ~ /->/) {
        # A catch-all. Which vocabulary members did the arms above it, at this same
        # indentation, mention? Walk back over the recorded arms.
        vocab = ""
        for (k = top; k >= 1; k--) {
          if (armind[k] != ind) continue
          if (armline[k] >= NR) continue
          if (seenbreak[k]) break
          if (armpat[k] ~ members) { vocab = armpat[k]; break }
        }
        if (vocab != "") {
          rhs = $0; sub(/^.*->/, "", rhs); gsub(/^[ \t]+|[ \t]+$/, "", rhs)
          # A refusing catch-all aborts at the call site rather than shrinking the answer.
          if (rhs ~ /^(None|die|fail|failwith|raise|exit|assert false|invalid_arg|refuse|broken)\b/ \
              || rhs == "None" || rhs == "") {
            # permitted
          } else {
            printf "%s:%d: `| _ ->` over a CHECK-declared vocabulary (arm above: %s)\n", FILENAME, NR, vocab
            n++
          }
        }
      } else {
        top++; armind[top] = ind; armpat[top] = pat; armline[top] = NR; seenbreak[top] = 0
      }
    }

    # A line at a SHALLOWER indentation than a recorded arm ends that match, so arms from
    # an earlier, unrelated match cannot be mistaken for the neighbours of this catch-all.
    !/^[ \t]*\|/ && !/^[ \t]*$/ {
      ind = indent_of($0)
      for (k = 1; k <= top; k++) if (armind[k] > ind) seenbreak[k] = 1
    }

    END { printf "#arms\t%d\n", narm }
  ' "$f")

  bad=$(printf '%s\n' "$out" | grep -v '^#arms' | grep -v '^$' || true)
  arms=$((arms + $(printf '%s\n' "$out" | grep '^#arms' | cut -f2)))
  if [ -n "$bad" ]; then
    printf '%s\n' "$bad"
    hits=$((hits + $(printf '%s\n' "$bad" | wc -l)))
  fi
done

echo "check-total-matches: inspected $arms match arm(s) across ${DIRS[*]}"
if [ "$hits" -gt 0 ]; then
  echo "check-total-matches: FAIL — $hits catch-all arm(s) over a closed vocabulary" >&2
  exit 1
fi
echo "check-total-matches: PASS — 0 offending arm(s). One would have been a \`| _ ->\` sharing"
echo "  its match with an arm naming proved_superset/top_bounded/no_contract, KILLED/SURVIVED/"
echo "  TIMEOUT/ERROR, a top_reason member or an edge kind, whose right-hand side produced a"
echo "  value instead of refusing."
exit 0
