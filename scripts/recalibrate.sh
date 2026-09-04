#!/usr/bin/env bash
# recalibrate.sh — attribution-gated recalibration of measured constants.
#
# The problem this exists for: this repository pins numbers that describe a
# measurement (test/fixtures/self-index-stats.txt) and numbers that impose a
# bound (must_null_ceiling's clean_measured). Both go stale on rebase, and the
# cheapest way to make CI green again is to overwrite them with whatever the
# branch now measures. That is also how both stop working:
#
#   - a golden overwritten without checking WHY it moved silently absorbs a
#     behaviour change into what is supposed to be a change DETECTOR;
#   - a ratchet raised to whatever the branch measures is not a ratchet. It has
#     already happened here: clean_measured was calibrated at 321 on
#     2026-09-01, main measured 340 by 2026-09-04, and that undeclared +19 ate
#     19 of the 25 headroom that everyone else was still budgeting against.
#
# So this does not "recalibrate on rebase". It ATTRIBUTES the movement first,
# and only writes the part it can prove is not behavioural.
#
# THE 2x2. A constant measured over the repo's own build has exactly two
# possible causes of movement, and only one of them is legitimate:
#
#                        corpus=base     corpus=new
#     binary=base            A               C
#     binary=new             B               D
#
#     source delta     = C - A     the branch added/removed code to measure
#     behaviour delta  = B - A     the branch changed what the producer DOES
#     interaction      = D - A - (C-A) - (B-A)
#
# A recalibration is safe exactly when behaviour delta = 0 and interaction = 0:
# the number moved because there is more code, not because the same code is now
# analysed differently. If behaviour delta is non-zero the movement may still be
# correct — but it is a claim about the analysis, and it must be argued and
# reviewed, not absorbed by a script. This tool refuses and prints the table.
#
# ASYMMETRY FOR RATCHETS. A golden is descriptive: restoring it restores its
# ability to detect the NEXT change, in either direction. A ratchet is
# normative, so the two directions are not alike:
#
#     metric FELL  -> tighten automatically. Strictly safer, and the manual step
#                     is exactly the one people skip, which is why ratchets drift
#                     upward over time and never back down.
#     metric ROSE  -> never automatic, even with a clean attribution. Raising a
#                     bound to meet the code is the failure mode, not the fix.
#
# Usage:
#   scripts/recalibrate.sh --check          verify every constant is CURRENT
#                                           against this tree (CI mode; exit 1
#                                           on stale, exit 2 on unusable input)
#   scripts/recalibrate.sh --write          attribute, then write what is safe
#   scripts/recalibrate.sh --explain        print the 2x2 and change nothing
#
#   --base <ref>     baseline to attribute against (default: origin/main)
#   --only <metric>  golden | ceiling
#
# Exit: 0 ok / 1 stale or refused / 2 degraded (cannot measure)

set -u

MODE=""
BASE_REF="origin/main"
ONLY=""

while [ $# -gt 0 ]; do
  case "$1" in
    --check|--write|--explain|--self-test) MODE="${1#--}" ;;
    --base) shift; BASE_REF="${1:-}" ;;
    --only) shift; ONLY="${1:-}" ;;
    -h|--help) sed -n '2,60p' "$0"; exit 0 ;;
    *) echo "recalibrate: unknown argument: $1" >&2; exit 2 ;;
  esac
  shift
done

if [ -z "$MODE" ]; then
  echo "recalibrate: one of --check / --write / --explain / --self-test is required" >&2
  exit 2
fi

# ---------------------------------------------------------------------------
# the verdict, as a pure function of the four cells
# ---------------------------------------------------------------------------
# Kept separate from the measuring so it can be exercised directly (--self-test).
# The INTERACTION arm is unreachable from any branch in this repository today —
# it needs a producer change that is inert on the old corpus and live on the new
# one — and an arm that has never been seen fire is an arm nobody should trust.
#
#   SOURCE_ONLY  both binaries agree on both corpora: only the code moved.
#   BEHAVIOURAL  they disagree on the OLD corpus: the analysis itself changed.
#   INTERACTION  they agree on the old corpus and disagree on the new one.
classify() {
  local a="$1" b="$2" c="$3" d="$4"
  if [ "$a" != "$b" ]; then echo BEHAVIOURAL
  elif [ "$c" != "$d" ]; then echo INTERACTION
  else echo SOURCE_ONLY
  fi
}

self_test() {
  local fails=0 got
  # got=expected : A B C D
  local cases="
SOURCE_ONLY:340:340:340:340
SOURCE_ONLY:761:761:780:780
BEHAVIOURAL:340:339:340:339
BEHAVIOURAL:340:339:340:340
INTERACTION:340:340:340:339
INTERACTION:340:340:355:340
"
  while IFS=: read -r want a b c d; do
    [ -z "${want:-}" ] && continue
    got="$(classify "$a" "$b" "$c" "$d")"
    if [ "$got" = "$want" ]; then
      printf '  ok   %-12s A=%s B=%s C=%s D=%s\n' "$got" "$a" "$b" "$c" "$d"
    else
      printf '  FAIL want %-12s got %-12s A=%s B=%s C=%s D=%s\n' "$want" "$got" "$a" "$b" "$c" "$d"
      fails=$(( fails + 1 ))
    fi
  done <<EOF
$cases
EOF
  # A multi-line golden must classify exactly like a scalar: the check is
  # string inequality precisely so it does not need the values to be numbers.
  got="$(classify "m: 23
f: 761" "m: 23
f: 761" "m: 23
f: 780" "m: 23
f: 780")"
  if [ "$got" = SOURCE_ONLY ]; then echo "  ok   SOURCE_ONLY  multi-line golden"
  else echo "  FAIL multi-line golden classified $got"; fails=$(( fails + 1 )); fi
  # 1, not "$fails": the count would collide with exit 2 (degraded input) at two
  # failures, and a caller reading the exit code cares whether it passed.
  if [ "$fails" = 0 ]; then echo "self-test: all cases pass"; return 0; fi
  echo "self-test: $fails case(s) FAILED"
  return 1
}

# --self-test needs nothing built and no repository state, so it is dispatched
# here, as soon as the logic it exercises exists.
if [ "$MODE" = "self-test" ]; then self_test; exit $?; fi


REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || {
  echo "recalibrate: not inside a git repository" >&2; exit 2; }
cd "$REPO_ROOT" || exit 2

# dune roots itself by searching UPWARD, so a stray dune-project in an ancestor
# (a shared /tmp, notably) silently hijacks a bare invocation and builds the
# wrong tree. --root . is not optional here.
DUNE="dune"
build_tree() { ( cd "$1" && $DUNE build --root . 2>&1 | tail -20 ); }

BASE_SHA="$(git rev-parse --verify "${BASE_REF}^{commit}" 2>/dev/null)" || {
  echo "recalibrate: cannot resolve base ref '$BASE_REF'" >&2; exit 2; }

WORK="$(mktemp -d "${TMPDIR:-/tmp}/recalibrate.XXXXXX")" || exit 2
BASE_TREE="$WORK/base"
cleanup() {
  git worktree remove --force "$BASE_TREE" >/dev/null 2>&1
  rm -rf "$WORK"
}
trap cleanup EXIT

echo "recalibrate: baseline $BASE_REF = ${BASE_SHA:0:12}"
git worktree add --detach "$BASE_TREE" "$BASE_SHA" >/dev/null 2>&1 || {
  echo "recalibrate: could not create baseline worktree" >&2; exit 2; }

echo "recalibrate: building baseline…"
build_tree "$BASE_TREE" >/dev/null || { echo "recalibrate: baseline build failed" >&2; exit 2; }
echo "recalibrate: building this tree…"
build_tree "$REPO_ROOT" >/dev/null || { echo "recalibrate: build failed" >&2; exit 2; }

producer() { echo "$1/_build/default/bin/arch_callgraph_ocaml/arch_callgraph_ocaml.exe"; }

# One cell of the 2x2: index CORPUS with the producer built from BIN_TREE.
# The binary is invoked by PATH after an explicit build rather than through
# `dune exec`, which does NOT rebuild the producer (deps apply to `runtest`)
# and would silently measure a stale one — the number would then faithfully
# describe a binary, just not the one being attributed.
index_cell() {
  local bin_tree="$1" corpus="$2" out="$3"
  local exe; exe="$(producer "$bin_tree")"
  [ -x "$exe" ] || { echo "recalibrate: missing producer $exe" >&2; return 2; }
  "$exe" --build-dir="$corpus" --db-path="$out" \
         --schema-path="$REPO_ROOT/architecture-schema.sql" >/dev/null 2>&1
}

q() { sqlite3 "$1" "$2" 2>/dev/null; }

# ---------------------------------------------------------------------------
# metric definitions
# ---------------------------------------------------------------------------
# Each metric declares the corpus it is measured OVER and the query that
# produces it. Stating the corpus per metric is deliberate: the recurring defect
# on this repository is a correct number at the wrong scope, and a metric whose
# scope lives only in a caller's head is one refactor away from being measured
# over something else entirely.

metric_corpus() {
  case "$1" in
    golden)  echo "_build/default/lib/arch_index" ;;
    ceiling) echo "_build/default" ;;
  esac
}

metric_value() {
  local metric="$1" db="$2"
  case "$metric" in
    golden)
      printf 'modules: %s\nfunctions: %s\ncalls: %s\n' \
        "$(q "$db" 'SELECT count(*) FROM modules;')" \
        "$(q "$db" 'SELECT count(*) FROM functions;')" \
        "$(q "$db" 'SELECT count(*) FROM calls;')"
      ;;
    ceiling)
      q "$db" "SELECT count(*) FROM calls WHERE kind = 'MUST' AND callee_id IS NULL \
               AND callee_name NOT LIKE 'Stdlib.%';"
      ;;
  esac
}

metric_pinned() {
  case "$1" in
    golden)  cat "$REPO_ROOT/test/fixtures/self-index-stats.txt" 2>/dev/null ;;
    ceiling) sed -n 's/^let clean_measured = \([0-9]\+\).*/\1/p' \
               "$REPO_ROOT/tezt/tests/must_null_ceiling.ml" 2>/dev/null ;;
  esac
}

metric_kind() { case "$1" in golden) echo descriptive ;; ceiling) echo ratchet ;; esac; }

# ---------------------------------------------------------------------------
# the 2x2
# ---------------------------------------------------------------------------
STATUS=0
METRICS="golden ceiling"
[ -n "$ONLY" ] && METRICS="$ONLY"

for metric in $METRICS; do
  corpus_rel="$(metric_corpus "$metric")"
  [ -n "$corpus_rel" ] || { echo "recalibrate: unknown metric '$metric'" >&2; exit 2; }

  index_cell "$BASE_TREE" "$BASE_TREE/$corpus_rel"  "$WORK/aa.db" || exit 2   # A
  index_cell "$REPO_ROOT" "$BASE_TREE/$corpus_rel"  "$WORK/ba.db" || exit 2   # B
  index_cell "$BASE_TREE" "$REPO_ROOT/$corpus_rel"  "$WORK/ab.db" || exit 2   # C
  index_cell "$REPO_ROOT" "$REPO_ROOT/$corpus_rel"  "$WORK/bb.db" || exit 2   # D

  # The byte-exact artifact CI will diff against, kept alongside the captured
  # value: a variable cannot represent a trailing newline, so the check that the
  # written file is correct cannot be made from "$D" alone.
  if [ "$metric" = golden ]; then
    GOLDEN_RAW="$WORK/golden.raw"
    sqlite3 "$WORK/bb.db" \
      "SELECT 'modules: ' || count(*) FROM modules; \
       SELECT 'functions: ' || count(*) FROM functions; \
       SELECT 'calls: ' || count(*) FROM calls;" > "$GOLDEN_RAW"
  fi

  A="$(metric_value "$metric" "$WORK/aa.db")"
  B="$(metric_value "$metric" "$WORK/ba.db")"
  C="$(metric_value "$metric" "$WORK/ab.db")"
  D="$(metric_value "$metric" "$WORK/bb.db")"
  PINNED="$(metric_pinned "$metric")"
  KIND="$(metric_kind "$metric")"

  echo
  echo "── $metric ($KIND, measured over $corpus_rel)"
  printf '   %-28s %s\n' "pinned in tree"        "$(echo "$PINNED" | tr '\n' ' ')"
  printf '   %-28s %s\n' "A base bin/base src"   "$(echo "$A" | tr '\n' ' ')"
  printf '   %-28s %s\n' "B  NEW bin/base src"   "$(echo "$B" | tr '\n' ' ')"
  printf '   %-28s %s\n' "C base bin/ NEW src"   "$(echo "$C" | tr '\n' ' ')"
  printf '   %-28s %s\n' "D  NEW bin/ NEW src"   "$(echo "$D" | tr '\n' ' ')"

  # The attribution. The movement is source-only when the two binaries agree on
  # BOTH corpora — then every difference between D and A is code that was added
  # or removed, and that is the only case a script may write.
  VERDICT="$(classify "$A" "$B" "$C" "$D")"
  BEHAVIOURAL=0
  [ "$VERDICT" != SOURCE_ONLY ] && BEHAVIOURAL=1

  # B = A alone is NOT sufficient, and getting this wrong was the first version
  # of this script. It says the producer is inert on the OLD corpus — a branch
  # that adds a producer change together with the code that change fires on
  # shows a perfectly clean B = A and still has a behavioural component in D.
  #
  # The general test is the other marginal: C and D differ only by which binary
  # read the NEW corpus. Comparing them needs no arithmetic, so unlike an
  # additive interaction term it works for a multi-line golden exactly as it
  # works for a scalar ratchet.
  if [ "$VERDICT" = BEHAVIOURAL ]; then
    echo "   → BEHAVIOURAL: the same corpus measures differently under the new binary."
    echo "     This branch changed what the analysis DOES. That may well be correct,"
    echo "     but it is a claim about the analysis and must be argued in review —"
    echo "     absorbing it into a constant is how a detector stops detecting."
  elif [ "$VERDICT" = INTERACTION ]; then
    echo "   → BEHAVIOURAL, and invisible in the B = A marginal: the two binaries"
    echo "     agree on the old corpus and disagree on the new one, so this branch"
    echo "     added a producer change together with the code it fires on."
  else
    echo "   → attributable to source change only (B = A)."
  fi

  # Currency is decided on the ARTIFACT, not on the captured value. For the
  # golden that distinction is the whole ballgame: command substitution strips
  # trailing newlines, so "$D" = "$PINNED" is true for two files that `diff`
  # — and therefore CI — call different. Comparing the strings is measuring a
  # projection of the thing the gate actually checks.
  CURRENT=0
  if [ "$metric" = golden ] && [ -n "${GOLDEN_RAW:-}" ]; then
    diff -q "$REPO_ROOT/test/fixtures/self-index-stats.txt" "$GOLDEN_RAW" >/dev/null 2>&1 && CURRENT=1
  else
    [ "$D" = "$PINNED" ] && CURRENT=1
  fi

  if [ "$CURRENT" = 1 ]; then
    echo "   ✓ pinned value is current."
    continue
  fi

  case "$MODE" in
    explain) STATUS=1 ;;
    check)
      echo "   ✗ STALE: pinned value is not what this tree measures."
      STATUS=1
      ;;
    write)
      if [ "$BEHAVIOURAL" = 1 ]; then
        echo "   ✗ REFUSED: movement is not attributable to source change alone."
        STATUS=1
      elif [ "$KIND" = ratchet ] && [ "$D" -gt "$PINNED" ] 2>/dev/null; then
        # The asymmetry. Raising a bound to meet the code is precisely the
        # failure this repository already suffered; it stays a human act.
        echo "   ✗ REFUSED: a ratchet may be tightened automatically, never loosened."
        echo "     $PINNED → $D would RAISE the bound. Record the +$(( D - PINNED )) and why."
        STATUS=1
      else
        case "$metric" in
          golden)
            # printf '%s\n', not '%s'. Command substitution strips trailing
            # newlines, so writing "$D" back verbatim silently produces a file
            # with no final newline — and CI compares it with `diff` against
            # raw `sqlite3` output, which has one. The counts were right and
            # the gate was red anyway, on one byte. Caught in review, not here,
            # which is why the write is now verified rather than trusted.
            printf '%s\n' "$D" > "$REPO_ROOT/test/fixtures/self-index-stats.txt"
            if [ -n "${GOLDEN_RAW:-}" ] && [ -f "$GOLDEN_RAW" ]; then
              if diff -q "$REPO_ROOT/test/fixtures/self-index-stats.txt" "$GOLDEN_RAW" >/dev/null
              then echo "   ✓ WROTE test/fixtures/self-index-stats.txt (byte-identical to a raw measurement)"
              else
                echo "   ✗ WROTE a file that does NOT match a raw measurement byte-for-byte:" >&2
                diff "$REPO_ROOT/test/fixtures/self-index-stats.txt" "$GOLDEN_RAW" >&2
                STATUS=1
              fi
            else
              echo "   ✓ WROTE test/fixtures/self-index-stats.txt"
            fi
            ;;
          ceiling)
            sed -i "s/^let clean_measured = [0-9]\+/let clean_measured = $D/" \
              "$REPO_ROOT/tezt/tests/must_null_ceiling.ml"
            echo "   ✓ TIGHTENED clean_measured $PINNED → $D"
            ;;
        esac
      fi
      ;;
  esac
done

echo
exit "$STATUS"
