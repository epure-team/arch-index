#!/usr/bin/env bash
# mutaml-wrapper.sh — the per-mutant test command `arch-mutants run` hands to the engine.
#
# THE EXECUTION MODEL, so it cannot be read two ways:
#
#     driver  →  engine (invoked ONCE)  →  this wrapper (invoked ONCE PER MUTANT)  →  tests
#
# The driver invokes the engine exactly once. The engine loops over its own mutants
# internally — that is how mutaml and cargo-mutants both work and the driver cannot change
# it. What runs once per mutant is THIS SCRIPT, which the driver passed to the engine as
# the engine's test command. mutaml's runner builds, per mutant,
#
#     MUTAML_MUTANT=<mut_id> timeout <n> <test_cmd> > <output> 2>&1
#
# (src/runner/runner.ml:123-130 in github.com/jmid/mutaml at 783831d), so the active
# mutant's identity arrives here in the environment. That is the whole mechanism: mutaml
# cannot vary its test command, but the command it runs can vary what IT runs.
#
# Anything asserting "the engine was invoked twice for two mutants" is asserting the wrong
# thing. Assert on THIS script's invocations, recorded in $ARCH_MUTANTS_TRACE.
#
# Environment, all set by the driver:
#   MUTAML_MUTANT           the engine's id for the mutant now active (set by the engine)
#   ARCH_MUTANTS_SELECTION  TSV the driver wrote, one line per catalogued mutant:
#                             <engine id>\t<superset 0|1>\t<intended,…>\t<executed,…>
#   ARCH_MUTANTS_TEST_CMD   the real test command. If it contains the token {tests} the
#                           executed set is substituted there; otherwise the set is
#                           appended as arguments.
#   ARCH_MUTANTS_TRACE      append-only TSV this script writes one line to per invocation:
#                             <engine id>\t<executed count>\t<executed,…>\t<exit code>
#
# Exit: the test command's own exit code, which is what the engine reads — EXCEPT that a
#       test command exiting 99 is remapped to 1, because 99 is this script's refusal code
#       and a code cannot mean two things at the boundary a third-party engine reads.
#
#       THE REFUSAL CODE IS 99, AND IT HAD TO BE A DISTINCTIVE ONE. mutaml persists the RAW
#       exit code, not the label it prints: src/runner/runner.ml:109-110 saves
#       `{ status = ret; mutant }` and src/common/mutaml_common.ml:74 declares
#       `status : int`, so whatever this script exits with is what lands in
#       mutaml-report.json and what `arch-mutants` then classifies. The driver's adapter
#       reads 0 as SURVIVED, 124 as TIMEOUT and EVERY OTHER CODE as KILLED. A refusal that
#       exited 2 — as this script used to — therefore arrived at the report as a clean
#       KILL, so a wholly broken selection produced a campaign of kills instead of a
#       refusal: the single worst reading, because a kill is the one outcome the design
#       treats as self-certifying proof.
#
#       99 is reserved for that and nothing else. The codes already spoken for are 0
#       (mutaml: "passed" = SURVIVED), 124 (GNU timeout, which mutaml wraps every test in),
#       127 (command-not-found, which mutaml treats as fatal and exits on), 126 (found but
#       not executable) and 128+n (killed by signal n, so 129-165 in practice). 99 sits
#       below 126 and outside every one of those, and no test runner in this repo's
#       profiles emits it. `arch-mutants` maps exactly 99 — no range, no catch-all — to a
#       NOT-ATTEMPTED / REFUSED outcome that can never become a kill, can never be
#       attributed to a test, and leaves the campaign's completed_at NULL.
#
#       Every refusal path exits 99: MUTAML_MUTANT unset, an uncatalogued mutant, an unset
#       or unreadable selection file, a missing test command, a missing trace file. It
#       refuses rather than running the whole suite, because a silent fallback to "run
#       everything" would make an unrecognised mutant read as a correctly-selected one.

set -uo pipefail

# Keep this in step with `refusal_exit_code` in bin/arch_mutants/arch_mutants.ml.
ARCH_MUTANTS_REFUSAL_EXIT=99

fail() { printf 'mutaml-wrapper: %s (refusing, exit %d)\n' "$1" "$ARCH_MUTANTS_REFUSAL_EXIT" >&2; exit "$ARCH_MUTANTS_REFUSAL_EXIT"; }

[ -n "${ARCH_MUTANTS_SELECTION-}" ] || fail "ARCH_MUTANTS_SELECTION is not set"
[ -r "${ARCH_MUTANTS_SELECTION}" ] || fail "cannot read the selection file ${ARCH_MUTANTS_SELECTION}"
[ -n "${ARCH_MUTANTS_TEST_CMD-}" ] || fail "ARCH_MUTANTS_TEST_CMD is not set"
[ -n "${ARCH_MUTANTS_TRACE-}" ] || fail "ARCH_MUTANTS_TRACE is not set"

# Unset MUTAML_MUTANT is refused, not defaulted. Running the full suite "just in case"
# would produce a record indistinguishable from a correctly-selected run, and the whole
# campaign rests on the executed set being known.
mut="${MUTAML_MUTANT-}"
[ -n "$mut" ] || fail "MUTAML_MUTANT is not set — the engine did not name the active mutant"

line="$(awk -F'\t' -v m="$mut" '$1 == m { print; exit }' "$ARCH_MUTANTS_SELECTION")"
[ -n "$line" ] || fail "mutant '$mut' is not in the selection the driver computed — refusing to guess its test set"

executed="$(printf '%s' "$line" | cut -f4)"

# Split on commas, dropping empties. An EMPTY executed set is legitimate and is not an
# error: a target with a provably empty reaching set inside a closed cone has no test to
# run, and the honest outcome is "nothing ran, the mutant survived" — a real, provable
# test gap (EC-1). Running the whole suite here would erase exactly that finding.
tests=()
if [ -n "$executed" ]; then
  IFS=',' read -r -a tests <<< "$executed"
fi

rc=0
if [ "${#tests[@]}" -eq 0 ]; then
  rc=0
else
  case "$ARCH_MUTANTS_TEST_CMD" in
    *"{tests}"*)
      # The names substituted here come from the ANALYSED REPOSITORY'S OWN SOURCE — they are
      # function names the index harvested, not operator input — and they are spliced into a
      # string handed to `sh -c`. Interpolating them raw made a campaign over an untrusted
      # checkout arbitrary command execution: a test named `a;touch /tmp/PWNED;echo x` ran the
      # touch. Each name is single-quoted before substitution, with any embedded quote closed
      # and reopened the POSIX way ('\''), so the shell sees one word per name and no operator.
      # The sibling branch below was already safe; only this one was not.
      quoted=""
      for t in "${tests[@]}"; do
        quoted="$quoted '${t//\'/\'\\\'\'}'"
      done
      cmd="${ARCH_MUTANTS_TEST_CMD//\{tests\}/${quoted# }}"
      sh -c "$cmd"
      rc=$?
      ;;
    *)
      sh -c "$ARCH_MUTANTS_TEST_CMD \"\$@\"" sh "${tests[@]}"
      rc=$?
      ;;
  esac
fi

# 99 IS THIS WRAPPER'S, END TO END. Forwarding the test command's own exit code unchanged
# meant a runner that legitimately exits 99 arrived at the driver as THIS SCRIPT'S refusal:
# the mutant lost its run row, could never be KILLED, landed in PENDING and blocked the
# campaign's completion — a real test failure read as "never attempted". Reserving a code in
# a third-party tool's exit space is only sound if the reservation is enforced at the one
# place both meanings pass through, which is here.
#
# 1 is the honest remap: the driver's adapter reads 0 as SURVIVED, 124 as TIMEOUT and every
# other code as KILLED, and a test command exiting non-zero under a mutation IS a kill. The
# code is not swallowed — it is named on stderr, so an operator debugging a runner still
# sees the value the runner actually produced.
if [ "$rc" -eq "$ARCH_MUTANTS_REFUSAL_EXIT" ]; then
  printf 'mutaml-wrapper: the test command exited %d for mutant %s, which is the code this wrapper reserves for a REFUSAL. It ran, so this is an ordinary test failure and is reported as exit 1. Only THIS script exits %d, and only without writing a trace line.\n' \
    "$rc" "$mut" "$ARCH_MUTANTS_REFUSAL_EXIT" >&2
  rc=1
fi

# The trace line is the discriminator the driver relies on: it exists for every mutant whose
# tests were actually attempted, and for none that this script refused — `fail` exits above,
# before this point.
printf '%s\t%s\t%s\t%s\n' "$mut" "${#tests[@]}" "$executed" "$rc" >> "$ARCH_MUTANTS_TRACE"
exit "$rc"
