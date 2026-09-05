#!/usr/bin/env bash
# check-mutaml-integration.sh — does the wrapper resolve MUTAML_MUTANT correctly under a REAL
# mutaml-runner?
#
# The mechanism is no longer in doubt: it was established by READING the engine, not its README.
# src/runner/runner.ml:123-130 (github.com/jmid/mutaml at 783831d) builds, per mutant,
#
#     MUTAML_MUTANT=<mut_id> timeout <n> <test_cmd>
#
# and runs it with Sys.command, and src/ppx/mutaml_ppx.ml:40 shows the instrumented code reading
# that same variable through Sys.getenv_opt. So the driver's wrapper CAN see which mutant is
# active. What this check confirms is the RUNTIME behaviour on top of that premise: that the
# wrapper, handed to a real runner as its test command, resolves the id the runner exports to the
# test set the driver computed — and not to the whole suite.
#
# EXIT 3 WHEN MUTAML IS ABSENT, NOT 1. An unverified integration and a failed one are different
# facts and must not collapse into one exit code: "we could not check" read as "we checked and it
# was fine" is how an integration ships unexercised. 3 is this repository's "the callee declined
# to answer" code, and it is what a caller must propagate rather than fold into a failure.
#
# Usage:  scripts/check-mutaml-integration.sh
#         MUTAML_RUNNER=<path> overrides the search.
# Exit:   0 = the wrapper resolved the mutant to the expected test set under a real runner.
#         1 = the assertion fired: it resolved to something else.
#         2 = harness error.
#         3 = mutaml is not available here; the integration is UNVERIFIED, not verified.

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
WRAPPER="$ROOT/scripts/mutaml-wrapper.sh"
[ -x "$WRAPPER" ] || { echo "check-mutaml-integration: $WRAPPER is missing or not executable" >&2; exit 2; }

runner=""
if [ -n "${MUTAML_RUNNER-}" ]; then
  if [ -x "$MUTAML_RUNNER" ]; then runner="$MUTAML_RUNNER"
  else echo "check-mutaml-integration: MUTAML_RUNNER=$MUTAML_RUNNER is not executable" >&2; exit 2; fi
else
  for c in mutaml-runner mutaml; do
    p="$(command -v "$c" 2>/dev/null)" && [ -n "$p" ] && { runner="$p"; break; }
  done
fi

if [ -z "$runner" ]; then
  echo "check-mutaml-integration: UNVERIFIED — no mutaml-runner on PATH and MUTAML_RUNNER is unset."
  echo "  This is exit 3, deliberately not 1: the integration was not exercised, which is a"
  echo "  different fact from having been exercised and failed. Do not read this as a pass."
  echo "  To verify it, install mutaml (opam install mutaml) or point MUTAML_RUNNER at a built"
  echo "  src/runner/runner.exe, then re-run this script."
  exit 3
fi

command -v timeout >/dev/null 2>&1 || {
  echo "check-mutaml-integration: mutaml's runner requires \`timeout\`, which is not installed" >&2
  exit 2
}

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
cd "$work" || exit 2

# A two-function fixture, expressed the way mutaml expresses one: a `.muts` catalogue holding two
# mutants in one file. The runner derives each mutant's id as
# `Filename.remove_extension <muts file> ^ ":" ^ number` (src/common/mutaml_common.ml:30), so the
# ids below are "lib/x:1" and "lib/x:2".
mkdir -p lib
cat > lib/x.muts <<'JSON'
[ {"number":1,"repl":"true",
   "loc":{"loc_start":{"pos_fname":"lib/x.ml","pos_lnum":3,"pos_bol":0,"pos_cnum":4},
          "loc_end":{"pos_fname":"lib/x.ml","pos_lnum":3,"pos_bol":0,"pos_cnum":9},
          "loc_ghost":false}},
  {"number":2,"repl":"false",
   "loc":{"loc_start":{"pos_fname":"lib/x.ml","pos_lnum":9,"pos_bol":0,"pos_cnum":2},
          "loc_end":{"pos_fname":"lib/x.ml","pos_lnum":9,"pos_bol":0,"pos_cnum":7},
          "loc_ghost":false}} ]
JSON

# The selection the driver would have written: mutant 1 is reached by one test, mutant 2 by two.
# Two DIFFERENT sets on purpose — a wrapper that ignored MUTAML_MUTANT and always emitted the same
# set would satisfy a single-set fixture perfectly.
printf 'lib/x:1\t0\tt_alpha\tt_alpha\n'                 >  selection.tsv
printf 'lib/x:2\t0\tt_beta,t_gamma\tt_beta,t_gamma\n'   >> selection.tsv
: > trace.tsv

# The "test command" the wrapper runs: it records the arguments it was handed, which is what the
# executed set becomes on the command line.
cat > fake-tests.sh <<'SH'
#!/bin/sh
printf '%s\n' "$*" >> "$RECORD"
exit 0
SH
chmod +x fake-tests.sh

export ARCH_MUTANTS_SELECTION="$work/selection.tsv"
export ARCH_MUTANTS_TRACE="$work/trace.tsv"
export RECORD="$work/record.txt"
export ARCH_MUTANTS_TEST_CMD="$work/fake-tests.sh"
: > "$RECORD"

"$runner" --muts lib/x.muts "$WRAPPER" > runner.log 2>&1
rc=$?
if [ ! -s "$ARCH_MUTANTS_TRACE" ]; then
  echo "check-mutaml-integration: the runner exited $rc and the wrapper was never invoked." >&2
  sed 's/^/    /' runner.log >&2
  exit 2
fi

got1="$(awk -F'\t' '$1=="lib/x:1"{print $3}' "$ARCH_MUTANTS_TRACE")"
got2="$(awk -F'\t' '$1=="lib/x:2"{print $3}' "$ARCH_MUTANTS_TRACE")"
invocations="$(wc -l < "$ARCH_MUTANTS_TRACE" | tr -d ' ')"

echo "check-mutaml-integration: runner $runner exited $rc"
echo "  · wrapper invocations : $invocations (expected 2 — one per mutant, NOT one per engine run)"
echo "  · lib/x:1 resolved to : ${got1:-<nothing>} (expected t_alpha)"
echo "  · lib/x:2 resolved to : ${got2:-<nothing>} (expected t_beta,t_gamma)"

fails=0
[ "$invocations" = "2" ] || { echo "  ✗ the wrapper ran $invocations time(s), not once per mutant"; fails=1; }
[ "$got1" = "t_alpha" ] || { echo "  ✗ lib/x:1 resolved to '${got1:-<nothing>}'"; fails=1; }
[ "$got2" = "t_beta,t_gamma" ] || { echo "  ✗ lib/x:2 resolved to '${got2:-<nothing>}'"; fails=1; }

if [ "$fails" -ne 0 ]; then
  echo "check-mutaml-integration: FAILED — the wrapper did not resolve MUTAML_MUTANT to the set"
  echo "  the driver declared. A campaign built on this would record a selection it never made."
  exit 1
fi
echo "check-mutaml-integration: the wrapper resolved each mutant to its declared set under a real runner."
exit 0
