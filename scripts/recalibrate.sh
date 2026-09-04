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
#   scripts/recalibrate.sh --explain        print the 2x2 and change nothing.
#                                           Exits 0 even when STALE, but 2 on a
#                                           DEGRADED or IMPLAUSIBLE measurement:
#                                           a measurement that did not happen is
#                                           not a verdict, in any mode. Use
#                                           --check for the enforced stale code.
#   scripts/recalibrate.sh --self-test      exercise classify()/is_int() only;
#                                           instant, needs no build or repo state
#
#   --base <ref>     baseline to attribute against (default: merge-base(HEAD,
#                    origin/main); an EXPLICIT --base is taken literally, not
#                    reinterpreted as a merge-base — see the --base handling
#                    below for why the default and the explicit case differ)
#   --only <metric>  golden | ceiling
#
# Exit: 0 ok / 1 stale or refused / 2 degraded (cannot measure)
#       (--explain is the one mode that does not use this table: see above)

# pipefail is load-bearing, not hygiene. Without it `dune build … | tail` exits
# with tail's status, which is always 0 — so every `|| { build failed; exit 2; }`
# below was dead code, and a tree that FAILED to compile was measured using the
# previous build's producer. That is exactly the stale-artifact trap this script
# warns about, committed by the script. Found in review.
set -u
set -o pipefail

MODE=""
BASE_REF="origin/main"
BASE_EXPLICIT=0
ONLY=""

while [ $# -gt 0 ]; do
  case "$1" in
    --check|--write|--explain|--self-test)
      if [ -n "$MODE" ] && [ "$MODE" != "${1#--}" ]; then
        echo "recalibrate: --$MODE and $1 are mutually exclusive" >&2; exit 2
      fi
      MODE="${1#--}" ;;
    --base)
      shift
      # --only's sibling hole was closed in round 5; this one was not.
      [ $# -gt 0 ] || { echo "recalibrate: --base requires a ref" >&2; exit 2; }
      BASE_REF="$1"; BASE_EXPLICIT=1 ;;
    --only)
      shift
      # A missing value yielded "" and was accepted by the both-metrics arm,
      # so `--check --only` silently ran everything. `--only bogus` fails
      # fast; a missing value must too.
      [ $# -gt 0 ] || { echo "recalibrate: --only requires a value (golden|ceiling)" >&2; exit 2; }
      ONLY="$1"
      # Validated here, not after the two pristine builds below: a typo costs
      # nothing at the top of the arg loop and minutes once past it. Found in
      # review — `--only bogus` used to run to completion before rejecting.
      case "$ONLY" in
        golden|ceiling) ;;
        *) echo "recalibrate: --only takes 'golden' or 'ceiling', got '$ONLY'" >&2; exit 2 ;;
      esac
      ;;
    -h|--help) sed -n '2,/^# Exit:/p' "$0" | sed 's/^# \?//'; exit 0 ;;
    *) echo "recalibrate: unknown argument: $1" >&2; exit 2 ;;
  esac
  shift
done

if [ -z "$MODE" ]; then
  echo "recalibrate: one of --check / --write / --explain / --self-test is required" >&2
  exit 2
fi

# ---------------------------------------------------------------------------
# pure logic — everything --self-test can drive without a build or a repository
# ---------------------------------------------------------------------------
# Round 6 mutation-tested the shipped script and SEVEN mutants survived, every
# one of them outside this section as it then stood: the write-verification read
# (the entire subject of the previous commit), the PINNED integrity gate added
# the commit before that, the headroom gate, the golden PINNED gate, the ratchet
# loosening guard, bump_status's degraded arm, and the degraded-cell loop. The
# untested region was precisely the region every shipped defect has lived in.
#
# So the decisions were pulled OUT of the measuring loop and into named
# functions above the --self-test dispatch. Nothing here touches the network,
# the build, sqlite3, or $REPO_ROOT; every file any of it reads is passed in as
# an argument, so --self-test drives all of it against temp fixtures.

# A measured or pinned value is only comparable as a number if it IS one — and
# "is a number" must mean "a number $(( )) evaluates the way a reader reads it",
# not "a string of digits". `08` passed the old digits-only test and then made
# the arithmetic comparison ABORT: bash reads a leading zero as octal, so
# `$(( 08 + 25 ))` fails with "value too great for base", the whole if/elif/else
# is skipped, NO arm runs, and CURRENT silently keeps whatever it held before.
# §10.6's shape exactly — the guard's accepted set was wider than its consumer's
# — and the self-test asserted the wrong half of it, pinning `00` as a pass.
is_int() {
  case "${1:-}" in
    0) return 0 ;;
    ''|*[!0-9]*|0*) return 1 ;;
    *) return 0 ;;
  esac
}

# ONE reader for every `let <name> = <int>` this tool reads out of OCaml source.
# The file had three spellings of this read and two were anchored; the third was
# not, and it was the one whose value enters the arithmetic.
#
# Anchoring is not cosmetic. `let headroom = 1_000` is legal OCaml meaning 1000;
# an unanchored `\([0-9]\+\).*` reads it as **1**, is_int accepts 1, and the band
# silently narrows from +/-1000 to +/-1 with no refusal and no diagnostic.
# Measured on the shipped script: pin 400 with `headroom = 1_000` made
# `--write --only ceiling` rewrite 400 -> 340 and report success, when 340 is
# inside the real band and nothing should have been written at all.
#
# And a read that matches TWICE is a defect, not something to take the first of:
# the old `| head -1` silently picked one of two contradictory definitions.
# Multi-match returns failure here, which the degradedness gate reports as an
# unreadable pin rather than resolving it by guess.
#   status 0  a single readable definition, echoed
#   status 1  no definition this reader accepts
#   status 2  defined more than once — a contradiction, not a choice
#
# The two statuses are distinct DELIBERATELY, and the story is worth recording
# because it is this review's own recurring finding, committed while fixing it.
# The first version of this function ended:
#
#     [ "$n" -eq 1 ] || return 1
#     is_int "$out" || return 1
#
# and the multi-match conjunct was DEAD: two matches make $out a two-LINE
# string, `is_int` rejects it for containing a newline, and `[ "$n" -eq 1 ]`
# therefore decided nothing on its own. Mutation-testing this file caught it —
# widening `-eq 1` to `-ge 1` left --self-test fully green. That is MEDIUM-2's
# finding exactly: a conjunct kept for comfort behind a justification that does
# not hold. It is not deleted but made LIVE, because "defined twice" and
# "unreadable" are different defects with different fixes and the caller says so
# in its diagnostic; --self-test pins both status codes.
read_pinned_int() {
  local file="$1" name="$2" out n
  out="$(sed -n "s/^let $name = \([0-9]\+\)[[:space:]]*\$/\1/p" "$file" 2>/dev/null)"
  n="$(printf '%s\n' "$out" | grep -c '[^[:space:]]')"
  [ "$n" -le 1 ] || return 2
  is_int "$out" || return 1
  printf '%s\n' "$out"
}

# A cell is well-formed for a metric when it is USABLE as that metric's value,
# not merely non-empty-as-a-string. is_int alone would do for the ratchet, but
# the golden is multi-line free text — "is an integer" is the wrong question
# for it, and reusing is_int there would refuse every legitimate golden cell.
# "well-formed" instead means: non-empty, and (for the golden) none of its
# "label: value" lines has an empty value — the shape q() produces when the
# underlying query returned nothing (e.g. a renamed column) instead of erroring
# loudly. Applied to every one of A/B/C/D, before classify() and before the
# currency comparison, in every mode: a degraded cell must never reach either.
#
# WELL-FORMED IS NOT ADEQUATE. This answers "could this be a value?", never "is
# this a measurement?" — `0` is a perfectly well-formed ceiling. The adequacy
# and plausibility gates below answer the second question, and they exist
# because this one was being read as though it already did.
metric_well_formed() {
  local metric="$1" val="$2"
  # No separate non-empty guard: it is dead. `is_int ""` already returns 1, an
  # empty golden yields 0 matching lines against a required 3, and an unknown
  # metric falls to the catch-all. Round 5 found it as a surviving mutant —
  # removing it changed nothing — and for THIS line that reasoning is sound;
  # round 6 re-derived it independently. (For its sibling one arm down, it was
  # not: see the correction there.)
  case "$metric" in
    ceiling) is_int "$val" ;;
    golden)
      # Arity is the whole check.
      #
      # CORRECTION, round 6. The comment that stood here claimed round 4's
      # trailing-label conjunct had been DEAD, citing round 5's surviving mutant
      # as the evidence. Review disproved it by running the round-4 code both
      # ways on `modules: 23 / functions: 781 / calls: 5068 / extra:`
      # (lines=3, total=4): conjunct PRESENT rejects, conjunct DELETED accepts.
      # The conjunct was LIVE. Deleting it is still correct, because the
      # `[ "$total" -eq 3 ]` added in the same edit strictly dominates it — but
      # the recorded reason was false, and it inverted round 5's own lesson: a
      # surviving mutant means the TEST did not cover the line, never that the
      # line is dead. Corrected in place rather than quietly dropped, because a
      # false justification in a comment is §10.3's failure mode exactly — it is
      # read as evidence by people who cannot re-run it.
      #
      # The regex is anchored and lower-case-only ON PURPOSE: CI compares
      # exactly the three lines `modules:`/`functions:`/`calls:` that
      # sqlite3 emits, so anything else is a measurement this tool must not
      # install. Each of those properties has a self-test case below.
      local lines total
      lines="$(printf '%s\n' "$val" | grep -cE '^[a-z]+: *[0-9]+$')"
      total="$(printf '%s\n' "$val" | grep -c '[^[:space:]]')"
      [ "$lines" -eq 3 ] && [ "$total" -eq 3 ]
      ;;
    *) return 1 ;;
  esac
}

classify() {
  local a="$1" b="$2" c="$3" d="$4"
  # All four cells empty is not "the binaries and corpora all agree" — it is
  # every measurement having produced nothing (schema failure, missing
  # producer, a query that silently returned ""). Reported as SOURCE_ONLY that
  # used to let a check/write proceed on a table with no actual measurement in
  # it: "" = "" on all four marginals. A single cell being empty is still
  # informative (something differs from something else) and is left to
  # BEHAVIOURAL/INTERACTION below; only total failure is special-cased here.
  #
  # This arm only ever caught the EMPTY degeneracy. The far commoner one is
  # A=B=C=D=0, which is not empty, is not caught here, and is the cleanest
  # possible SOURCE_ONLY — see plausibility_failures below for that one.
  if [ -z "$a" ] && [ -z "$b" ] && [ -z "$c" ] && [ -z "$d" ]; then echo DEGRADED
  elif [ "$a" != "$b" ]; then echo BEHAVIOURAL
  elif [ "$c" != "$d" ]; then echo INTERACTION
  else echo SOURCE_ONLY
  fi
}

# ---------------------------------------------------------------------------
# adequacy — the gate between a degenerate-but-integer number and a write
# ---------------------------------------------------------------------------
# THE HOLE THIS CLOSES. A query that succeeds but matches nothing returns `0`,
# not an error. sqlite3 prints nothing on stderr, so QERR stays empty and the
# degraded arm never fires; `0` is an integer, so metric_well_formed accepts it;
# and A=B=C=D=0 is the cleanest possible SOURCE_ONLY attribution. Reproduced in
# review by editing the ceiling predicate to simulate a column rename that still
# returns a number — the shape this file's own comment calls frequent here:
#
#     -  AND callee_name NOT LIKE 'Stdlib.%'
#     +  AND callee_name LIKE 'ZzzNoSuchModule.%'
#     => A=B=C=D=0, "attributable to source change only",
#        "TIGHTENED clean_measured 347 -> 0 (installed file re-read and
#        confirmed)", exit 0.
#
# The same hole on the golden left the CHANGE DETECTOR reading
# `modules: 0 / functions: 0 / calls: 0`, "installed file verified
# byte-identical", exit 0.
#
# AND THIS IS WHY "A TIGHTEN IS ALWAYS SAFE" IS FALSE. That axiom is about
# DIRECTION and says nothing about MAGNITUDE — but every way a measurement can
# silently break (a renamed column, a renamed table, a predicate that stops
# matching, an under-built corpus) moves the number DOWN, into the direction the
# axiom calls always-safe. So a broken run and a spectacular win have the same
# shape, only magnitude separates them, and the axiom routes the broken one
# straight to a write. A tighten is safe for the INVARIANT and destructive for
# the CONSTANT: `clean_measured = 0` cannot fail CI, and it also cannot ever
# catch anything again.
#
# Two independent floors, because they catch different things and neither
# subsumes the other:
#
#   relative  every component must be at least 1/PLAUSIBILITY_DEN of what is
#             pinned. Needs no invented constant and cannot go stale. Catches
#             the degeneracies above, where the corpus is fine and the QUERY is
#             broken.
#   absolute  the corpus itself must contain enough to have been measured at
#             all. Catches the shape the relative floor cannot — an under-built
#             tree, where nothing was there to count. Mirrored from
#             must_null_ceiling.ml's own [min_total_calls] rather than invented
#             here; see the read of it in the loop below.
#
# Neither is a judgement that a large drop is WRONG. It is a judgement that a
# large drop is not a SCRIPT'S to absorb: --write refuses and prints the table,
# and a human recalibrates by hand with a recorded reason — the same contract
# the BEHAVIOURAL arm has always had.
PLAUSIBILITY_DEN=2

# Echoes one line per implausible component; empty output means plausible.
# Components are matched by LABEL, not by line order: pairing the golden's three
# lines positionally would silently compare modules against functions the day a
# line is added or reordered.
plausibility_failures() {
  local metric="$1" measured="$2" pinned="$3"
  case "$metric" in
    ceiling)
      if ! is_int "$measured" || ! is_int "$pinned"; then
        echo "ceiling: unreadable (measured='$measured' pinned='$pinned')"
        return 0
      fi
      if [ "$(( measured * PLAUSIBILITY_DEN ))" -lt "$pinned" ]; then
        echo "ceiling: measured $measured is below 1/$PLAUSIBILITY_DEN of pinned $pinned"
      fi
      ;;
    golden)
      local line label val pin
      while IFS= read -r line; do
        [ -n "$line" ] || continue
        label="${line%%:*}"
        val="${line##*: }"
        pin="$(printf '%s\n' "$pinned" | sed -n "s/^$label: *\([0-9]\+\)[[:space:]]*\$/\1/p")"
        if ! is_int "$val" || ! is_int "$pin"; then
          echo "$label: unreadable (measured='$val' pinned='$pin')"
          continue
        fi
        if [ "$(( val * PLAUSIBILITY_DEN ))" -lt "$pin" ]; then
          echo "$label: measured $val is below 1/$PLAUSIBILITY_DEN of pinned $pin"
        fi
      done <<PLAUS
$measured
PLAUS
      ;;
    *) echo "unknown metric '$metric'" ;;
  esac
  return 0
}

# ---------------------------------------------------------------------------
# the per-cell gates, as functions rather than inline loops
# ---------------------------------------------------------------------------
# All four cells, not just D. Every one of them feeds classify(), and four
# degenerate cells are the cleanest possible SOURCE_ONLY — gating D alone would
# leave the attribution itself computed from nothing.
cells_degraded() {  # metric A B C D -> " A B" style label list, empty if all ok
  local metric="$1"; shift
  local label out=""
  for label in A B C D; do
    metric_well_formed "$metric" "${1:-}" || out="$out $label"
    shift
  done
  printf '%s' "$out"
}

cells_implausible() {  # metric PINNED A B C D -> label list, empty if all ok
  local metric="$1" pinned="$2"; shift 2
  local label out=""
  for label in A B C D; do
    [ -z "$(plausibility_failures "$metric" "${1:-}" "$pinned")" ] || out="$out $label"
    shift
  done
  printf '%s' "$out"
}

# PINNED too, and for a ratchet it must be an INTEGER, because the headroom
# band does arithmetic on it. Round 4 added `is_int "$hr"` for the value it
# introduced and not for the value it started computing with two lines later
# — and bash coerces an empty operand to 0 inside $(( )), so `--check`
# printed "pinned value is current" and exited 0 having read no pinned value.
pinned_degraded() {  # kind pinned -> " PINNED" or ""
  local kind="$1" pinned="$2"
  if [ "$kind" = ratchet ]; then
    is_int "$pinned" || { printf ' PINNED'; return 0; }
  else
    [ -n "$pinned" ] || { printf ' PINNED'; return 0; }
  fi
  printf ''
}

# ---------------------------------------------------------------------------
# the ratchet band and the ratchet write, as pure decisions
# ---------------------------------------------------------------------------
# Currency for a ratchet is the ENFORCED predicate, not exact equality.
# tezt/tests/must_null_ceiling.ml asserts `must_null <= clean_measured +
# headroom`, and headroom exists (its own comment) to "absorb ordinary future
# growth without demanding a recalibration commit for every unrelated PR".
# Testing D = PINNED converted that into an exact-equality gate and reinstated
# the treadmill this tool exists to end. Round 4 found it.
#
#   D > PINNED + headroom  -> BREACH;  must be argued, never auto-written
#   D < PINNED - headroom  -> GAIN;    candidate for an automatic tighten
#   otherwise              -> CURRENT; inside the band, advisory, exit 0
band_verdict() {  # D PINNED HR -> CURRENT | BREACH | GAIN | ERR
  local d="$1" p="$2" hr="$3"
  if ! is_int "$d" || ! is_int "$p" || ! is_int "$hr"; then echo ERR; return 0; fi
  if   [ "$d" -gt "$(( p + hr ))" ]; then echo BREACH
  elif [ "$d" -lt "$(( p - hr ))" ]; then echo GAIN
  else echo CURRENT
  fi
}

# The asymmetry. Raising a bound to meet the code is precisely the failure this
# repository already suffered; it stays a human act.
ratchet_write_verdict() {  # D PINNED -> WRITE | REFUSE_LOOSEN | REFUSE_D | REFUSE_PINNED
  local d="$1" p="$2"
  if ! is_int "$d"; then echo REFUSE_D; return 0; fi
  if ! is_int "$p"; then echo REFUSE_PINNED; return 0; fi
  if [ "$d" -gt "$p" ]; then echo REFUSE_LOOSEN; return 0; fi
  echo WRITE
}

# Edit a COPY, verify the copy with an anchored read, and echo what the copy
# reads back. The caller installs it only on a match, so a refusal leaves the
# tracked file untouched rather than merely "reported as wrong".
#
# BOTH sides of the sed are anchored. Unanchored on the right,
# `let clean_measured = 1_000` became `let clean_measured = 340_000` — the
# read-back then refused, so the tracked file survived, but the scratch file was
# silently corrupt and the refusal named the wrong cause. Anchored, that line is
# not matched at all and the read-back reports exactly that.
ceiling_write_to() {  # src scratch value -> echoes the value the scratch reads back
  local src="$1" scratch="$2" val="$3"
  cp "$src" "$scratch" || return 2
  sed -i "s/^let clean_measured = [0-9]\+[[:space:]]*\$/let clean_measured = $val/" "$scratch" || return 2
  read_pinned_int "$scratch" clean_measured
}

# ---------------------------------------------------------------------------
# exit status
# ---------------------------------------------------------------------------
STATUS=0
# Monotonic: once degraded (2), stays degraded regardless of what a LATER
# metric in this same run reports, and a stale/refused (1) never falls back to
# ok (0). Without this, a --check running both metrics could see golden come
# back degraded (2) and ceiling merely stale (1) — direct assignment would
# leave the final exit code at 1, understating the more severe failure.
# Defined above the --self-test dispatch so the self-test can drive it: a mutant
# deleting the `*:2` arm survived round 6 because nothing did.
bump_status() {
  case "$STATUS:$1" in
    2:*) ;;
    *:2) STATUS=2 ;;
    0:1) STATUS=1 ;;
  esac
}

self_test() {
  local fails=0 got
  # Delimiter is '#', not ':'. A golden cell contains ": " ("modules: 23"), so an
  # IFS=':' parser silently misparses any golden row a contributor adds — which
  # is why the multi-line case below had to be hand-rolled instead of living in
  # this table.
  #
  # SCOPE. This used to exercise classify(), metric_well_formed() and is_int()
  # and nothing else, and it said so honestly. That honesty was not a fix:
  # round 6 applied 17 mutants to the shipped script, killed all nine that lay
  # inside those three functions, and watched SEVEN survive — every fix from
  # rounds 2 through 5, including the write-verification read that was the whole
  # subject of the last commit. With that mutant applied, this self-test still
  # printed "all cases pass" AND round 5's CRITICAL-1 reproduced verbatim.
  #
  # So the decisions moved into pure functions above and the cases below drive
  # them against temp fixtures. Each block names the mutant it exists to kill;
  # every one was applied and observed to turn this self-test RED, rather than
  # assumed to be covered. What is still NOT covered here is the measuring half
  # — the builds, the four index_cell runs, the sqlite3 queries — which needs a
  # repository and is exercised by --check in CI.
  chk() {  # want got label
    if [ "$1" = "$2" ]; then printf '  ok   %-34s %s\n' "$3" "$2"
    else printf '  FAIL %-34s want %-14s got %s\n' "$3" "$1" "$2"; fails=$(( fails + 1 )); fi
  }

  local cases="
SOURCE_ONLY#340#340#340#340
SOURCE_ONLY#761#761#780#780
BEHAVIOURAL#340#339#340#339
BEHAVIOURAL#340#339#340#340
INTERACTION#340#340#340#339
INTERACTION#340#340#355#340
BEHAVIOURAL#340##340#340
INTERACTION#340#340##340
DEGRADED####
"
  local a b c d want
  while IFS='#' read -r want a b c d; do
    [ -z "${want:-}" ] && continue
    got="$(classify "$a" "$b" "$c" "$d")"
    if [ "$got" = "$want" ]; then
      printf '  ok   %-12s A=%-4s B=%-4s C=%-4s D=%-4s\n' "$got" "${a:-<empty>}" "${b:-<empty>}" "${c:-<empty>}" "${d:-<empty>}"
    else
      printf '  FAIL want %-12s got %-12s A=%s B=%s C=%s D=%s\n' "$want" "$got" "$a" "$b" "$c" "$d"
      fails=$(( fails + 1 ))
    fi
  done <<EOF
$cases
EOF
  # A multi-line golden must classify exactly like a scalar: the check is string
  # inequality precisely so it does not need the values to be numbers.
  got="$(classify "m: 23
f: 761" "m: 23
f: 761" "m: 23
f: 780" "m: 23
f: 780")"
  if [ "$got" = SOURCE_ONLY ]; then echo "  ok   SOURCE_ONLY  multi-line golden"
  else echo "  FAIL multi-line golden classified $got"; fails=$(( fails + 1 )); fi

  # metric_well_formed is the guard between a silently-failed query and a
  # written constant. It had NO coverage: stubbing it to `return 0` left this
  # self-test reporting "all cases pass". That is the arm round 2's CRITICAL
  # lived in, so it is the last place that should have been untested.
  #
  # `0` is asserted to be ACCEPTED here, deliberately and with its own reason:
  # well-formedness answers "could this be a ceiling value?", and 0 could. What
  # 0 must not do is reach a WRITE, and the round-6 finding was that nothing
  # else stopped it. That is now the plausibility block further down, and the
  # two assertions are complementary rather than in tension.
  local m
  for m in "340" "0"; do
    if metric_well_formed ceiling "$m"; then echo "  ok   well_formed ceiling '$m'"
    else echo "  FAIL well_formed REJECTED ceiling '$m'"; fails=$(( fails + 1 )); fi
  done
  for m in "" " " "34a" "3.4"; do
    if metric_well_formed ceiling "$m"; then
      echo "  FAIL well_formed ACCEPTED ceiling '$m' — this is the degraded path"; fails=$(( fails + 1 ))
    else echo "  ok   well_formed rej ceiling '$m'"; fi
  done
  local good_golden="modules: 23
functions: 781
calls: 5068"
  if metric_well_formed golden "$good_golden"; then echo "  ok   well_formed golden (full triple)"
  else echo "  FAIL well_formed REJECTED a valid golden"; fails=$(( fails + 1 )); fi
  for m in "" "modules: 23
functions:
calls: 5068" "modules: 23"; do
    if metric_well_formed golden "$m"; then
      echo "  FAIL well_formed ACCEPTED a degraded golden"; fails=$(( fails + 1 ))
    else echo "  ok   well_formed rej golden (degraded)"; fi
  done

  # These five cases exist because round 5 mutation-tested metric_well_formed
  # and five mutants SURVIVED: dropping the non-empty guard, accepting an
  # unknown metric, widening [a-z] to [a-zA-Z], dropping the ^…$ anchors, and
  # deleting round 4's trailing-label conjunct. §10.6 names this function as an
  # instance; an unkilled mutant in it is the finding.
  if metric_well_formed bogus "340"; then
    echo "  FAIL well_formed ACCEPTED an unknown metric"; fails=$(( fails + 1 ))
  else echo "  ok   well_formed rej unknown metric"; fi
  local g_upper="Modules: 23
functions: 781
calls: 5068"
  if metric_well_formed golden "$g_upper"; then
    echo "  FAIL well_formed ACCEPTED a capitalised golden label"; fails=$(( fails + 1 ))
  else echo "  ok   well_formed rej capitalised label"; fi
  local g_unanchored=" modules: 23
functions: 781
calls: 5068"
  if metric_well_formed golden "$g_unanchored"; then
    echo "  FAIL well_formed ACCEPTED a leading-space golden line"; fails=$(( fails + 1 ))
  else echo "  ok   well_formed rej unanchored line"; fi
  local g_extra="modules: 23
functions: 781
calls: 5068
types: 9"
  if metric_well_formed golden "$g_extra"; then
    echo "  FAIL well_formed ACCEPTED a FOURTH golden line"; fails=$(( fails + 1 ))
  else echo "  ok   well_formed rej extra line"; fi
  local g_junk="modules: 23
functions: 781
calls: 5068
oops"
  if metric_well_formed golden "$g_junk"; then
    echo "  FAIL well_formed ACCEPTED trailing junk"; fails=$(( fails + 1 ))
  else echo "  ok   well_formed rej trailing junk"; fi
  # The exact input round 6 used to disprove the "the conjunct was dead" claim:
  # lines=3 (the trailing `extra:` has no value, so it does not match), total=4.
  # Pinned here so the correction cannot rot back into the old story.
  local g_trailing_label="modules: 23
functions: 781
calls: 5068
extra:"
  if metric_well_formed golden "$g_trailing_label"; then
    echo "  FAIL well_formed ACCEPTED a trailing valueless label"; fails=$(( fails + 1 ))
  else echo "  ok   well_formed rej trailing valueless label"; fi

  # is_int guards the ratchet write. An empty or non-numeric value reaching the
  # comparison is what made that guard fail OPEN and emit an uncompilable file.
  local v
  for v in 0 340 1 12980; do
    if is_int "$v"; then echo "  ok   is_int      '$v'"
    else echo "  FAIL is_int rejected '$v'"; fails=$(( fails + 1 )); fi
  done
  # `08` and `00` are the MEDIUM-3 cases and they used to be asserted the wrong
  # way round: `00` was pinned as a PASS. A leading zero is octal to $(( )), so
  # `[ "$D" -gt "$(( PINNED + hr ))" ]` aborts with "value too great for base",
  # every arm of the if/elif/else is skipped, and CURRENT keeps its prior value
  # while a bash error goes to stderr. The guard was wider than its consumer.
  for v in "" " " "34a" "-1" "3.4" "321 " "let clean_measured" "08" "00" "0x200" "1_000"; do
    if is_int "$v"; then echo "  FAIL is_int ACCEPTED '$v' — this is the fail-open path"; fails=$(( fails + 1 ))
    else echo "  ok   is_int rej  '$v'"; fi
  done

  # -------------------------------------------------------------------------
  # temp fixtures — the file-reading and file-writing halves
  # -------------------------------------------------------------------------
  local FX; FX="$(mktemp -d "${TMPDIR:-/tmp}/recal-selftest.XXXXXX")" || {
    echo "self-test: cannot create a temp dir"; return 1; }
  printf 'let clean_measured = 347\n\nlet headroom = 25\n\nlet min_total_calls = 8000\n' > "$FX/ok.ml"
  # `1_000` is legal OCaml meaning 1000. This is HIGH-1's fixture.
  printf 'let clean_measured = 1_000\n\nlet headroom = 1_000\n' > "$FX/underscore.ml"
  printf 'let clean_measured = 347\nlet clean_measured = 340\n' > "$FX/duplicate.ml"
  printf 'let clean_measured : int = 347\n' > "$FX/annotated.ml"

  # --- read_pinned_int: HIGH-1, and mutant M14 (the headroom gate) ----------
  chk 347 "$(read_pinned_int "$FX/ok.ml" clean_measured || echo REFUSED)" "read_pinned_int clean_measured"
  chk 25  "$(read_pinned_int "$FX/ok.ml" headroom       || echo REFUSED)" "read_pinned_int headroom"
  chk 8000 "$(read_pinned_int "$FX/ok.ml" min_total_calls || echo REFUSED)" "read_pinned_int min_total_calls"
  # The whole of HIGH-1 in one assertion: unanchored, this returns 1 and the
  # band silently becomes +/-1. It must REFUSE, not truncate.
  chk REFUSED "$(read_pinned_int "$FX/underscore.ml" headroom       || echo REFUSED)" "headroom 1_000 refused"
  chk REFUSED "$(read_pinned_int "$FX/underscore.ml" clean_measured || echo REFUSED)" "clean_measured 1_000 refused"
  # A read that matches twice is a defect, not a first-match. `| head -1` used
  # to pick one of two contradictory definitions silently.
  chk REFUSED "$(read_pinned_int "$FX/duplicate.ml" clean_measured || echo REFUSED)" "duplicate definition refused"
  chk REFUSED "$(read_pinned_int "$FX/annotated.ml" clean_measured || echo REFUSED)" "type-annotated pin refused"
  chk REFUSED "$(read_pinned_int "$FX/ok.ml" no_such_constant      || echo REFUSED)" "absent constant refused"
  # The STATUS, not just the value. Without these the multi-match conjunct is
  # dead — `is_int` already rejects a two-line result — and widening it to
  # `-ge 1` left the whole self-test green. "Defined twice" and "unreadable"
  # are different defects and the caller reports them differently.
  local rc
  read_pinned_int "$FX/ok.ml"         clean_measured >/dev/null 2>&1; rc=$?
  chk 0 "$rc" "status: readable pin"
  read_pinned_int "$FX/annotated.ml"  clean_measured >/dev/null 2>&1; rc=$?
  chk 1 "$rc" "status: unreadable pin"
  read_pinned_int "$FX/underscore.ml" headroom       >/dev/null 2>&1; rc=$?
  chk 1 "$rc" "status: 1_000 headroom unreadable"
  read_pinned_int "$FX/duplicate.ml"  clean_measured >/dev/null 2>&1; rc=$?
  chk 2 "$rc" "status: defined more than once"

  # --- ceiling_write_to: mutant M12, the subject of the last commit ---------
  chk 340 "$(ceiling_write_to "$FX/ok.ml" "$FX/w1.ml" 340 || echo REFUSED)" "write-verify reads back 340"
  chk "let clean_measured = 340" "$(grep '^let clean_measured' "$FX/w1.ml")" "write-verify installed line"
  # Re-unanchor the read (M12) and this pair goes red: the sed leaves
  # `340_000` and an unanchored read reports a confident `340`.
  chk REFUSED "$(ceiling_write_to "$FX/underscore.ml" "$FX/w2.ml" 340 || echo REFUSED)" "write-verify refuses 1_000 pin"
  chk "let clean_measured = 1_000" "$(grep '^let clean_measured' "$FX/w2.ml")" "refused write left the copy intact"
  chk REFUSED "$(ceiling_write_to "$FX/annotated.ml" "$FX/w3.ml" 340 || echo REFUSED)" "write-verify refuses annotated pin"
  rm -rf "$FX"

  # --- band_verdict: mutant M14, and round 4's headroom regression ----------
  chk CURRENT "$(band_verdict 340 347 25)"   "band 340 in 347+/-25"
  chk CURRENT "$(band_verdict 372 347 25)"   "band at the upper edge"
  chk CURRENT "$(band_verdict 322 347 25)"   "band at the lower edge"
  chk BREACH  "$(band_verdict 373 347 25)"   "band one past the ceiling"
  chk GAIN    "$(band_verdict 321 347 25)"   "band one below the floor"
  # HIGH-1's measured consequence, as a decision: with headroom truly 1000, 340
  # against a pin of 321 is CURRENT. Read as 1 (unanchored) it is a BREACH, and
  # the shipped script exited 1 "STALE" on exactly this input.
  chk CURRENT "$(band_verdict 340 321 1000)" "band 340 in 321+/-1000"
  chk BREACH  "$(band_verdict 340 321 1)"    "band 340 in 321+/-1 (the misread)"
  chk ERR     "$(band_verdict 340 321 '')"   "band refuses empty headroom"
  chk ERR     "$(band_verdict 340 '' 25)"    "band refuses empty pin"
  chk ERR     "$(band_verdict '' 321 25)"    "band refuses empty measurement"
  # MEDIUM-3: `08` must not reach $(( )). Before, this aborted the comparison.
  chk ERR     "$(band_verdict 340 08 25)"    "band refuses octal-looking pin"

  # --- ratchet_write_verdict: mutant M16, the loosening guard ---------------
  chk REFUSE_LOOSEN  "$(ratchet_write_verdict 400 347)" "ratchet refuses a raise"
  chk REFUSE_LOOSEN  "$(ratchet_write_verdict 348 347)" "ratchet refuses a raise by one"
  chk WRITE          "$(ratchet_write_verdict 347 347)" "ratchet allows equal"
  chk WRITE          "$(ratchet_write_verdict 300 347)" "ratchet allows a tighten"
  chk REFUSE_D       "$(ratchet_write_verdict ''  347)" "ratchet refuses empty measurement"
  chk REFUSE_PINNED  "$(ratchet_write_verdict 300 '')"  "ratchet refuses empty pin"

  # --- pinned_degraded: mutants M13 (ratchet) and M15 (golden) --------------
  # M13 deletes the ratchet arm; round 5's CRITICAL-1 then reproduces verbatim
  # — "pinned value is current", exit 0, empty pinned value.
  chk " PINNED" "$(pinned_degraded ratchet '')"      "ratchet pin empty is degraded"
  chk " PINNED" "$(pinned_degraded ratchet 'abc')"   "ratchet pin non-numeric is degraded"
  chk " PINNED" "$(pinned_degraded ratchet '1_000')" "ratchet pin 1_000 is degraded"
  chk ""        "$(pinned_degraded ratchet '347')"   "ratchet pin 347 is fine"
  chk " PINNED" "$(pinned_degraded descriptive '')"  "golden pin empty is degraded"
  chk ""        "$(pinned_degraded descriptive 'modules: 23')" "golden pin non-empty is fine"

  # --- cells_degraded: mutant M17, the loop that marks nothing --------------
  chk ""      "$(cells_degraded ceiling 340 340 340 340)" "four good ceiling cells"
  chk " B"    "$(cells_degraded ceiling 340 '' 340 340)"  "one empty ceiling cell"
  chk " A B C D" "$(cells_degraded ceiling '' '' '' '')"  "four empty ceiling cells"
  chk " C"    "$(cells_degraded ceiling 340 340 x 340)"   "one non-numeric ceiling cell"
  chk ""      "$(cells_degraded golden "$good_golden" "$good_golden" "$good_golden" "$good_golden")" \
              "four good golden cells"
  chk " D"    "$(cells_degraded golden "$good_golden" "$good_golden" "$good_golden" "modules: 23")" \
              "one truncated golden cell"

  # --- plausibility_failures / cells_implausible: CRITICAL-1 ---------------
  # The reviewer's reproduction, as a decision. A ceiling predicate that stops
  # matching returns 0 from a healthy database: well-formed, integer, and the
  # cleanest possible SOURCE_ONLY. Only magnitude separates it from a win.
  local pf
  pf="$(plausibility_failures ceiling 340 347)"; chk "" "$pf" "ceiling 340 vs pin 347 plausible"
  pf="$(plausibility_failures ceiling 174 347)"; chk "" "$pf" "ceiling 174 vs pin 347 plausible (edge)"
  pf="$(plausibility_failures ceiling 173 347)"; [ -n "$pf" ] \
    && echo "  ok   ceiling 173 vs pin 347 implausible" \
    || { echo "  FAIL ceiling 173 vs pin 347 accepted"; fails=$(( fails + 1 )); }
  pf="$(plausibility_failures ceiling 0 347)"; [ -n "$pf" ] \
    && echo "  ok   ceiling 0 vs pin 347 implausible   <- CRITICAL-1" \
    || { echo "  FAIL ceiling 0 vs pin 347 ACCEPTED — CRITICAL-1 is open"; fails=$(( fails + 1 )); }
  # A rise is always plausible: the floor is one-sided. Raising is refused by
  # ratchet_write_verdict, not by this.
  pf="$(plausibility_failures ceiling 900 347)"; chk "" "$pf" "ceiling 900 vs pin 347 plausible"
  local pinned_golden="modules: 23
functions: 804
calls: 5170"
  pf="$(plausibility_failures golden "$pinned_golden" "$pinned_golden")"
  chk "" "$pf" "golden identical to pin is plausible"
  local zero_golden="modules: 0
functions: 0
calls: 0"
  pf="$(plausibility_failures golden "$zero_golden" "$pinned_golden")"
  [ "$(printf '%s\n' "$pf" | grep -c .)" -eq 3 ] \
    && echo "  ok   golden 0/0/0 implausible on all 3   <- CRITICAL-1" \
    || { echo "  FAIL golden 0/0/0 not caught on all three — CRITICAL-1 is open"; fails=$(( fails + 1 )); }
  # Partial degeneracy: one table renamed, the other two fine. Positional
  # pairing would still line up here; label pairing is what catches a reorder.
  local part_golden="modules: 23
functions: 0
calls: 5170"
  pf="$(plausibility_failures golden "$part_golden" "$pinned_golden")"
  [ "$(printf '%s\n' "$pf" | grep -c .)" -eq 1 ] \
    && echo "  ok   golden one degenerate component caught" \
    || { echo "  FAIL golden partial degeneracy not caught"; fails=$(( fails + 1 )); }
  local reordered="calls: 5170
modules: 23
functions: 804"
  pf="$(plausibility_failures golden "$reordered" "$pinned_golden")"
  chk "" "$pf" "golden matched by label, not by order"
  chk " A B C D" "$(cells_implausible ceiling 347 0 0 0 0)" "four degenerate ceiling cells"
  chk ""         "$(cells_implausible ceiling 347 340 340 345 345)" "four healthy ceiling cells"
  chk " D"       "$(cells_implausible ceiling 347 340 340 340 0)"   "only D degenerate"

  # --- bump_status: mutant M10, the monotonic exit status -------------------
  local before after
  for m in "0 1 1" "0 2 2" "1 1 1" "1 2 2" "2 1 2" "2 2 2" "0 0 0" "1 0 1" "2 0 2"; do
    set -- $m
    before="$1"; STATUS="$1"; bump_status "$2"; after="$STATUS"
    chk "$3" "$after" "bump_status $before + $2"
  done
  STATUS=0

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

# Named once, used everywhere below. Both are read AND written by this script,
# and spelling either of them out at each site is how a read and its matching
# write drift onto different files.
CEILING_FILE="$REPO_ROOT/tezt/tests/must_null_ceiling.ml"
GOLDEN_FILE="$REPO_ROOT/test/fixtures/self-index-stats.txt"

# Preflight: every metric_value() query runs through sqlite3, and it was never
# checked for — its absence looks identical to every column it queries having
# been renamed (q() swallows sqlite3's own "not found" error same as any other),
# which is exactly the silent-degradation shape H-2 below guards against. Fail
# loudly here instead of producing four empty, "successfully" measured cells.
command -v sqlite3 >/dev/null 2>&1 || {
  echo "recalibrate: sqlite3 not found in PATH — cannot query any measurement" >&2; exit 2; }
# Likewise dune: without it build_or_die's own failure message would be the
# first symptom, two pristine worktrees and a mktemp too late.
command -v dune >/dev/null 2>&1 || {
  echo "recalibrate: dune not found in PATH — cannot build either tree" >&2; exit 2; }

# dune roots itself by searching UPWARD, so a stray dune-project in an ancestor
# (a shared /tmp, notably) silently hijacks a bare invocation and builds the
# wrong tree. --root . is not optional here.
DUNE="dune"
# Log to a file rather than through a pipe, and surface it on failure: the
# diagnostic was previously discarded twice over — once by `| tail` eating the
# status, once by `>/dev/null` at the call site.
build_tree() {
  local tree="$1" log="$2"
  ( cd "$tree" && $DUNE build --root . ) >"$log" 2>&1
}
build_or_die() {
  local tree="$1" log="$2" what="$3"
  if ! build_tree "$tree" "$log"; then
    echo "recalibrate: $what build FAILED — refusing to measure a stale binary" >&2
    tail -30 "$log" >&2
    exit 2
  fi
}

# The DEFAULT baseline is the MERGE BASE, not origin/main's tip. Using the tip
# puts every commit that landed on main-but-not-here into the B and D cells and
# attributes it to this branch, so a branch that is merely behind main earns a
# BEHAVIOURAL refusal for changes it does not contain — and a gate that refuses
# wrongly is a gate people learn to bypass.
#
# An EXPLICIT --base is a different request and is taken LITERALLY: someone who
# types `--base origin/main` said the tip, not "compute a merge-base against
# it", and silently reinterpreting their explicit argument as something else is
# a surprise, not a convenience — the merge-base indirection is a default
# behaviour, not a property of the ref "origin/main" itself. Found in review:
# the old code branched on the STRING "origin/main", so `--base origin/main`
# and no `--base` at all were, bizarrely, not equivalent to `--base` naming any
# other ref — they were the one case where the argument was ignored.
if [ "$BASE_EXPLICIT" = 0 ]; then
  BASE_SHA="$(git merge-base HEAD origin/main 2>/dev/null)" || BASE_SHA=""
  [ -n "$BASE_SHA" ] || {
    echo "recalibrate: cannot compute merge-base with origin/main (fetch first?)" >&2; exit 2; }
  BASE_DESC="merge-base(HEAD, origin/main)"
else
  BASE_SHA="$(git rev-parse --verify "${BASE_REF}^{commit}" 2>/dev/null)" || {
    echo "recalibrate: cannot resolve base ref '$BASE_REF'" >&2; exit 2; }
  BASE_DESC="$BASE_REF"
fi

HEAD_SHA="$(git rev-parse --verify HEAD 2>/dev/null)" || {
  echo "recalibrate: cannot resolve HEAD" >&2; exit 2; }

# Both sides must be the SAME KIND of tree, or the 2x2 compares two different
# corpora and its verdict means nothing. The baseline was always a pristine
# worktree; the "new" side used to be the developer's own incremental
# _build/default, which accumulates whatever aliases they happened to build.
# Measured cost of that asymmetry: a plain `dune build @check` moves the ceiling
# metric 340 -> 759 while classify still says SOURCE_ONLY, because A=B and C=D
# hold on two DIFFERENT corpus definitions. Found in review; it is the defect
# that most directly defeats the tool's purpose.
#
# EXEMPTION WINDOW, stated explicitly because it was silently wrong once
# already (the corpus/binary asymmetry above): must_null_ceiling.ml is exempt
# here as a CONSTANT FILE (the line `let clean_measured = N` may legitimately
# be dirty while recalibrating), but that same file's call sites are also
# SOURCE inside the ceiling metric's own corpus (_build/default, see
# metric_corpus below). The two worktrees below are built from committed SHAs,
# so an uncommitted edit to it — e.g. adding a new MUST-null call site — is
# NOT part of $D here: --check/--write can read as clean against a corpus that
# does not yet contain that edit, and only disagree once it is committed and
# measured for real (by this script's next run, or by the tezt in CI). This is
# a real gap, not a false exemption: narrowing it would mean diffing which
# LINES of the file changed, which this script does not attempt.
CONSTANT_FILES="test/fixtures/self-index-stats.txt tezt/tests/must_null_ceiling.ml"
# git status --porcelain -uno | awk '{print $2}' mis-parses two common shapes:
# a rename row ("R  old -> new") yields $2 = "old", losing "new" entirely, and
# a path containing a space is C-quoted by porcelain and awk splits it on the
# space anyway. `git diff --name-only` emits one whole path per line (renames
# split into their own delete+add lines with --no-renames) and is read with
# `IFS= read -r`, not word-split, so neither shape is mangled. Found in review.
# `git diff` cannot see untracked files AT ALL, so the commonest workflow —
# add a module, recalibrate, then commit — walked straight past this gate and
# wrote a golden measured over two pristine worktrees that do not contain the
# new file. It was then wrong the instant the file was committed, and reported
# success. Round 2 reworked this line for renames and spaces and did not close
# the larger hole. `--others --exclude-standard` adds exactly the untracked,
# non-ignored files.
dirty="$(git diff --no-renames --name-only HEAD -- 2>/dev/null
         git ls-files --others --exclude-standard 2>/dev/null)"
unexpected=""
while IFS= read -r f; do
  [ -z "$f" ] && continue
  case " $CONSTANT_FILES " in
    *" $f "*) ;;
    *) unexpected="$unexpected
$f" ;;
  esac
done <<EOF
$dirty
EOF
if [ -n "$unexpected" ]; then
  echo "recalibrate: working tree has uncommitted changes, so HEAD is not what you are" >&2
  echo "  measuring. Commit them first (the constant files themselves are exempt):" >&2
  echo "$unexpected" | while IFS= read -r f; do [ -n "$f" ] && echo "    $f" >&2; done
  exit 2
fi

WORK="$(mktemp -d "${TMPDIR:-/tmp}/recalibrate.XXXXXX")" || exit 2
BASE_TREE="$WORK/base"
NEW_TREE="$WORK/new"
cleanup() {
  git worktree remove --force "$BASE_TREE" >/dev/null 2>&1
  git worktree remove --force "$NEW_TREE" >/dev/null 2>&1
  rm -rf "$WORK"
}
trap cleanup EXIT

echo "recalibrate: baseline $BASE_DESC = ${BASE_SHA:0:12}"
echo "recalibrate: head              = ${HEAD_SHA:0:12}"
git worktree add --detach "$BASE_TREE" "$BASE_SHA" >/dev/null 2>&1 || {
  echo "recalibrate: could not create baseline worktree" >&2; exit 2; }
git worktree add --detach "$NEW_TREE" "$HEAD_SHA" >/dev/null 2>&1 || {
  echo "recalibrate: could not create head worktree" >&2; exit 2; }

echo "recalibrate: building baseline…"
build_or_die "$BASE_TREE" "$WORK/base.log" "baseline"
echo "recalibrate: building head…"
build_or_die "$NEW_TREE" "$WORK/new.log" "head"

producer() { echo "$1/_build/default/bin/arch_callgraph_ocaml/arch_callgraph_ocaml.exe"; }

# One cell of the 2x2: index CORPUS with the producer built from BIN_TREE.
# The binary is invoked by PATH after an explicit build rather than through
# `dune exec`, which does NOT rebuild the producer (deps apply to `runtest`)
# and would silently measure a stale one — the number would then faithfully
# describe a binary, just not the one being attributed.
index_cell() {
  local bin_tree="$1" corpus="$2" out="$3" log="$4" label="$5"
  local exe; exe="$(producer "$bin_tree")"
  [ -x "$exe" ] || { echo "recalibrate: cell $label: missing producer $exe" >&2; return 2; }
  # --schema-path is the SCHEMA BELONGING TO THE BINARY BEING RUN, not always
  # NEW_TREE's. architecture-schema.sql is executed as DDL by the producer, so
  # binary and schema are one unit — and it is among the most frequently
  # edited files in the repo. The old code fed $NEW_TREE's schema to all four
  # cells, so cells A and C (bin_tree=$BASE_TREE, meant to contain NO branch
  # input at all) silently ran under the BRANCH's schema. Reproduced in review:
  # appending invalid SQL to architecture-schema.sql on a HEAD commit killed
  # the pure-baseline cell (A) first, before any cell that should legitimately
  # see the branch's code.
  if ! "$exe" --build-dir="$corpus" --db-path="$out" \
         --schema-path="$bin_tree/architecture-schema.sql" >"$log" 2>&1
  then
    # Both call sites used to run this under >/dev/null 2>&1 with a bare
    # `|| exit 2`, so a failed measurement printed NOTHING — the same
    # swallow-the-diagnostic defect build_or_die was just fixed for, one
    # function below it. Reproduced in review: the invalid-SQL probe above
    # exits 2 with two "building…" lines and silence, no matter which cell
    # actually failed.
    echo "recalibrate: cell $label: measurement FAILED (producer exited non-zero)" >&2
    echo "  build-dir=$corpus" >&2
    echo "  log: $log" >&2
    tail -30 "$log" >&2
    return 2
  fi
}

# The degraded arm's evidence. sqlite3's stderr used to go to /dev/null, so the
# one arm guarding "a query failed silently" had nothing of the query in it —
# round 5 measured it tailing the producer's SUCCESS output instead, ~120 lines
# of "Done! Indexed:" per cell, pointing the reader away from the cause. The
# arm is only reachable when index_cell returned 0, so the producer log cannot
# be the evidence by construction.
q() { sqlite3 "$1" "$2" 2>>"${QERR:-/dev/null}"; }

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
    golden)  cat "$GOLDEN_FILE" 2>/dev/null ;;
    # Through read_pinned_int, which is the ONE anchored reader for every
    # `let <name> = <int>` in this file. Anchored, it refuses forms it cannot
    # read rather than truncating them: `1_000` used to yield 1 and `0x200`
    # used to yield 0 — a WRONG number where the correct answer is a refusal.
    # An unreadable pin produces no value, which gate 1 reports as degraded.
    ceiling) read_pinned_int "$CEILING_FILE" clean_measured ;;
  esac
}

metric_kind() { case "$1" in golden) echo descriptive ;; ceiling) echo ratchet ;; esac; }


# ---------------------------------------------------------------------------
# the 2x2
# ---------------------------------------------------------------------------
# --only was already validated in the arg loop (see there for why: this used
# to run after both pristine builds, so a typo cost minutes). ONLY is here
# either empty or one of golden/ceiling.
METRICS="${ONLY:-golden ceiling}"

for metric in ${METRICS}; do
  corpus_rel="$(metric_corpus "$metric")"
  QERR="$WORK/$metric-query.err"; : > "$QERR"
  [ -n "$corpus_rel" ] || { echo "recalibrate: unknown metric '$metric'" >&2; exit 2; }

  # Per-metric database paths. These were four FIXED names (aa/ba/ab/bb.db)
  # reused across every metric, so correctness depended on the producer
  # TRUNCATING an existing file rather than appending to it. It does today —
  # but nothing states that invariant, nothing tests it, and if it ever stopped
  # holding the symptom would be a perfectly plausible number measured over two
  # corpora at once: §10.1's trap, with no second scope left to compare against.
  AA_DB="$WORK/$metric-aa.db"; BA_DB="$WORK/$metric-ba.db"
  AB_DB="$WORK/$metric-ab.db"; BB_DB="$WORK/$metric-bb.db"

  index_cell "$BASE_TREE" "$BASE_TREE/$corpus_rel" "$AA_DB" \
    "$WORK/$metric-A.log" "$metric A (base bin / base corpus)" || exit 2
  index_cell "$NEW_TREE"  "$BASE_TREE/$corpus_rel" "$BA_DB" \
    "$WORK/$metric-B.log" "$metric B (new bin / base corpus)"  || exit 2
  index_cell "$BASE_TREE" "$NEW_TREE/$corpus_rel"  "$AB_DB" \
    "$WORK/$metric-C.log" "$metric C (base bin / new corpus)"  || exit 2
  index_cell "$NEW_TREE"  "$NEW_TREE/$corpus_rel"  "$BB_DB" \
    "$WORK/$metric-D.log" "$metric D (new bin / new corpus)"   || exit 2

  # The byte-exact artifact CI will diff against, kept alongside the captured
  # value: a variable cannot represent a trailing newline, so the check that the
  # written file is correct cannot be made from "$D" alone.
  #
  # This deliberately does NOT go through metric_value(), and review's LOW-3
  # (fold it in, it is "a second textually-different source of truth for the
  # same three numbers") is declined on that point. It is a transcription of
  # ci.yml's own "Self-index smoke test" command — one sqlite3 invocation with
  # three concatenating SELECTs — whereas metric_value builds the same three
  # lines from three separate q() calls and a printf. Comparing them is a
  # DIFFERENTIAL check against the thing CI actually runs; making them one
  # function would turn the comparison below into a tautology and delete the
  # only place this tool checks itself against CI. What LOW-3 is right about is
  # the error handling, and that is fixed here: the exit status was unchecked
  # and stderr went outside $QERR, so this one call had exactly the silent
  # failure shape q() exists to close.
  if [ "$metric" = golden ]; then
    GOLDEN_RAW="$WORK/golden.raw"
    if ! sqlite3 "$BB_DB" \
         "SELECT 'modules: ' || count(*) FROM modules; \
          SELECT 'functions: ' || count(*) FROM functions; \
          SELECT 'calls: ' || count(*) FROM calls;" > "$GOLDEN_RAW" 2>>"$QERR"
    then
      echo
      echo "── $metric (measured over $corpus_rel)"
      echo "   ✗ REFUSED: the raw golden query failed on $BB_DB" >&2
      tail -20 "$QERR" >&2
      bump_status 2
      continue
    fi
  fi

  A="$(metric_value "$metric" "$AA_DB")"
  B="$(metric_value "$metric" "$BA_DB")"
  C="$(metric_value "$metric" "$AB_DB")"
  D="$(metric_value "$metric" "$BB_DB")"
  PINNED="$(metric_pinned "$metric")"
  KIND="$(metric_kind "$metric")"

  # -------------------------------------------------------------------------
  # gate 1 — well-formedness: is each cell USABLE as a value at all?
  # -------------------------------------------------------------------------
  # Rejected HERE, before classify() and before the currency comparison, in
  # every mode (--explain included, since it must not report a tree as current
  # when nothing was actually measured). The bug this closes: `[ "$D" =
  # "$PINNED" ]` had no integrity test, so a query returning empty (a renamed
  # column; q() swallows sqlite3's error same as any other) made an unmeasured
  # cell compare equal to an unmeasured anything, and `--check` printed
  # "✓ pinned value is current" having measured nothing.
  cell_bad="$(cells_degraded "$metric" "$A" "$B" "$C" "$D")"
  pin_bad="$(pinned_degraded "$KIND" "$PINNED")"
  if [ -n "$cell_bad$pin_bad" ]; then
    echo
    echo "── $metric ($KIND, measured over $corpus_rel)"
    echo "   ✗ REFUSED: no well-formed $metric measurement for:$cell_bad$pin_bad" >&2
    # The two causes are DIFFERENT and this used to print the sqlite3
    # explanation for both. Reproduced in five separate runs: an unreadable
    # CONSTANT was reported as "sqlite3 reported no error, so the query returned
    # an empty result — check the column names against the current schema", when
    # no query is involved and the cause is how the constant is spelled. Round 5
    # fixed this for cells and left PINNED pointing at the wrong thing.
    if [ -n "$cell_bad" ]; then
      if [ -s "${QERR:-/dev/null}" ]; then
        echo "     cells$cell_bad — sqlite3 wrote to stderr:" >&2
        tail -20 "$QERR" >&2
      else
        echo "     cells$cell_bad — sqlite3 reported no error, so the query returned an" >&2
        echo "     empty result rather than failing. Check the column names in" >&2
        echo "     metric_value() against the current schema." >&2
      fi
    fi
    if [ -n "$pin_bad" ]; then
      case "$metric" in
        ceiling)
          echo "     PINNED — no single 'let clean_measured = <int>' could be read from" >&2
          echo "       $CEILING_FILE" >&2
          echo "     The read is anchored on both ends (^let clean_measured = <digits>\$)," >&2
          echo "     so it refuses rather than truncates: a type annotation" >&2
          echo "     ('let clean_measured : int = 347'), an underscored literal ('1_000')," >&2
          echo "     a hex literal, a trailing comment, or two competing definitions all" >&2
          echo "     land here. Candidate lines in that file:" >&2
          grep -n '^let clean_measured' "$CEILING_FILE" >&2 || echo "       (none)" >&2
          ;;
        golden)
          echo "     PINNED — $GOLDEN_FILE is empty or unreadable." >&2
          ;;
      esac
    fi
    bump_status 2
    continue
  fi

  echo
  echo "── $metric ($KIND, measured over $corpus_rel)"
  printf '   %-28s %s\n' "pinned in tree"        "$(echo "$PINNED" | tr '\n' ' ')"
  printf '   %-28s %s\n' "A base bin/base src"   "$(echo "$A" | tr '\n' ' ')"
  printf '   %-28s %s\n' "B  NEW bin/base src"   "$(echo "$B" | tr '\n' ' ')"
  printf '   %-28s %s\n' "C base bin/ NEW src"   "$(echo "$C" | tr '\n' ' ')"
  printf '   %-28s %s\n' "D  NEW bin/ NEW src"   "$(echo "$D" | tr '\n' ' ')"

  # -------------------------------------------------------------------------
  # gate 2 — adequacy: was this corpus big enough to have been measured?
  # -------------------------------------------------------------------------
  # The ABSOLUTE floor, ceiling only. Mirrored from must_null_ceiling.ml's own
  # [min_total_calls] rather than invented here: that tezt already carries
  # exactly this guard, for exactly this reason ("an under-built _build/default
  # indexes fewer calls across the board, which would otherwise read as a
  # comfortable pass on the ceiling rather than as 'nothing was measured'"), and
  # over the SAME corpus this metric uses (_build/default). It is READ FROM THE
  # FILE, not copied, so the two cannot drift apart — a copied 8000 would be a
  # number with no harness behind it, §10.3.
  #
  # It is a live guard, not a theoretical one: it fired during this round's own
  # baseline run, on a `dune test --force` that had under-built the tree —
  # "only 6783 calls were indexed, below the floor of 8000".
  #
  # The golden gets no absolute floor. Its corpus is lib/arch_index alone, a
  # different scope (§10.1), and min_total_calls was never calibrated over it;
  # inventing a second constant here would be the very thing this comment
  # objects to. The golden is covered by gate 3.
  if [ "$metric" = ceiling ]; then
    MTC="$(read_pinned_int "$CEILING_FILE" min_total_calls)" || MTC=""
    if ! is_int "$MTC"; then
      echo "   ✗ REFUSED: no single 'let min_total_calls = <int>' could be read from" >&2
      echo "     $CEILING_FILE — the corpus adequacy floor is unavailable, and a" >&2
      echo "     measurement with no adequacy floor is not a measurement." >&2
      bump_status 2
      continue
    fi
    inadequate=""
    for pair in "A:$AA_DB" "B:$BA_DB" "C:$AB_DB" "D:$BB_DB"; do
      label="${pair%%:*}"; dbf="${pair#*:}"
      tot="$(q "$dbf" 'SELECT count(*) FROM calls;')"
      is_int "$tot" && [ "$tot" -ge "$MTC" ] || inadequate="$inadequate $label(total=${tot:-none})"
    done
    if [ -n "$inadequate" ]; then
      echo "   ✗ REFUSED: corpus adequacy floor not met by:$inadequate" >&2
      echo "     Each cell's database must hold at least $MTC rows in [calls] —" >&2
      echo "     must_null_ceiling.ml's own min_total_calls — before its ceiling" >&2
      echo "     count means anything. An under-built tree indexes fewer calls" >&2
      echo "     across the board, and that reads as a comfortable TIGHTENING" >&2
      echo "     rather than as 'nothing was measured'." >&2
      if [ -s "${QERR:-/dev/null}" ]; then
        echo "     --- sqlite3 stderr ---" >&2
        tail -20 "$QERR" >&2
      fi
      bump_status 2
      continue
    fi
  fi

  # -------------------------------------------------------------------------
  # gate 3 — plausibility: is this measurement believable against the pin?
  # -------------------------------------------------------------------------
  # CRITICAL-1. See the block above plausibility_failures() for the
  # reproduction and for why "a tighten is always safe" is false. Applied to all
  # four cells, not just D: every one of them feeds classify(), and four
  # degenerate cells are the cleanest possible SOURCE_ONLY.
  implausible="$(cells_implausible "$metric" "$PINNED" "$A" "$B" "$C" "$D")"
  if [ -n "$implausible" ]; then
    echo "   ✗ REFUSED: implausible measurement in cell(s):$implausible" >&2
    for pair in "A:$A" "B:$B" "C:$C" "D:$D"; do
      label="${pair%%:*}"; val="${pair#*:}"
      plausibility_failures "$metric" "$val" "$PINNED" | while IFS= read -r pline; do
        [ -n "$pline" ] && echo "       $label $pline" >&2
      done
    done
    echo "     A component that has collapsed below 1/$PLAUSIBILITY_DEN of the pinned" >&2
    echo "     value is far likelier a query that stopped matching than a real" >&2
    echo "     movement of that size. sqlite3 does not error on a predicate that" >&2
    echo "     matches nothing — it returns 0 — so a broken measurement and a" >&2
    echo "     spectacular gain have the same shape, and only this floor tells" >&2
    echo "     them apart. That is also why 'a ratchet may always be TIGHTENED'" >&2
    echo "     is not enough on its own: every silent breakage moves the number" >&2
    echo "     DOWN, into the direction that axiom calls always-safe." >&2
    echo "     If the movement is REAL, recalibrate by hand and record why — one" >&2
    echo "     commit message, the same contract the BEHAVIOURAL arm has." >&2
    bump_status 2
    continue
  fi

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
    diff -q "$GOLDEN_FILE" "$GOLDEN_RAW" >/dev/null 2>&1 && CURRENT=1
  elif [ "$metric" = ceiling ]; then
    # One anchored reader for every pinned integer; see read_pinned_int. The
    # `| head -1` that used to terminate this read is gone: a pinned constant
    # that is defined twice is a defect to report, not a coin to flip.
    hr="$(read_pinned_int "$CEILING_FILE" headroom)"; hr_rc=$?
    if [ "$hr_rc" -ne 0 ] || ! is_int "$hr"; then
      echo "   ✗ REFUSED: no single 'let headroom = <int>' could be read from" >&2
      echo "     $CEILING_FILE. This value enters the arithmetic that decides" >&2
      echo "     whether anything is written, so an unreadable one is refused" >&2
      echo "     rather than defaulted." >&2
      [ "$hr_rc" = 2 ] && \
        echo "     It is defined MORE THAN ONCE below; this tool will not choose." >&2
      echo "     Candidate lines:" >&2
      grep -n '^let headroom' "$CEILING_FILE" >&2 || echo "       (none)" >&2
      bump_status 2
      continue
    fi
    case "$(band_verdict "$D" "$PINNED" "$hr")" in
      CURRENT)
        CURRENT=1
        [ "$D" = "$PINNED" ] || \
          echo "   • within headroom: measures $D against pinned $PINNED (+/-$hr) — advisory, not stale"
        ;;
      BREACH)
        CURRENT=0
        echo "   • BREACH: $D is above pinned $PINNED + headroom $hr = $(( PINNED + hr ))"
        ;;
      GAIN)
        CURRENT=0
        echo "   • GAIN: $D is below pinned $PINNED - headroom $hr = $(( PINNED - hr ))"
        ;;
      *)
        echo "   ✗ REFUSED: the band could not be computed (D='$D' pinned='$PINNED' headroom='$hr')" >&2
        bump_status 2
        continue
        ;;
    esac
  else
    [ "$D" = "$PINNED" ] && CURRENT=1
  fi

  if [ "$CURRENT" = 1 ]; then
    echo "   ✓ pinned value is current."
    continue
  fi

  case "$MODE" in
    explain)
      # A read-only mode that exits non-zero with no output reads as a crash.
      # Say what is stale; leave the exit status to --check.
      echo "   ✗ STALE: pinned value is not what this tree measures (would become: $D)."
      ;;
    check)
      echo "   ✗ STALE: pinned value is not what this tree measures."
      bump_status 1
      ;;
    write)
      WVERDICT=WRITE
      [ "$KIND" = ratchet ] && WVERDICT="$(ratchet_write_verdict "$D" "$PINNED")"
      if [ "$BEHAVIOURAL" = 1 ]; then
        echo "   ✗ REFUSED: movement is not attributable to source change alone."
        bump_status 1
      elif [ "$WVERDICT" = REFUSE_D ]; then
        # `[ "$D" -gt "$PINNED" ]` returns 2 on a non-integer operand, and the
        # old code read any non-zero as "not a loosening" and fell THROUGH to
        # the write. An empty $D is reachable — q() swallows sqlite3 errors —
        # so the guard failed open and sed produced `let clean_measured = `,
        # a file that does not compile. (Now additionally unreachable in
        # practice, since gate 1 catches a non-integer D — defence in depth.)
        echo "   ✗ REFUSED: measured value is not an integer (got '$D')." >&2
        bump_status 1
      elif [ "$WVERDICT" = REFUSE_PINNED ]; then
        echo "   ✗ REFUSED: pinned value is not an integer (got '$PINNED') —" >&2
        echo "     the constant may have been reformatted out of the regex's reach." >&2
        bump_status 1
      elif [ "$WVERDICT" = REFUSE_LOOSEN ]; then
        # The asymmetry. Raising a bound to meet the code is precisely the
        # failure this repository already suffered; it stays a human act.
        echo "   ✗ REFUSED: a ratchet may be tightened automatically, never loosened."
        echo "     $PINNED → $D would RAISE the bound. Record the +$(( D - PINNED )) and why."
        bump_status 1
      else
        case "$metric" in
          golden)
            # Verify BEFORE writing into the tracked path, not after: a
            # degraded measurement used to overwrite the fixture with garbage
            # ("modules: $" etc.) and only THEN report the mismatch, leaving
            # the tracked file corrupted with no rollback until the user knew
            # to `git checkout` it. Now the candidate is written to a scratch
            # path under $WORK and only `mv`d over the tracked file once it is
            # confirmed byte-identical to a raw measurement. printf '%s\n', not
            # '%s': command substitution strips trailing newlines, so writing
            # "$D" back verbatim would silently produce a file with no final
            # newline, and CI compares it with `diff` against raw `sqlite3`
            # output, which has one.
            printf '%s\n' "$D" > "$WORK/golden.new"
            if [ -n "${GOLDEN_RAW:-}" ] && [ -f "$GOLDEN_RAW" ] \
               && diff -q "$WORK/golden.new" "$GOLDEN_RAW" >/dev/null 2>&1
            then
              # Check the mv, then re-verify the INSTALLED file — not the scratch
              # copy. Round 2 moved the write to scratch so a refusal could not
              # leave a half-edited tracked file, and moved the verification
              # with it; nothing then checked the artifact that matters. With
              # the target directory read-only this printed
              # "✓ WROTE … byte-identical to a raw measurement" and exited 0
              # having written NOTHING.
              if ! mv "$WORK/golden.new" "$GOLDEN_FILE"; then
                echo "   ✗ REFUSED: could not install test/fixtures/self-index-stats.txt" >&2
                bump_status 2
              elif ! diff -q "$GOLDEN_FILE" "$GOLDEN_RAW" >/dev/null 2>&1; then
                echo "   ✗ INSTALLED file does not match a raw measurement:" >&2
                diff "$GOLDEN_FILE" "$GOLDEN_RAW" >&2
                bump_status 2
              else
                echo "   ✓ WROTE test/fixtures/self-index-stats.txt (installed file verified byte-identical)"
              fi
            else
              echo "   ✗ REFUSED to write: measurement does not match a raw measurement" >&2
              echo "     byte-for-byte — the tracked file is UNCHANGED." >&2
              diff "$WORK/golden.new" "${GOLDEN_RAW:-/dev/null}" >&2
              bump_status 1
            fi
            ;;
          ceiling)
            # Same verify-before-write shape as the golden, for the same
            # reason: sed -i used to edit the tracked file directly and only
            # read it back afterward, so a reformatting that put the constant
            # out of the regex's reach ("let clean_measured : int = 321")
            # still left a partially-touched tracked file on the refusal path.
            # ceiling_write_to edits a COPY and reads it back with the one
            # anchored reader; --self-test drives it against temp fixtures,
            # which is what the previous round's fix here was missing.
            written="$(ceiling_write_to "$CEILING_FILE" "$WORK/ceiling.new" "$D")" || written=""
            if [ "$written" = "$D" ]; then
              # Check the mv, then re-read the INSTALLED file. "(read back and
              # confirmed)" was literally false — the read-back was on
              # $WORK/ceiling.new.
              if ! mv "$WORK/ceiling.new" "$CEILING_FILE"; then
                echo "   ✗ REFUSED: could not install tezt/tests/must_null_ceiling.ml" >&2
                bump_status 2
              else
                installed="$(metric_pinned ceiling)"
                if [ "$installed" = "$D" ]; then
                  echo "   ✓ TIGHTENED clean_measured $PINNED → $D (installed file re-read and confirmed)"
                else
                  echo "   ✗ INSTALLED file reads '$installed', expected $D" >&2
                  bump_status 2
                fi
              fi
            else
              echo "   ✗ REFUSED to write: clean_measured would read '$written', expected $D —" >&2
              echo "     the tracked file is UNCHANGED. The constant is probably not spelled" >&2
              echo "     'let clean_measured = <int>' on a line of its own." >&2
              bump_status 1
            fi
            ;;
        esac
      fi
      ;;
  esac
done

echo
exit "$STATUS"
