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
# Exit: the test command's own exit code, which is what the engine reads (mutaml: 0 =
#       "passed" = the mutant SURVIVED, 124 = timeout, anything else = killed).
#       2 = this wrapper could not do its job at all — a missing variable, or a mutant the
#       driver never catalogued. It refuses rather than running the whole suite, because a
#       silent fallback to "run everything" would make an unrecognised mutant read as a
#       correctly-selected one.

set -uo pipefail

fail() { printf 'mutaml-wrapper: %s\n' "$1" >&2; exit 2; }

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
      cmd="${ARCH_MUTANTS_TEST_CMD//\{tests\}/${tests[*]}}"
      sh -c "$cmd"
      rc=$?
      ;;
    *)
      sh -c "$ARCH_MUTANTS_TEST_CMD \"\$@\"" sh "${tests[@]}"
      rc=$?
      ;;
  esac
fi

printf '%s\t%s\t%s\t%s\n' "$mut" "${#tests[@]}" "$executed" "$rc" >> "$ARCH_MUTANTS_TRACE"
exit "$rc"
