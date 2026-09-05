#!/usr/bin/env bash
# check-quint-red.sh — negative tests for the Quint invariants of specs/mutation-campaign-313.qnt
#
# A green model check proves nothing on its own: an invariant that cannot fail is a gate that
# cannot fail. This script injects one defect at a time into a COPY of the model and requires
# that the named invariant goes red. If any mutation stays green, the corresponding invariant
# is vacuous and this script exits 1.
#
# Contract: no invariant lands in the model without its mutant here.
# Exit: 0 = every mutation was caught. 1 = at least one mutation survived. 2 = harness error.
set -uo pipefail

SPEC="${1:-specs/mutation-campaign-313.qnt}"
command -v quint >/dev/null 2>&1 || { echo "check-quint-red: quint not installed" >&2; exit 2; }
[ -f "$SPEC" ] || { echo "check-quint-red: $SPEC not found" >&2; exit 2; }

TMP=$(mktemp -d) || exit 2
trap 'rm -rf "$TMP"' EXIT
fails=0; total=0

# name | invariant it must break | sed expression injecting the defect
run_mutation() {
  local name="$1" inv="$2" sedexpr="$3"
  total=$((total+1))
  local f="$TMP/mut.qnt"
  sed "$sedexpr" "$SPEC" > "$f"
  if cmp -s "$f" "$SPEC"; then
    echo "  ✗ $name — the sed matched NOTHING, so this mutation tested nothing"
    fails=$((fails+1)); return
  fi
  local out
  out=$(quint run "$f" --invariant="$inv" --max-samples=20000 --max-steps=12 2>&1)
  if printf '%s' "$out" | grep -q "No violation found"; then
    echo "  ✗ $name — SURVIVED: $inv stayed green with the defect injected (vacuous invariant)"
    fails=$((fails+1))
  elif printf '%s' "$out" | grep -qi "violation\|error:"; then
    echo "  ✓ $name — caught by $inv"
  else
    echo "  ✗ $name — quint produced neither a violation nor a green result:"
    printf '%s\n' "$out" | tail -3 | sed 's/^/      /'
    fails=$((fails+1))
  fi
}

echo "check-quint-red: injecting defects into a copy of $SPEC"

run_mutation "a dynamic source that REMOVES a test from the selection" \
  "p2ExecutedNeverShrinks" \
  's/executed\.union(Set(t))/executed.exclude(Set(t))/'

run_mutation "provenance always claims a proved superset" \
  "p1SurvivorNeedsProvedSuperset" \
  's/if (not(contract)) "no_contract"/if (false) "no_contract"/'

run_mutation "attribution written for any outcome, from any executed set" \
  "p3AttributionNeverInvented" \
  's/((s == "KILLED" or s == "TIMEOUT") and (executed.size() == 1 or named))/true/'

run_mutation "a TIMEOUT is no longer treated as a kill" \
  "p1KillIsNeverWeakened" \
  's/if (status == "KILLED" or status == "TIMEOUT") "KILLED"/if (status == "KILLED") "KILLED"/'

run_mutation "PENDING becomes a storable engine status" \
  "p3PendingIsNeverStored" \
  's/oneOf(Set("KILLED", "SURVIVED", "TIMEOUT", "ERROR"))/oneOf(Set("KILLED", "SURVIVED", "TIMEOUT", "ERROR", "PENDING"))/'

echo
if [ "$fails" -eq 0 ]; then
  echo "check-quint-red: $total/$total mutations caught — every invariant can fail."
  exit 0
else
  echo "check-quint-red: $fails of $total mutations SURVIVED — those invariants are vacuous."
  exit 1
fi
