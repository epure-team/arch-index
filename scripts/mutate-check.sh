#!/usr/bin/env bash
# Mutation check — replaces a four-step manual ritual with one command.
#
# The ritual was: edit the file, build a target, run it, restore. Every one of
# those steps failed at least once in practice, each in a different way:
#
#   edit    a `sed` expression whose anchor never matched; `grep -c` returned 0
#           and the mutation was reported as applied and restored
#   build   `dune build test/<t>.exe` does NOT rebuild a test's
#           (deps %{exe:...}) dependency, so the test ran a STALE binary and
#           the mutant survived for a reason that had nothing to do with the test
#   run     an assertion checked a sentinel appeared *somewhere*; a second site
#           produced it
#   restore left to hand, so a failed run could leave the tree mutated
#
# This script removes all four. It refuses to run unless the anchor occurs
# exactly the declared number of times, requires a GREEN baseline (otherwise
# KILLED/SURVIVED means nothing), always drives the canonical test command
# rather than a hand-built target, and restores via trap on every exit path
# including SIGINT.
#
# Usage:
#   scripts/mutate-check.sh <file> <expected-anchor-count> <anchor> <replacement> [test-cmd]
#
# Defaults to `dune runtest --root <repo root>` (`dune test` is an alias for
# `runtest`, so this is correct in both this repo and arch-index). Override per
# call or via MUTATE_TEST_CMD.
#
# The root is the git toplevel, NOT `.`, and that distinction is load-bearing:
# `--root .` is only correct when the script is invoked FROM the repo root.
# Measured from lib/: `dune runtest --root .` re-roots dune at the
# subdirectory, warns `No dune-project file has been found in directory "."  A
# default one is assumed`, CREATES a stray lib/_build, and then exits 1 on an
# unrelated `public_name` error. This script would have read that as a RED
# BASELINE and refused with a diagnostic pointing at the wrong thing, having
# already polluted the tree. `--root "$(git rev-parse --show-toplevel)"` makes
# the command mean the same thing from any directory. (The <file> argument is
# still resolved relative to your cwd, as usual.)
#
# `--root` is also what keeps a stray ANCESTOR dune-project from hijacking a
# bare invocation: dune roots itself by searching upward to the OUTERMOST
# ancestor dune-project, and a real /tmp/dune-project on a developer machine is
# enough to make `dune build` announce `Entering directory '/tmp'`.
#
# Exit codes: 0 = mutant KILLED (the test earned its keep)
#             1 = mutant SURVIVED (the test does not detect the defect)
#             2 = setup refused (bad anchor count, red baseline, bad usage)
set -uo pipefail

die() { printf 'mutate-check: %s\n' "$*" >&2; exit 2; }

[ "$#" -ge 4 ] || die "usage: $0 <file> <expected-count> <anchor> <replacement> [test-cmd]"

FILE=$1
EXPECTED=$2
ANCHOR=$3
REPLACEMENT=$4
REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null) \
  || die "not inside a git repository — cannot root the default test command.
  Pass an explicit [test-cmd] or set MUTATE_TEST_CMD."
DEFAULT_TEST_CMD="dune runtest --root $(printf '%q' "$REPO_ROOT")"
TEST_CMD=${5:-${MUTATE_TEST_CMD:-$DEFAULT_TEST_CMD}}

[ -f "$FILE" ] || die "no such file: $FILE"
case $EXPECTED in ''|*[!0-9]*) die "expected-count must be a non-negative integer, got '$EXPECTED'" ;; esac
[ "$EXPECTED" -ge 1 ] || die "expected-count must be >= 1; a mutation with no anchor is vacuous by construction"

# Literal (not regex) counting and replacement. sed/grep metacharacters in the
# anchor are the reason the original ritual reported a mutation it never made.
count_anchor() {
  ANCHOR="$ANCHOR" python3 -c '
import os,sys
sys.stdout.write(str(open(sys.argv[1], encoding="utf-8").read().count(os.environ["ANCHOR"])))' "$FILE"
}

ACTUAL=$(count_anchor) || die "could not read $FILE"
if [ "$ACTUAL" != "$EXPECTED" ]; then
  die "anchor occurs $ACTUAL time(s) in $FILE, declared $EXPECTED.
  Refusing to run: an unasserted anchor is how a mutation gets reported as
  applied without ever changing anything. Fix the count or the anchor."
fi

BACKUP=$(mktemp "${TMPDIR:-/tmp}/mutate-check.XXXXXX") || die "mktemp failed"
cp "$FILE" "$BACKUP" || die "could not back up $FILE"
restore() { cp "$BACKUP" "$FILE" && rm -f "$BACKUP"; }
trap 'restore' EXIT INT TERM

printf 'mutate-check: baseline — %s\n' "$TEST_CMD" >&2
if ! eval "$TEST_CMD" >/dev/null 2>&1; then
  die "baseline is RED before mutating. KILLED/SURVIVED would be meaningless.
  Make '$TEST_CMD' pass first."
fi

ANCHOR="$ANCHOR" REPLACEMENT="$REPLACEMENT" python3 -c '
import os,sys
p=sys.argv[1]; a=os.environ["ANCHOR"]; r=os.environ["REPLACEMENT"]
s=open(p,encoding="utf-8").read()
n=s.count(a)
if n==0: sys.exit("anchor vanished between count and write")
open(p,"w",encoding="utf-8").write(s.replace(a,r))
sys.stderr.write("mutate-check: applied %d substitution(s)\n" % n)' "$FILE" || die "mutation failed to apply"

printf 'mutate-check: mutant — %s\n' "$TEST_CMD" >&2
if eval "$TEST_CMD" >/dev/null 2>&1; then
  printf 'SURVIVED  %s  (anchor x%s)\n' "$FILE" "$EXPECTED"
  printf '  The suite still passes with the defect present. The test does not\n'
  printf '  detect what it claims to. Restored.\n'
  exit 1
fi
printf 'KILLED    %s  (anchor x%s)\n' "$FILE" "$EXPECTED"
exit 0
