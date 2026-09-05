#!/usr/bin/env bash
# checks/status-provenance-per-record.sh — runnable directly.
#
# Ratchet check for review-round-1's HIGH against scripts/check-status-provenance.sh
# (CHECK-7 / AC-10 / FR-013).
#
# The defect. That guard's header says it "checks the enclosing record, not the file". It did
# not: its depth guard opened a record only at bracket depth 0, so a nested `Assoc never
# started a record of its own and the whole outermost blob was judged as ONE. An inner record
# therefore inherited any selection_provenance key appearing anywhere in the outer one.
# Deleting the per-run record's provenance key at bin/arch_mutants/arch_mutants.ml:1584 —
# leaving that record emitting ("engine_status", …) with nothing beside it, the row a reader
# copies into a bug report and the exact case FR-013 exists for — produced exit 0 and
# "PASS — 0 offending emitter(s)".
#
# What this pins. On a fixture whose OUTER record carries the provenance and whose INNER
# record carries a lone engine_status, check-status-provenance.sh must exit 1 and must name
# the INNER record's line, not the outer one.
#
# Exit: 0 = each record is judged on its own keys; 1 = inheritance is back; >=2 = setup error.
set -uo pipefail

here="$(cd "$(dirname "$0")" && pwd -P)"
guard="$here/../scripts/check-status-provenance.sh"
[ -x "$guard" ] || { echo "status-provenance-per-record: $guard is not executable" >&2; exit 2; }

work="$(mktemp -d "${TMPDIR:-/tmp}/status-prov.XXXXXX")" || { echo "status-provenance-per-record: mktemp failed" >&2; exit 2; }
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/src" || { echo "status-provenance-per-record: cannot create fixture dir" >&2; exit 2; }

cat > "$work/src/fixture.ml" <<'ML'
(* The outer record names a provenance. The inner one does not, and must not inherit it. *)
let payload provenance runs =
  `Assoc
    [ ("campaign", `Int 1);
      ("selection_provenance", `String (MDb.provenance_to_string provenance));
      ("runs",
       `List
         (List.map
            (fun (m : mutant) ->
              `Assoc
                [ ("engine_mutant_id", `String m.id);
                  ("engine_status", `String (String.uppercase_ascii m.status)) ])
            runs)) ]
ML
# The inner `Assoc opens on line 11 of the fixture; a hit reported anywhere else would mean
# the guard found something other than what this check constructs.
inner_line=$(grep -n '`Assoc$' "$work/src/fixture.ml" | sed -n '2p' | cut -d: -f1)
[ -n "$inner_line" ] || { echo "status-provenance-per-record: fixture has no nested \`Assoc — it would prove nothing" >&2; exit 2; }

out="$("$guard" "$work/src" 2>&1)"; code=$?
if [ "$code" -eq 1 ] && printf '%s' "$out" | grep -q ":$inner_line: a JSON record carries a status without selection_provenance"; then
  echo "status-provenance-per-record: PASS — the inner record was judged on its own keys (line $inner_line)."
  exit 0
fi
echo "status-provenance-per-record: FAIL — expected exit 1 naming the inner record at line $inner_line; got exit $code" >&2
printf '%s\n' "$out" | sed 's/^/  | /' >&2
echo "  A nested record is inheriting the enclosing record's selection_provenance, which is" >&2
echo "  precisely the inheritance FR-013 forbids." >&2
exit 1
