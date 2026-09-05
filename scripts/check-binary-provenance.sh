#!/usr/bin/env bash
# check-binary-provenance.sh — CHECK-15 / AC-24 / FR-030.
#
# The campaign must REFUSE (exit 1) when a binary or script it resolves lies OUTSIDE the
# working tree it was invoked from.
#
# Why. bin/arch_mutants/arch_mutants.ml's `locate_wrapper` (:787) and `locate_impact` (:875)
# both walk ancestor directories from the working directory. A worktree placed INSIDE another
# checkout therefore runs the PARENT checkout's wrapper and the PARENT checkout's arch-impact
# — silently, with plausible output. For a mutation campaign that is the worst possible
# failure: the parent's binary is unmutated, so every mutant survives and the report becomes a
# page of false test gaps that reads exactly like a real finding. That is issue #77.
#
# WHY THIS SCRIPT WAS REWRITTEN, on the record. Its previous version probed four hardcoded
# `_build` paths from the tree root and never invoked arch-mutants at all. It therefore exited
# 0 on a tree where the guard it claims to enforce had never been written — and it had never
# been written: `locate_wrapper` and `locate_impact` still walk ancestors with no tree-boundary
# check. A check that cannot observe the absence of its own subject is not a check. This
# version constructs the nested-checkout fixture and runs the REAL driver inside it.
#
# What it asserts, twice, each against its own fixture:
#   PROBE A — the wrapper: an inner tree with no scripts/mutaml-wrapper.sh, inside an outer
#             directory that has one. `arch-mutants run` must refuse.
#   PROBE B — the binary: an inner tree with no _build, inside an outer directory whose
#             _build/default/bin/arch_impact/arch_impact.exe the ancestor walk reaches.
#             `arch-mutants run --diff` must refuse.
# In both cases the assertion is exit 1 AND a message naming the outside path, because an
# exit code alone cannot tell a fired guard from an unrelated failure.
#
# An environment override (ARCH_MUTANTS_WRAPPER, ARCH_IMPACT) naming a path that EXISTS is
# deliberately not probed: FR-030 exempts it, because there the operator named the path.
#
# Usage:   scripts/check-binary-provenance.sh [root]
#          root defaults to the git toplevel of the current directory.
# Exit:    0 = the campaign refuses in both nested-checkout fixtures.
#          1 = at least one fixture ran the outside artefact instead of refusing.
#          2 = harness error (no tree, no sqlite3, no built driver, fixture setup failed).

set -uo pipefail

ROOT="${1:-$(git rev-parse --show-toplevel 2>/dev/null)}"
[ -n "$ROOT" ] && [ -d "$ROOT" ] || { echo "check-binary-provenance: cannot determine tree root" >&2; exit 2; }
ROOT="$(cd "$ROOT" && pwd -P)"

fatal() { echo "check-binary-provenance: $*" >&2; exit 2; }

command -v git >/dev/null 2>&1     || fatal "git is required"
command -v sqlite3 >/dev/null 2>&1 || fatal "sqlite3 is required to build the fixture database"

DRIVER="$ROOT/_build/default/bin/arch_mutants/arch_mutants.exe"
[ -x "$DRIVER" ] || fatal "$DRIVER is not built — run 'dune build' first. Nothing was checked."
# The driver under test must be THIS tree's. Checking another checkout's binary would be the
# very confusion this script exists to detect.
case "$(cd "$(dirname "$DRIVER")" && pwd -P)" in
  "$ROOT"/*) : ;;
  *) fatal "the driver resolved outside $ROOT — refusing to test another checkout's binary" ;;
esac

SCHEMA="$ROOT/architecture-schema.sql"
MIGRATION="$ROOT/mutants-schema-migration.sql"
[ -f "$SCHEMA" ] || fatal "missing $SCHEMA"
[ -f "$MIGRATION" ] || fatal "missing $MIGRATION"

WORK="$(mktemp -d "${TMPDIR:-/tmp}/check-binary-provenance.XXXXXX")" || fatal "cannot create a fixture directory"
cleanup() { rm -rf "$WORK"; }
trap cleanup EXIT

# Build an inner tree: its own git repository (so the working tree is the INNER one), an empty
# but valid index database, a plan, an engine stub and a test-command stub. Everything the
# driver needs to reach the resolution step and nothing more.
make_inner() {
  local inner="$1" ncommits="${2:-1}"
  mkdir -p "$inner" || return 1
  (
    cd "$inner" || exit 1
    git init -q . >/dev/null 2>&1 || exit 1
    git config user.email check@binary.provenance || exit 1
    git config user.name check-binary-provenance || exit 1
    sqlite3 t.db < "$SCHEMA" || exit 1
    sqlite3 t.db < "$MIGRATION" || exit 1
    printf '#!/bin/sh\nexit 0\n' > engine.sh
    printf '#!/bin/sh\nexit 0\n' > tests.sh
    chmod +x engine.sh tests.sh
    printf '{"id":"1","file":"a.ml","line":1}\n' > cat.ndjson
    local i=0
    while [ "$i" -lt "$ncommits" ]; do
      echo "revision $i" > a.txt
      git add -A >/dev/null 2>&1 || exit 1
      git commit -qm "r$i" >/dev/null 2>&1 || exit 1
      i=$((i + 1))
    done
    "$DRIVER" plan t.db --format json > plan.json || exit 1
  ) || return 1
  return 0
}

fails=0
probes=0

# Run the driver inside $inner with the ancestor-walk overrides cleared, and judge the refusal.
# $outside is the path the guard must name; finding it in the output is what distinguishes a
# fired guard from an unrelated exit 1.
judge() {
  local label="$1" inner="$2" outside="$3"; shift 3
  local out code
  probes=$((probes + 1))
  out="$(cd "$inner" && env -u ARCH_IMPACT -u ARCH_MUTANTS_WRAPPER -u ARCH_MUTANTS "$DRIVER" "$@" 2>&1)"
  code=$?
  if [ "$code" -eq 1 ] && printf '%s' "$out" | grep -qF "$outside"; then
    echo "  ✓ $label — refused (exit 1) and named $outside"
    return 0
  fi
  fails=$((fails + 1))
  echo "  ✗ $label — expected exit 1 naming $outside; got exit $code"
  if [ "$code" -eq 1 ]; then
    echo "      It exited 1 but never named the outside artefact, so the refusal cannot be"
    echo "      attributed to the tree boundary."
  else
    echo "      The campaign did NOT refuse. It resolved an artefact from outside the working"
    echo "      tree and carried on — issue #77's mechanism, live."
  fi
  printf '%s\n' "$out" | sed -e 's/^/      | /' -e '12q'
  return 1
}

echo "check-binary-provenance: tree root $ROOT"
echo "check-binary-provenance: driver     $DRIVER"
echo "check-binary-provenance: fixtures   $WORK"
echo

# ---- PROBE A: the wrapper, reached by the ancestor walk ---------------------------------
OUTER_A="$WORK/a/outer"
mkdir -p "$OUTER_A/scripts" || fatal "fixture A: cannot create $OUTER_A/scripts"
printf '#!/bin/sh\nexit 0\n' > "$OUTER_A/scripts/mutaml-wrapper.sh"
chmod +x "$OUTER_A/scripts/mutaml-wrapper.sh"
make_inner "$OUTER_A/inner" 1 || fatal "fixture A: could not build the inner tree"
[ ! -e "$OUTER_A/inner/scripts" ] || fatal "fixture A: the inner tree must NOT hold a wrapper"
judge "wrapper via ancestor walk" "$OUTER_A/inner" "$OUTER_A/scripts/mutaml-wrapper.sh" \
  run t.db --plan plan.json --engine ./engine.sh --test-cmd ./tests.sh --catalogue cat.ndjson

# ---- PROBE B: arch-impact, reached through an ancestor _build ---------------------------
OUTER_B="$WORK/b/outer"
mkdir -p "$OUTER_B/_build/default/bin/arch_impact" || fatal "fixture B: cannot create the ancestor _build"
printf '#!/bin/sh\nexit 3\n' > "$OUTER_B/_build/default/bin/arch_impact/arch_impact.exe"
chmod +x "$OUTER_B/_build/default/bin/arch_impact/arch_impact.exe"
make_inner "$OUTER_B/inner" 2 || fatal "fixture B: could not build the inner tree"
# The inner tree gets its OWN wrapper, so probe B fails on the binary and on nothing else.
mkdir -p "$OUTER_B/inner/scripts" || fatal "fixture B: cannot create the inner scripts dir"
printf '#!/bin/sh\nexit 0\n' > "$OUTER_B/inner/scripts/mutaml-wrapper.sh"
chmod +x "$OUTER_B/inner/scripts/mutaml-wrapper.sh"
[ ! -e "$OUTER_B/inner/_build" ] || fatal "fixture B: the inner tree must NOT hold a _build"
judge "arch-impact via ancestor _build" "$OUTER_B/inner" \
  "$OUTER_B/_build/default/bin/arch_impact/arch_impact.exe" \
  run t.db --plan plan.json --engine ./engine.sh --test-cmd ./tests.sh --catalogue cat.ndjson \
  --diff 'HEAD~1..HEAD' --repo "$OUTER_B/inner"

echo
if [ "$fails" -gt 0 ]; then
  echo "check-binary-provenance: $fails of $probes nested-checkout fixture(s) did not make the campaign refuse." >&2
  echo "  FR-030 is not implemented: locate_wrapper (arch_mutants.ml:787) and locate_impact (:875)" >&2
  echo "  walk ancestor directories with no tree-boundary check." >&2
  exit 1
fi
# Never publish a bare zero: say what would have made it non-zero.
echo "check-binary-provenance: $probes of $probes nested-checkout fixtures made the campaign refuse (exit 1)."
echo "  A failure here would mean the driver resolved the OUTER directory's wrapper or arch-impact"
echo "  and ran the campaign anyway — issue #77, where the parent checkout's unmutated binary makes"
echo "  every mutant survive and the report reads as a page of real test gaps."
exit 0
