#!/usr/bin/env bash
# checks/prior-status-read-with-its-provenance.sh — runnable directly. CHECK-28 / FR-013, FR-018.
#
# The defect. `prior_mutants` projected `r.engine_status` with NO `r.selection_provenance`
# beside it and collapsed the row to a boolean `pk_killed`. `--diff`'s deleted-test rule then
# read that boolean: a mutant that was not "killed" was treated as a PROVEN non-kill and left
# off the un-recheckable list. But a SURVIVED recorded under a ⊤-BOUNDED selection publishes
# as UNKNOWN everywhere else in this tool — the tests that reach it may never have run at all —
# so it proves nothing about whether the deleted test was the one catching it. The pairing that
# `MDb.outcome` exists to make impossible was enforced in `verdict` and not here.
#
# The fixture, three prior mutants under one completed campaign, so both polarities are live:
#   lib/x.ml:15  KILLED  / proved_superset, ONE kill row naming a test the index no longer
#                carries          → RE-CHECKED. This is also what makes `deleted_tests`
#                non-empty; without it the two lists below are empty and everything is vacuous.
#   lib/y.ml:35  SURVIVED / top_bounded, NO kill row
#                                 → UN-RECHECKABLE. This is the finding.
#   lib/z.ml:55  SURVIVED / proved_superset, NO kill row
#                                 → NOT un-recheckable. This is the negative control: every
#                                   reaching test provably ran and none killed it, so no
#                                   deleted test can have been catching it. Without this row,
#                                   "call every survivor un-recheckable" would pass.
#
# The range edits README.md only, so rules 1 and 2 select nothing and everything below arrived
# through the deleted-test rule alone.
#
# Exit: 0 = a bounded SURVIVED is not read as a proven non-kill;
#       1 = an assertion fired; >=2 = harness error.
set -uo pipefail

here="$(cd "$(dirname "$0")" && pwd -P)"
repo="$(cd "$here/.." && pwd -P)"
B="$repo/_build/default/bin"

fatal() { echo "prior-status-provenance: $*" >&2; exit 2; }
command -v sqlite3 >/dev/null 2>&1 || fatal "sqlite3 is required"
command -v git >/dev/null 2>&1 || fatal "git is required"
[ -x "$repo/scripts/mutaml-wrapper.sh" ] || fatal "the wrapper is missing"
for exe in arch_load/arch_load.exe arch_mutants/arch_mutants.exe arch_impact/arch_impact.exe; do
  [ -x "$B/$exe" ] || fatal "$B/$exe is not built — run 'dune build' first. Nothing was checked."
done

W="$(mktemp -d "${TMPDIR:-/tmp}/prior-status.XXXXXX")" || fatal "mktemp failed"
trap 'rm -rf "$W"' EXIT

fails=0
assert_eq() {
  if [ "$2" = "$3" ]; then echo "  ✓ $1 — $3"
  else echo "  ✗ $1 — expected $2, got $3"; fails=$((fails + 1)); fi
}

# ---- the indexed project, and a git history whose range touches no indexed function -------
proj="$W/proj"
mkdir -p "$proj/lib" "$proj/test" || fatal "cannot create the project tree"
for f in lib/x.ml lib/y.ml lib/z.ml test/alpha_test.ml test/beta_test.ml; do
  awk 'BEGIN{for(i=1;i<=70;i++) print "let l" i " = " i}' > "$proj/$f"
done
echo readme > "$proj/README.md"
( cd "$proj" && git init -q && git config user.email t@t && git config user.name t \
    && git add -A && git commit -qm init ) >/dev/null 2>&1 || fatal "git init failed"
echo "readme, revised" > "$proj/README.md"
( cd "$proj" && git add -A && git commit -qm docs ) >/dev/null 2>&1 || fatal "git commit failed"

cat > "$W/stream.ndjson" <<'S'
{"type":"function","name":"t_alpha","file_path":"test/alpha_test.ml","line_start":1,"line_end":5}
{"type":"function","name":"t_gamma","file_path":"test/alpha_test.ml","line_start":7,"line_end":9}
{"type":"function","name":"t_beta","file_path":"test/beta_test.ml","line_start":1,"line_end":5}
{"type":"function","name":"covered","file_path":"lib/x.ml","line_start":10,"line_end":20}
{"type":"function","name":"other","file_path":"lib/y.ml","line_start":30,"line_end":40}
{"type":"function","name":"shared","file_path":"lib/z.ml","line_start":50,"line_end":60}
{"type":"call","caller_name":"t_alpha","caller_file":"test/alpha_test.ml","callee_name":"covered","callee_file":"lib/x.ml","call_site":"test/alpha_test.ml:2","kind":"MUST"}
{"type":"call","caller_name":"t_gamma","caller_file":"test/alpha_test.ml","callee_name":"other","callee_file":"lib/y.ml","call_site":"test/alpha_test.ml:8","kind":"MUST"}
{"type":"call","caller_name":"t_beta","caller_file":"test/beta_test.ml","callee_name":"shared","callee_file":"lib/z.ml","call_site":"test/beta_test.ml:2","kind":"MUST"}
S
"$B/arch_load/arch_load.exe" "$W/t.db" < "$W/stream.ndjson" >/dev/null 2>&1 || fatal "arch-load failed"
sqlite3 "$W/t.db" < "$repo/mutants-schema-migration.sql" || fatal "the migration would not apply"

sqlite3 "$W/t.db" <<'SQL' || fatal "seeding the prior campaign failed"
INSERT INTO mutants(file_path,line,col_start,col_end,replacement,source_hash,function_name)
  VALUES ('lib/x.ml',15,3,9,'true','prior-x','covered'),
         ('lib/y.ml',35,1,4,'false','prior-y','other'),
         ('lib/z.ml',55,2,7,'0','prior-z','shared');
INSERT INTO mutant_campaigns(engine,engine_path,test_runner_path,granularity,completed_at)
  VALUES ('stub','/bin/true','/bin/true','case','2026-09-05T00:00:00Z');
INSERT INTO mutant_runs(campaign_id,mutant_id,engine_status,selection_provenance,
                        intended_tests,executed_tests)
  SELECT 1, id, 'KILLED', 'proved_superset', 1, 1 FROM mutants WHERE file_path='lib/x.ml';
INSERT INTO mutant_runs(campaign_id,mutant_id,engine_status,selection_provenance,
                        intended_tests,executed_tests)
  SELECT 1, id, 'SURVIVED', 'top_bounded', 1, 1 FROM mutants WHERE file_path='lib/y.ml';
INSERT INTO mutant_runs(campaign_id,mutant_id,engine_status,selection_provenance,
                        intended_tests,executed_tests)
  SELECT 1, id, 'SURVIVED', 'proved_superset', 1, 1 FROM mutants WHERE file_path='lib/z.ml';
INSERT INTO mutant_kills(campaign_id,mutant_id,test_name,attribution)
  SELECT 1, id, 't_deleted', 'singleton_executed_set' FROM mutants WHERE file_path='lib/x.ml';
SQL

# PRECONDITION, asserted against the database rather than against the tool under test: the two
# SURVIVED rows must genuinely differ in provenance and both must carry zero kill rows. If the
# seed ever stopped producing that contrast, every assertion below would pass vacuously.
assert_eq "the fixture really holds one bounded and one proved survivor" "top_bounded|proved_superset" \
  "$(sqlite3 "$W/t.db" "SELECT group_concat(r.selection_provenance,'|') FROM mutant_runs r \
     JOIN mutants m ON m.id=r.mutant_id WHERE r.engine_status='SURVIVED' ORDER BY m.file_path")"
assert_eq "neither survivor carries a kill row" "0" \
  "$(sqlite3 "$W/t.db" "SELECT count(*) FROM mutant_kills k JOIN mutant_runs r ON \
     r.mutant_id=k.mutant_id WHERE r.engine_status='SURVIVED'")"

# ---- the run whose scope we read ---------------------------------------------------------
cat > "$W/cat.ndjson" <<'C'
{"id":"m1","file":"lib/x.ml","line":15,"col_start":3,"col_end":9,"replacement":"true"}
{"id":"m2","file":"lib/y.ml","line":35,"col_start":1,"col_end":4,"replacement":"false"}
{"id":"m3","file":"lib/z.ml","line":55,"col_start":2,"col_end":7,"replacement":"0"}
C
cat > "$W/report.ndjson" <<'R'
{"file":"lib/x.ml","line":15,"status":"SURVIVED","id":"m1"}
R
"$B/arch_mutants/arch_mutants.exe" plan "$W/t.db" --tests 'file:test/**' --format json \
  > "$W/plan.json" || fatal "arch-mutants plan failed"
printf '#!/bin/sh\nexit 0\n' > "$W/engine.sh"; chmod +x "$W/engine.sh"

out="$(ARCH_IMPACT="$B/arch_impact/arch_impact.exe" ARCH_MUTANTS_WORKDIR="$W/work" \
  ARCH_MUTANTS_WRAPPER="$repo/scripts/mutaml-wrapper.sh" \
  "$B/arch_mutants/arch_mutants.exe" run "$W/t.db" --plan "$W/plan.json" \
  --engine "$W/engine.sh" --test-cmd true --catalogue "$W/cat.ndjson" \
  --report "$W/report.ndjson" --tests 'file:test/**' --repo "$proj" \
  --diff 'HEAD~1..HEAD' --format json 2>"$W/err")"
printf '%s' "$out" > "$W/run.json"
[ -s "$W/run.json" ] || { echo "prior-status-provenance: the run produced no JSON:" >&2
                          sed 's/^/  | /' "$W/err" >&2; exit 2; }

# The scope's lists, flattened to "file:line" (or to the plain strings) in document order.
cat > "$W/scope.py" <<'PYEOF'
import json, sys
d = json.load(open(sys.argv[1]))["diff_scope"]
v = d[sys.argv[2]]
if v and isinstance(v[0], dict):
    print(",".join("%s:%d" % (x["file"], x["line"]) for x in v))
else:
    print(",".join(map(str, v)))
PYEOF
scope() {
  python3 "$W/scope.py" "$W/run.json" "$1" \
    || { echo "prior-status-provenance: the run JSON carries no diff_scope.$1" >&2; exit 2; }
}

# Rules 1 and 2 must contribute nothing, or a hit below could have come from either.
assert_eq "a documentation-only range touches no indexed function" "" "$(scope touched_functions)"
assert_eq "only the absent test counts as deleted" "t_deleted" "$(scope deleted_tests)"

assert_eq "the mutant a deleted test killed ALONE is re-selected" "lib/x.ml:15" \
  "$(scope rechecked_for_deleted_tests)"
# THE FINDING. A SURVIVED under a ⊤-bounded selection publishes as UNKNOWN; the reaching tests
# may never have run, so nothing says the deleted test was not the one catching it.
# THE NEGATIVE CONTROL, in the same assertion: lib/z.ml:55 is a SURVIVED under a PROVED
# superset and must NOT be listed — every reaching test ran and none killed it.
assert_eq "a ⊤-bounded survivor is UN-RECHECKABLE, a proved one is not" "lib/y.ml:35" \
  "$(scope unrecheckable)"

echo
if [ "$fails" -gt 0 ]; then
  echo "prior-status-provenance: FAIL — $fails assertion(s) fired." >&2
  echo "  A prior engine_status is being read without its selection_provenance, so a bounded" >&2
  echo "  SURVIVED is being treated as a proven non-kill." >&2
  exit 1
fi
echo "prior-status-provenance: PASS — the prior status travels with its provenance and the"
echo "  un-recheckable list is derived from the published verdict, not from a boolean."
exit 0
