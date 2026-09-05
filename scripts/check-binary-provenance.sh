#!/usr/bin/env bash
# check-binary-provenance.sh — refuse to trust a binary resolved OUTSIDE the working tree.
#
# Why this exists as a script and not as a paragraph in a brief.
# tezt/lib/arch_tezt.ml's `locate` walks ancestor directories from the working directory to find
# a binary. A worktree placed INSIDE another checkout, or one whose _build is incomplete, therefore
# runs the PARENT checkout's binary — silently, with plausible output. For a mutation campaign that
# is the worst possible failure: the parent's binary is unmutated, so every mutant survives and the
# report becomes a page of false test gaps that reads exactly like a real finding.
#
# A written warning does not prevent this. On 2026-09-05 an agent briefed specifically about this
# hazard worked in a worktree inside the checkout anyway — the warning was there and was not enough,
# because it was one paragraph inside a long brief. Hence a check that fails loudly.
#
# Usage:   scripts/check-binary-provenance.sh [root]
#          root defaults to the git toplevel of the current directory.
# Exit:    0 = every resolved binary lies inside the tree. 1 = at least one does not. 2 = harness error.

set -uo pipefail

ROOT="${1:-$(git rev-parse --show-toplevel 2>/dev/null)}"
[ -n "$ROOT" ] && [ -d "$ROOT" ] || { echo "check-binary-provenance: cannot determine tree root" >&2; exit 2; }
ROOT="$(cd "$ROOT" && pwd -P)"

# The binaries a campaign resolves, and the environment variable that overrides each. Names match
# tezt/lib/arch_tezt.ml's `locate ~env_var` convention.
BINARIES="ARCH_MUTANTS:bin/arch_mutants/arch_mutants.exe
ARCH_QUERY:bin/arch_query/arch_query.exe
ARCH_IMPACT:bin/arch_impact/arch_impact.exe
ARCH_COVERAGE:bin/arch_coverage/arch_coverage.exe"

fails=0; checked=0; found=0

# Reproduce locate's resolution order: the environment variable wins, then an upward walk.
resolve() {
  local var="$1" rel="$2" v d p
  v="$(printf '%s' "${!var-}")"
  if [ -n "$v" ]; then printf '%s' "$v"; return; fi
  d="$(pwd -P)"
  while :; do
    p="$d/_build/default/$rel"
    [ -f "$p" ] && { printf '%s' "$p"; return; }
    [ "$d" = "/" ] && return
    d="$(dirname "$d")"
  done
}

echo "check-binary-provenance: tree root $ROOT"
while IFS= read -r line; do
  var="${line%%:*}"; rel="${line#*:}"
  checked=$((checked+1))
  path="$(resolve "$var" "$rel")"
  if [ -z "$path" ]; then
    echo "  · $var — not resolvable from here (nothing built yet); nothing to trust, nothing to distrust"
    continue
  fi
  found=$((found+1))
  real="$(cd "$(dirname "$path")" 2>/dev/null && pwd -P)/$(basename "$path")"
  case "$real" in
    "$ROOT"/*) echo "  ✓ $var → ${real#"$ROOT"/}" ;;
    *) echo "  ✗ $var → $real"
       echo "      OUTSIDE the tree. A campaign run against this binary would report every mutant"
       echo "      as a survivor, because that binary is not the one being mutated."
       fails=$((fails+1)) ;;
  esac
done <<< "$BINARIES"

echo
if [ "$fails" -gt 0 ]; then
  echo "check-binary-provenance: $fails of $found resolved binaries lie outside $ROOT — refusing."
  exit 1
fi
# Never publish a bare zero: say what would have made it non-zero.
echo "check-binary-provenance: 0 of $found resolved binaries lie outside the tree ($checked probed)."
echo "  A non-zero count would mean a binary resolved through an ancestor directory — the case that"
echo "  arises when this tree sits inside another checkout, or when its own _build is incomplete."
exit 0
