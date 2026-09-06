#!/usr/bin/env bash
# checks/tree-boundary-refusal.sh — runnable directly. CHECK-26 / AC-24 / FR-030.
#
# The ratchet for `scripts/check-binary-provenance.sh`. That script probes the two ancestor
# walks from the ROOT of a nested inner tree. This one probes the three things it cannot see,
# each of which is a way the refusal can be implemented wrongly and still pass it:
#
#   PROBE 1 — depth. The driver invoked from a SUBDIRECTORY of the inner tree. A guard that
#             compares the resolved path against the working DIRECTORY rather than the working
#             TREE refuses here for the wrong reason, or (if it compares prefixes loosely)
#             fails to refuse at all. The boundary must be the git toplevel.
#
#   PROBE 2 — the exemption. `ARCH_MUTANTS_WRAPPER` naming an existing path OUTSIDE the tree
#             must still be honoured. FR-030 exempts it on purpose: there the operator named
#             the path. A guard that refuses this has broken every harness that points the
#             driver at a binary outside its own tree deliberately — this repo's own tezt
#             suite among them.
#
#   PROBE 3 — the negative. A wrapper INSIDE the tree must be accepted. Without this, "refuse
#             everything" passes both check-binary-provenance.sh probes and probe 1, and the
#             guard would be indistinguishable from a tool that no longer works.
#
# Probes 2 and 3 are the half that matters most here: a refusal is easy, a refusal that fires
# exactly when it should is not, and only 2 and 3 can tell them apart.
#
# Exit: 0 = the boundary refusal fires from a subdirectory and nowhere it should not;
#       1 = an assertion fired; >=2 = harness error.
set -uo pipefail

here="$(cd "$(dirname "$0")" && pwd -P)"
repo="$(cd "$here/.." && pwd -P)"
DRIVER="$repo/_build/default/bin/arch_mutants/arch_mutants.exe"

fatal() { echo "tree-boundary-refusal: $*" >&2; exit 2; }
command -v git >/dev/null 2>&1     || fatal "git is required"
command -v sqlite3 >/dev/null 2>&1 || fatal "sqlite3 is required"
[ -x "$DRIVER" ] || fatal "$DRIVER is not built — run 'dune build' first. Nothing was checked."
SCHEMA="$repo/architecture-schema.sql"; MIGRATION="$repo/mutants-schema-migration.sql"
[ -f "$SCHEMA" ] && [ -f "$MIGRATION" ] || fatal "the schema files are missing"

W="$(mktemp -d "${TMPDIR:-/tmp}/tree-boundary.XXXXXX")" || fatal "mktemp failed"
trap 'rm -rf "$W"' EXIT

# An inner tree that is its own git repository, with the minimum the driver needs to reach
# wrapper resolution: a valid empty index, a plan, an engine stub and a test-command stub.
make_inner() {
  local inner="$1"
  mkdir -p "$inner" || return 1
  (
    cd "$inner" || exit 1
    git init -q . >/dev/null 2>&1 || exit 1
    git config user.email check@tree.boundary || exit 1
    git config user.name tree-boundary || exit 1
    sqlite3 t.db < "$SCHEMA" || exit 1
    sqlite3 t.db < "$MIGRATION" || exit 1
    printf '#!/bin/sh\nexit 0\n' > engine.sh
    printf '#!/bin/sh\nexit 0\n' > tests.sh
    chmod +x engine.sh tests.sh
    printf '{"id":"1","file":"a.ml","line":1}\n' > cat.ndjson
    echo r0 > a.txt
    git add -A >/dev/null 2>&1 || exit 1
    git commit -qm r0 >/dev/null 2>&1 || exit 1
    "$DRIVER" plan t.db --format json > plan.json || exit 1
  ) || return 1
}

fails=0
# $1 label, $2 cwd, $3 expected exit, $4 substring that must appear ("" = must NOT contain
# the refusal), then the argv. Paths in the fixture are relative to the inner tree's root.
run_probe() {
  local label="$1" cwd="$2" want="$3" needle="$4"; shift 4
  local out code
  out="$(cd "$cwd" && env -u ARCH_IMPACT -u ARCH_MUTANTS "$@" 2>&1)"; code=$?
  local ok=1
  [ "$code" -eq "$want" ] || ok=0
  if [ -n "$needle" ]; then
    printf '%s' "$out" | grep -qF "$needle" || ok=0
  else
    printf '%s' "$out" | grep -q "OUTSIDE the working tree" && ok=0
  fi
  if [ "$ok" -eq 1 ]; then
    echo "  ✓ $label — exit $code${needle:+, named the outside path}"
  else
    echo "  ✗ $label — expected exit $want${needle:+ naming $needle}; got exit $code"
    printf '%s\n' "$out" | sed -e 's/^/      | /' -e '10q'
    fails=$((fails + 1))
  fi
}

# ---- PROBE 1: refuses from a SUBDIRECTORY of the inner tree ----------------------------
OUT1="$W/p1/outer"
mkdir -p "$OUT1/scripts" || fatal "probe 1: cannot lay out the outer tree"
printf '#!/bin/sh\nexit 0\n' > "$OUT1/scripts/mutaml-wrapper.sh"
chmod +x "$OUT1/scripts/mutaml-wrapper.sh"
make_inner "$OUT1/inner" || fatal "probe 1: could not build the inner tree"
mkdir -p "$OUT1/inner/sub/deeper" || fatal "probe 1: cannot create the subdirectory"
[ ! -e "$OUT1/inner/scripts" ] || fatal "probe 1: the inner tree must NOT hold a wrapper"
run_probe "a subdirectory of the inner tree still refuses the outer wrapper" \
  "$OUT1/inner/sub/deeper" 1 "$OUT1/scripts/mutaml-wrapper.sh" \
  "$DRIVER" run ../../t.db --plan ../../plan.json --engine ../../engine.sh \
  --test-cmd ../../tests.sh --catalogue ../../cat.ndjson

# ---- PROBE 2: an existing ARCH_MUTANTS_WRAPPER outside the tree is EXEMPT --------------
# Same fixture, same cwd, the only difference being that the operator named the path. If this
# refuses, the guard has broken the exemption FR-030 states, and with it this repo's own
# test suite, which points the driver at exactly such a path.
out2="$(cd "$OUT1/inner/sub/deeper" && env -u ARCH_IMPACT -u ARCH_MUTANTS \
  ARCH_MUTANTS_WRAPPER="$OUT1/scripts/mutaml-wrapper.sh" \
  "$DRIVER" run ../../t.db --plan ../../plan.json --engine ../../engine.sh \
  --test-cmd ../../tests.sh --catalogue ../../cat.ndjson 2>&1)"; code2=$?
if [ "$code2" -ne 1 ] && ! printf '%s' "$out2" | grep -q "OUTSIDE the working tree"; then
  echo "  ✓ an explicit ARCH_MUTANTS_WRAPPER outside the tree is honoured — exit $code2"
else
  echo "  ✗ an explicit ARCH_MUTANTS_WRAPPER outside the tree was REFUSED (exit $code2)"
  echo "      FR-030 exempts an override naming an existing path: there the operator chose it."
  printf '%s\n' "$out2" | sed -e 's/^/      | /' -e '10q'
  fails=$((fails + 1))
fi

# ---- PROBE 3: a wrapper INSIDE the tree is accepted -------------------------------------
OUT3="$W/p3/outer"
mkdir -p "$OUT3/scripts" || fatal "probe 3: cannot lay out the outer tree"
printf '#!/bin/sh\nexit 0\n' > "$OUT3/scripts/mutaml-wrapper.sh"
chmod +x "$OUT3/scripts/mutaml-wrapper.sh"
make_inner "$OUT3/inner" || fatal "probe 3: could not build the inner tree"
mkdir -p "$OUT3/inner/scripts" "$OUT3/inner/sub" || fatal "probe 3: cannot create the inner scripts dir"
printf '#!/bin/sh\nexit 0\n' > "$OUT3/inner/scripts/mutaml-wrapper.sh"
chmod +x "$OUT3/inner/scripts/mutaml-wrapper.sh"
run_probe "a wrapper inside the tree is accepted, from a subdirectory" \
  "$OUT3/inner/sub" 0 "" \
  "$DRIVER" run ../t.db --plan ../plan.json --engine ../engine.sh \
  --test-cmd ../tests.sh --catalogue ../cat.ndjson

echo
if [ "$fails" -gt 0 ]; then
  echo "tree-boundary-refusal: FAIL — $fails of 3 probes." >&2
  echo "  FR-030's boundary is the WORKING TREE (git toplevel), it is not the working directory," >&2
  echo "  and it does not apply to a path the operator named. Getting any of those three wrong" >&2
  echo "  still passes scripts/check-binary-provenance.sh." >&2
  exit 1
fi
echo "tree-boundary-refusal: PASS — 3 of 3 probes. What would have made this non-zero: a guard"
echo "  anchored on the working DIRECTORY instead of the tree (probe 1), one that refuses an"
echo "  operator-named override (probe 2), or one that simply refuses everything (probe 3) — none"
echo "  of which scripts/check-binary-provenance.sh can distinguish from a correct implementation."
exit 0
