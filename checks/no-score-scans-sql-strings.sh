#!/usr/bin/env bash
# checks/no-score-scans-sql-strings.sh — runnable directly.
#
# Ratchet check for review-round-1's HIGH against scripts/check-no-score.sh (FR-015).
#
# The defect. That guard stripped OCaml comments with an awk scanner that had no notion of a
# string literal, so `count(*)` inside a SQL literal — bin/arch_mutants/arch_mutants.ml:1024
# holds one — opened a phantom comment that never closed. Measured end-of-file depth was 3
# and 1288 of 2215 lines were stripped to nothing before anything was scanned. Injecting
# `Printf.printf "  score %d%% ..."` past that point — a literal %% AND the word `score` on
# an output path, the two hits the guard's own header names — produced exit 0 and
# "PASS — 0 offending site(s)".
#
# What this pins. On a fixture holding a SQL string with `count(*)` FOLLOWED by a scoring
# printf, check-no-score.sh must exit 1. A scanner that lets the string open a comment cannot
# see anything after it and exits 0.
#
# Exit: 0 = the guard sees past the SQL literal; 1 = it does not (the bug is back);
#       >=2 = setup error, never conflated with 0/1.
set -uo pipefail

here="$(cd "$(dirname "$0")" && pwd -P)"
guard="$here/../scripts/check-no-score.sh"
[ -x "$guard" ] || { echo "no-score-scans-sql-strings: $guard is not executable" >&2; exit 2; }

work="$(mktemp -d "${TMPDIR:-/tmp}/no-score-sql.XXXXXX")" || { echo "no-score-scans-sql-strings: mktemp failed" >&2; exit 2; }
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/src" || { echo "no-score-scans-sql-strings: cannot create fixture dir" >&2; exit 2; }

cat > "$work/src/fixture.ml" <<'ML'
(* A SQL literal carrying an OCaml comment opener inside a string. It is a string, not a
   comment, and nothing after it may be swallowed. *)
let prior_rows t =
  Arch_db.rows t
    "SELECT m.file_path, (SELECT count(*) FROM mutant_kills k WHERE k.mutant_id = m.id) \
     FROM mutants m ORDER BY m.id"
    ()

(* The offence, placed AFTER the literal above so only a scanner that survives it can see. *)
let publish killed attempted =
  Printf.printf "  • score %d%% of %d outcomes\n" killed attempted
ML
[ -s "$work/src/fixture.ml" ] || { echo "no-score-scans-sql-strings: fixture was not written" >&2; exit 2; }
grep -q 'count(\*)' "$work/src/fixture.ml" || { echo "no-score-scans-sql-strings: fixture lost its count(*) — it would prove nothing" >&2; exit 2; }
grep -q '%%' "$work/src/fixture.ml" || { echo "no-score-scans-sql-strings: fixture lost its %% — it would prove nothing" >&2; exit 2; }

out="$("$guard" "$work/src" 2>&1)"; code=$?
if [ "$code" -eq 1 ] && printf '%s' "$out" | grep -q 'a literal percent sign'; then
  echo "no-score-scans-sql-strings: PASS — the guard scanned past the SQL literal and named the scoring printf."
  exit 0
fi
echo "no-score-scans-sql-strings: FAIL — expected exit 1 naming the percent sign; got exit $code" >&2
printf '%s\n' "$out" | sed 's/^/  | /' >&2
echo "  A '(*' inside a string literal is being read as a comment opener, so everything after" >&2
echo "  the SQL literal is stripped and never scanned." >&2
exit 1
