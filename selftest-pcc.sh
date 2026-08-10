#!/usr/bin/env bash
# selftest-pcc.sh — the three pcc-* binaries scripts/pcc/{pcc-index,pcc-dossier,pcc-preflight}
# consumed by cabal-workflow-runner's proof-carrying-change workflow (see that repo's
# docs/proof-carrying-change.md, "The pcc-* convention"). Builds a small real OCaml fixture
# (real dune project, real git repo) and drives the three binaries as real subprocesses — no
# stubs — asserting:
#   1. pcc-index prints exactly one JSON object, no float, computed:true + a functions int
#   2. pcc-dossier writes a non-empty file to --out and exits 0 even when arch-rules --and--
#      arch-impact both report a non-clean verdict underneath
#   3. pcc-preflight exits 0/ok:true on a passing test suite, and (distinctly) exits nonzero/
#      ok:false on a failing one — the two fixtures differ only in the one assertion that fails,
#      so a binary that always reports "ok" cannot pass both
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
PCC="$HERE/scripts/pcc"
fails=0; note() { echo "FAIL: $*" >&2; fails=$((fails+1)); }
command -v python3 >/dev/null 2>&1 || { echo "selftest-pcc: python3 required" >&2; exit 2; }
command -v sqlite3 >/dev/null 2>&1 || { echo "selftest-pcc: sqlite3 required" >&2; exit 2; }
command -v dune >/dev/null 2>&1 || { echo "selftest-pcc: dune required" >&2; exit 2; }
[ -x "$HERE/arch-impact" ] || { echo "selftest-pcc: arch-impact not built — run: dune build" >&2; exit 2; }
[ -x "$HERE/_build/default/poc/decision-lint/bin/decision_lint.exe" ] \
  || { echo "selftest-pcc: decision_lint not built — run: dune build" >&2; exit 2; }

# pcc-index/pcc-dossier/pcc-preflight resolve their sibling arch-index tools via `command -v
# arch-impact` (they run with CWD set to the TARGET repo, never arch-index's own checkout), so
# both this repo root and scripts/pcc/ must be on PATH — exactly how the workflow's operator is
# expected to invoke them.
export PATH="$HERE:$PCC:$PATH"

# stdin: assert it is EXACTLY one JSON object (no trailing garbage) and that no float/Intlit
# value appears anywhere — same discipline as selftest-impact.sh/selftest-rules.sh.
strict_json_ok() {
  python3 -c '
import json, sys
s = sys.stdin.read().lstrip()
dec = json.JSONDecoder()
obj, idx = dec.raw_decode(s)
assert s[idx:].strip() == "", "trailing data after the JSON object"
def walk(v):
    if isinstance(v, float):
        raise AssertionError("float found in machine output: %r" % (v,))
    if isinstance(v, dict):
        for x in v.values():
            walk(x)
    elif isinstance(v, list):
        for x in v:
            walk(x)
walk(obj)
'
}

new_ocaml_fixture() {
  # $1 = target dir. A 4-function module with ONE pre-existing, deliberately UNTOUCHED
  # decision-lint finding (duplicate conjunct, same shape as decision-lint's own test fixture)
  # — needed so arch-impact --fail-on-new-findings can reach verdict:pass rather than
  # verdict:refused (an index with an empty decisions table always refuses; see JALON3-rapport.md
  # Phase 0).
  local dir="$1"
  mkdir -p "$dir/src"
  ( cd "$dir" && git init -q && git config user.email t@t && git config user.name t )
  cat > "$dir/dune-project" <<'EOF'
(lang dune 3.0)
EOF
  cat > "$dir/src/dune" <<'EOF'
(library
 (name fixturelib)
 (modules fixturelib))
EOF
  cat > "$dir/src/fixturelib.ml" <<'EOF'
let add x y = x + y
let mul x y = x * y
let entry n = add (mul n 2) 1
let quirky a b = if a && b && a then 1 else 2
EOF
  cat > "$dir/arch-rules.txt" <<'EOF'
rule "exports remain in src"
  forbid exported outside file:src/**
EOF
  ( cd "$dir" && git add -A && git commit -qm init )
}

# ============================================================================================
# 1. pcc-index: single strict JSON object, computed:true, functions is an int
# ============================================================================================
IDX_FX="$(mktemp -d)"
new_ocaml_fixture "$IDX_FX"
# Shared v1 capture is executable, bounded below CWR's 64 KiB stdout cap, and refuses an
# engine identity mismatch with exit 3 rather than silently rebasing expectations.
[ -x "$PCC/pcc-evidence" ] || note "pcc-evidence must be executable"
CAP="$(cd "$IDX_FX" && "$PCC/pcc-evidence" capture)"
[ "$(printf '%s' "$CAP" | wc -c)" -lt 65536 ] || note "pcc-evidence capture must remain below 64 KiB"
printf '%s' "$CAP" | strict_json_ok || note "pcc-evidence capture must be one strict JSON object"
printf '%s' "$CAP" | python3 -c 'import json,sys,os; d=json.load(sys.stdin); assert d["status"]=="pass"; os.unlink(d["target_artifact"]); os.unlink(d["expected_inputs_artifact"])' \
  || note "pcc-evidence direct capture must pass and provide authenticated artifacts"
# Git executable mode is target evidence, not an OS-specific incidental permission.
MODE1="$(cd "$IDX_FX" && "$PCC/pcc-target-manifest" | python3 -c 'import json,sys; print(json.load(sys.stdin)["target_digest"])')"
chmod +x "$IDX_FX/src/fixturelib.ml"
MODE2="$(cd "$IDX_FX" && "$PCC/pcc-target-manifest" | python3 -c 'import json,sys; print(json.load(sys.stdin)["target_digest"])')"
[ "$MODE1" != "$MODE2" ] || note "target digest must change for an unstaged executable-bit change"
chmod -x "$IDX_FX/src/fixturelib.ml"
BAD_REQUEST="$(printf '%s' "$CAP" | python3 -c '
import json,sys
d=json.load(sys.stdin)["actual"]
d["target_digest"]="sha256:"+"0"*64
print(json.dumps(d,sort_keys=True,separators=(",",":")))
')"
BAD_CAP="$(cd "$IDX_FX" && printf '%s' "$BAD_REQUEST" | "$PCC/pcc-evidence" capture)"
BAD_CAP_RC=$?
[ "$BAD_CAP_RC" -eq 3 ] || note "pcc-evidence must exit 3 on expected/actual identity mismatch"
printf '%s' "$BAD_CAP" | python3 -c 'import json,sys,os; d=json.load(sys.stdin); assert d["status"]=="refused" and d["ok"] is False; os.unlink(d["target_artifact"]); os.unlink(d["expected_inputs_artifact"])' \
  || note "identity mismatch receipt must be refused/ok:false"
LEAKS_BEFORE="$(find /tmp -maxdepth 1 -name 'arch-pcc-*.json' | wc -l)"
BAD_IDX="$(cd "$IDX_FX" && printf '%s' "$BAD_REQUEST" | "$PCC/pcc-index" --db .pcc/index.db)"
BAD_IDX_RC=$?
[ "$BAD_IDX_RC" -eq 3 ] || note "pcc-index identity mismatch must exit 3"
printf '%s' "$BAD_IDX" | strict_json_ok || note "pcc-index mismatch must emit exactly one JSON refusal envelope"
printf '%s' "$BAD_IDX" | python3 -c 'import json,sys; d=json.load(sys.stdin); assert d["schema"]=="arch-index.pcc.index.v1" and d["status"]=="refused" and d["ok"] is False' \
  || note "pcc-index mismatch envelope must retain the wrapper schema"
[ "$(find /tmp -maxdepth 1 -name 'arch-pcc-*.json' | wc -l)" = "$LEAKS_BEFORE" ] \
  || note "identity refusal must clean temporary manifest artifacts"
IDX_OUT="$(cd "$IDX_FX" && "$PCC/pcc-index" --db .pcc/index.db 2>/tmp/selftest-pcc-index-err.$$)"
IDX_RC=$?
[ "$IDX_RC" -eq 0 ] || { cat /tmp/selftest-pcc-index-err.$$ >&2; note "pcc-index exited $IDX_RC on a clean, buildable fixture"; }
rm -f /tmp/selftest-pcc-index-err.$$
printf '%s' "$IDX_OUT" | strict_json_ok || note "pcc-index must print exactly one strict JSON object (no float/Intlit)"
printf '%s' "$IDX_OUT" | python3 -c '
import json, sys
d = json.load(sys.stdin)
assert d["computed"] is True, d
assert isinstance(d["functions"], int) and d["functions"] > 0, d
assert isinstance(d["contract_ok"], bool), d
' 2>/dev/null || note "pcc-index JSON must have computed:true and an int functions count: got [$IDX_OUT]"
# the OCaml CMT producer is sound by construction — this fixture must reach contract_ok:true,
# same empirical result as JALON3-rapport.md's Phase 0.
printf '%s' "$IDX_OUT" | python3 -c 'import json,sys; assert json.load(sys.stdin)["contract_ok"] is True' 2>/dev/null \
  || note "pcc-index: expected contract_ok:true on the OCaml CMT-path fixture, got [$IDX_OUT]"

# All wrappers must derive the same target/policy/tool/input identities from the shared helper.
EQ_DOS="$(cd "$IDX_FX" && "$PCC/pcc-dossier" --db .pcc/index.db --repo . --diff HEAD --rules arch-rules.txt --out .pcc/dossier.md)"
EQ_PRE="$(cd "$IDX_FX" && "$PCC/pcc-preflight" 2>/dev/null)"
python3 - "$IDX_OUT" "$EQ_DOS" "$EQ_PRE" <<'PY' || note "PCC wrappers must emit identical shared v1 evidence fields"
import json,sys
docs=[json.loads(x) for x in sys.argv[1:]]
for key in ("target_digest","policy_digest","tool_bundle_digest","expected_inputs_digest"):
    assert len({d[key] for d in docs}) == 1, (key, [d[key] for d in docs])
PY

# --- every post-capture failure emits a typed envelope; mutation overrides infra failure ------
BROKEN_FX="$(mktemp -d)"
new_ocaml_fixture "$BROKEN_FX"
printf 'let x = this is not valid ocaml (((\n' >> "$BROKEN_FX/src/fixturelib.ml"
( cd "$BROKEN_FX" && git commit -qam "break the build" )
BROKEN_OUT="$(cd "$BROKEN_FX" && "$PCC/pcc-index" --db .pcc/index.db 2>/dev/null)"
BROKEN_RC=$?
[ "$BROKEN_RC" -eq 2 ] || note "pcc-index must exit 2 on a broken dune build, got $BROKEN_RC"
printf '%s' "$BROKEN_OUT" | python3 -c 'import json,sys; d=json.load(sys.stdin); assert d["status"]=="error" and d["failure_stage"]=="dune_build" and not d["mutation_detected"]' \
  || note "non-mutating build failure must emit one typed error envelope"
rm -rf "$BROKEN_FX"

MUT_BUILD="$(mktemp -d)"; new_ocaml_fixture "$MUT_BUILD"
cat >"$MUT_BUILD/dune" <<EOF
(rule (alias default)
 (action (progn
  (run sh -c "printf '\\nlet failed_build_mutation = 1\\n' >> '$MUT_BUILD/src/fixturelib.ml'")
  (run false))))
EOF
(cd "$MUT_BUILD" && git add -A && git commit -qm hostile-build)
MUT_BUILD_OUT="$(cd "$MUT_BUILD" && "$PCC/pcc-index" --db .pcc/index.db 2>/dev/null)"; MUT_BUILD_RC=$?
[ "$MUT_BUILD_RC" -eq 3 ] || note "mutation during a failing build must override infra with exit 3"
printf '%s' "$MUT_BUILD_OUT" | python3 -c 'import json,sys; d=json.load(sys.stdin); assert d["status"]=="refused" and d["mutation_detected"] and d["failure_stage"]=="dune_build"' \
  || note "failing build mutation must emit a typed refusal envelope"
grep -q failed_build_mutation "$MUT_BUILD/src/fixturelib.ml" || note "PCC mutation refusal must not clean candidate changes"
rm -rf "$MUT_BUILD"

FIFO_BUILD="$(mktemp -d)"; new_ocaml_fixture "$FIFO_BUILD"
cat >"$FIFO_BUILD/dune" <<EOF
(rule (alias default)
 (action (progn
  (run sh -c "mkfifo '$FIFO_BUILD/created.fifo'")
  (run false))))
EOF
(cd "$FIFO_BUILD" && git add -A && git commit -qm hostile-fifo-build)
FIFO_OUT="$(cd "$FIFO_BUILD" && "$PCC/pcc-index" --db .pcc/index.db 2>/dev/null)"; FIFO_RC=$?
[ "$FIFO_RC" -eq 3 ] || note "FIFO creation during a failing build must be mutation refusal/3"
printf '%s' "$FIFO_OUT" | python3 -c 'import json,sys; d=json.load(sys.stdin); assert d["status"]=="refused" and d["mutation_detected"] and d["failure_stage"]=="dune_build"' \
  || note "untracked FIFO mutation must be visible in the typed refusal envelope"
[ -p "$FIFO_BUILD/created.fifo" ] || note "FIFO mutation fixture did not create the special path"
rm -rf "$FIFO_BUILD"

# Inject failing analyzers from an otherwise complete protected tool layout.
FAKE_ROOT="$(mktemp -d)"; mkdir -p "$FAKE_ROOT/_build/default/bin/arch_callgraph_ocaml" "$FAKE_ROOT/_build/default/poc/decision-lint/bin"
ln -s "$HERE/arch-impact" "$FAKE_ROOT/arch-impact"; ln -s "$HERE/arch-rules" "$FAKE_ROOT/arch-rules"
ln -s "$HERE/architecture-schema.sql" "$FAKE_ROOT/architecture-schema.sql"
REAL_CG="$HERE/_build/default/bin/arch_callgraph_ocaml/arch_callgraph_ocaml.exe"
REAL_DL="$HERE/_build/default/poc/decision-lint/bin/decision_lint.exe"
AN_FX="$(mktemp -d)"; new_ocaml_fixture "$AN_FX"
cat >"$FAKE_ROOT/_build/default/bin/arch_callgraph_ocaml/arch_callgraph_ocaml.exe" <<EOF
#!/usr/bin/env bash
printf '\nlet failed_analyzer_mutation = 1\n' >> '$AN_FX/src/fixturelib.ml'
exit 1
EOF
cp "$REAL_DL" "$FAKE_ROOT/_build/default/poc/decision-lint/bin/decision_lint.exe"
chmod 755 "$FAKE_ROOT/_build/default/bin/arch_callgraph_ocaml/arch_callgraph_ocaml.exe" "$FAKE_ROOT/_build/default/poc/decision-lint/bin/decision_lint.exe"
AN_OUT="$(cd "$AN_FX" && PATH="$FAKE_ROOT:$PCC:$PATH" "$PCC/pcc-index" --db .pcc/index.db 2>/dev/null)"; AN_RC=$?
[ "$AN_RC" -eq 3 ] || note "mutation during failing callgraph must exit 3"
printf '%s' "$AN_OUT" | python3 -c 'import json,sys; d=json.load(sys.stdin); assert d["status"]=="refused" and d["failure_stage"]=="callgraph" and d["mutation_detected"]' \
  || note "failing analyzer mutation must emit a typed refusal envelope"

# Reach decision-lint with a real callgraph, then mutate and fail there too.
cat >"$FAKE_ROOT/_build/default/bin/arch_callgraph_ocaml/arch_callgraph_ocaml.exe" <<EOF
#!/usr/bin/env bash
exec '$REAL_CG' "\$@"
EOF
cat >"$FAKE_ROOT/_build/default/poc/decision-lint/bin/decision_lint.exe" <<EOF
#!/usr/bin/env bash
printf 'untracked analyzer mutation\n' > '$AN_FX/analyzer-untracked.txt'
exit 1
EOF
chmod 755 "$FAKE_ROOT/_build/default/bin/arch_callgraph_ocaml/arch_callgraph_ocaml.exe" "$FAKE_ROOT/_build/default/poc/decision-lint/bin/decision_lint.exe"
DL_OUT="$(cd "$AN_FX" && PATH="$FAKE_ROOT:$PCC:$PATH" "$PCC/pcc-index" --db .pcc/index2.db 2>/dev/null)"; DL_RC=$?
[ "$DL_RC" -eq 3 ] || note "untracked mutation during failing decision analysis must exit 3"
printf '%s' "$DL_OUT" | python3 -c 'import json,sys; d=json.load(sys.stdin); assert d["status"]=="refused" and d["failure_stage"]=="decision_lint" and d["mutation_detected"]' \
  || note "failing decision analyzer mutation must emit a typed refusal envelope"
rm -rf "$AN_FX" "$FAKE_ROOT"

# ============================================================================================
# 2. pcc-dossier: non-empty file at --out, exit 0 even when arch-rules/arch-impact report fail
# ============================================================================================
DOS_FX="$(mktemp -d)"
mkdir -p "$DOS_FX/src"
( cd "$DOS_FX" && git init -q && git config user.email t@t && git config user.name t )
cat > "$DOS_FX/dune-project" <<'EOF'
(lang dune 3.0)
EOF
cat > "$DOS_FX/src/dune" <<'EOF'
(library
 (name dosfix)
 (modules ui db))
EOF
cat > "$DOS_FX/src/db.ml" <<'EOF'
let write (x : int) : int = x
EOF
cat > "$DOS_FX/src/ui.ml" <<'EOF'
let handle (x : int) : int = x + 1
EOF
cat > "$DOS_FX/arch-rules.txt" <<'EOF'
rule "ui must not reach db"
  forbid reach from file:src/ui.ml to file:src/db.ml
EOF
( cd "$DOS_FX" && git add -A && git commit -qm init )
# introduce a REAL, uncommitted architecture violation — the exact shape arch-rules must FAIL
cat > "$DOS_FX/src/ui.ml" <<'EOF'
let handle (x : int) : int = Db.write (x + 1)
EOF
DOS_IDX_OUT="$(cd "$DOS_FX" && "$PCC/pcc-index" --db .pcc/index.db 2>&1)"
printf '%s' "$DOS_IDX_OUT" | python3 -c 'import json,sys; d=json.load(sys.stdin); assert d["computed"] is True and d["status"]=="pass"' 2>/dev/null \
  || note "pcc-dossier fixture: pcc-index did not build cleanly: $DOS_IDX_OUT"
rm -f "$DOS_FX/.pcc/dossier.md"
( cd "$DOS_FX" && "$PCC/pcc-dossier" --db .pcc/index.db --repo . --diff HEAD --rules arch-rules.txt --out .pcc/dossier.md )
DOS_RC=$?
[ "$DOS_RC" -eq 0 ] || note "pcc-dossier must exit 0 even though arch-rules reports a violation underneath, got $DOS_RC"
[ -s "$DOS_FX/.pcc/dossier.md" ] || note "pcc-dossier must write a non-empty file to --out"
grep -q 'FAIL' "$DOS_FX/.pcc/dossier.md" || note "pcc-dossier's file must actually surface the real arch-rules FAIL verdict, not swallow it"

# --- mutation check: a missing required argument must fail loudly, before writing anything ---
( cd "$DOS_FX" && "$PCC/pcc-dossier" --db .pcc/index.db --repo . --diff HEAD --out .pcc/bad-dossier.md >/dev/null 2>/tmp/selftest-pcc-dossier-err.$$ )
DOS_BAD_RC=$?
[ "$DOS_BAD_RC" -ne 0 ] || note "pcc-dossier with a missing required --rules argument should not silently succeed"
[ -s /tmp/selftest-pcc-dossier-err.$$ ] || note "pcc-dossier with a missing required argument should say so on stderr"
rm -f /tmp/selftest-pcc-dossier-err.$$ "$DOS_FX/.pcc/bad-dossier.md"

# ============================================================================================
# 3. pcc-preflight: {"ok":true,...}/exit 0 on a passing suite, {"ok":false,...}/exit!=0 on a
#    failing one — TWO fixtures differing in exactly the assertion that fails, so the two
#    outcomes cannot be confused with each other.
# ============================================================================================
PRE_PASS="$(mktemp -d)"
new_ocaml_fixture "$PRE_PASS"
mkdir -p "$PRE_PASS/test"
cat > "$PRE_PASS/test/dune" <<'EOF'
(test
 (name test_fixturelib)
 (libraries fixturelib alcotest))
EOF
cat > "$PRE_PASS/test/test_fixturelib.ml" <<'EOF'
let () =
  Alcotest.run "fixturelib"
    [ ("add", [ Alcotest.test_case "2+3=5" `Quick (fun () ->
          Alcotest.(check int) "add" 5 (Fixturelib.add 2 3)) ]) ]
EOF
( cd "$PRE_PASS" && git add -A && git commit -qm "add passing test" )
PRE_PASS_OUT="$(cd "$PRE_PASS" && "$PCC/pcc-preflight" 2>/tmp/selftest-pcc-preflight-pass-err.$$)"
PRE_PASS_RC=$?
[ "$PRE_PASS_RC" -eq 0 ] || { cat /tmp/selftest-pcc-preflight-pass-err.$$ >&2; note "pcc-preflight must exit 0 on a passing suite, got $PRE_PASS_RC"; }
rm -f /tmp/selftest-pcc-preflight-pass-err.$$
printf '%s' "$PRE_PASS_OUT" | strict_json_ok || note "pcc-preflight must print exactly one strict JSON object"
printf '%s' "$PRE_PASS_OUT" | python3 -c 'import json,sys; d=json.load(sys.stdin); assert d["ok"] is True and d["tests"] >= 1, d' 2>/dev/null \
  || note "pcc-preflight on a passing suite must report ok:true and tests>=1, got [$PRE_PASS_OUT]"
printf '%s' "$PRE_PASS_OUT" | python3 -c 'import json,sys; d=json.load(sys.stdin); assert not d["read_only_source_enforced"] and not d["network_isolated"] and not d["ambient_secrets_blocked"]' \
  || note "candidate-side preflight must not claim operator-owned isolation"

PRE_FAIL="$(mktemp -d)"
new_ocaml_fixture "$PRE_FAIL"
mkdir -p "$PRE_FAIL/test"
cat > "$PRE_FAIL/test/dune" <<'EOF'
(test
 (name test_fixturelib)
 (libraries fixturelib alcotest))
EOF
cat > "$PRE_FAIL/test/test_fixturelib.ml" <<'EOF'
let () =
  Alcotest.run "fixturelib"
    [ ("add", [ Alcotest.test_case "2+3=6 (deliberately wrong)" `Quick (fun () ->
          Alcotest.(check int) "add" 6 (Fixturelib.add 2 3)) ]) ]
EOF
( cd "$PRE_FAIL" && git add -A && git commit -qm "add failing test" )
PRE_FAIL_OUT="$(cd "$PRE_FAIL" && "$PCC/pcc-preflight" 2>/tmp/selftest-pcc-preflight-fail-err.$$)"
PRE_FAIL_RC=$?
[ "$PRE_FAIL_RC" -ne 0 ] || note "pcc-preflight must exit NONZERO on a failing suite"
rm -f /tmp/selftest-pcc-preflight-fail-err.$$
printf '%s' "$PRE_FAIL_OUT" | strict_json_ok || note "pcc-preflight must print exactly one strict JSON object even on failure"
printf '%s' "$PRE_FAIL_OUT" | python3 -c 'import json,sys; assert json.load(sys.stdin)["ok"] is False' 2>/dev/null \
  || note "pcc-preflight on a failing suite must report ok:false, got [$PRE_FAIL_OUT]"

# A repository-authored test that otherwise passes after mutating tracked source is refused/3;
# detection is observational and must not clean up the candidate's data.
PRE_MUT="$(mktemp -d)"
new_ocaml_fixture "$PRE_MUT"
mkdir -p "$PRE_MUT/test"
cat > "$PRE_MUT/test/dune" <<'EOF'
(test (name mutate))
EOF
cat > "$PRE_MUT/test/mutate.ml" <<'EOF'
let () =
  let path = Filename.concat (Sys.getenv "PCC_MUTATE_ROOT") "src/fixturelib.ml" in
  let oc = open_out_gen [Open_wronly; Open_append] 0o644 path in
  output_string oc "\nlet injected = 1\n";
  close_out oc
EOF
(cd "$PRE_MUT" && git add -A && git commit -qm "add mutating test")
PRE_MUT_OUT="$(cd "$PRE_MUT" && PCC_MUTATE_ROOT="$PRE_MUT" "$PCC/pcc-preflight" 2>/dev/null)"
PRE_MUT_RC=$?
[ "$PRE_MUT_RC" -eq 3 ] || note "tracked mutation by passing tests must be refused with exit 3"
printf '%s' "$PRE_MUT_OUT" | python3 -c 'import json,sys; d=json.load(sys.stdin); assert d["status"]=="refused" and d["ok"] is False' 2>/dev/null \
  || note "mutation receipt must be refused/ok:false"
grep -q 'let injected = 1' "$PRE_MUT/src/fixturelib.ml" \
  || note "mutation detection must not reset or delete candidate data"

# Initialized submodule worktree state participates recursively in the target digest.
SM="$(mktemp -d)"; SUPER="$(mktemp -d)"
git -C "$SM" init -q; git -C "$SM" config user.email t@t; git -C "$SM" config user.name t
printf 'let sub = 1\n' > "$SM/sub.ml"; git -C "$SM" add -A; git -C "$SM" commit -qm init
git -C "$SUPER" init -q; git -C "$SUPER" config user.email t@t; git -C "$SUPER" config user.name t
printf 'rule "submodule policy"\n  forbid exported outside file:**\n' > "$SUPER/arch-rules.txt"
git -C "$SUPER" -c protocol.file.allow=always submodule add -q "$SM" sm
git -C "$SUPER" add -A; git -C "$SUPER" commit -qm submodule
SM1="$(cd "$SUPER" && "$PCC/pcc-target-manifest" | python3 -c 'import json,sys; print(json.load(sys.stdin)["target_digest"])')"
printf 'let sub = 2\n' > "$SUPER/sm/sub.ml"
SM2="$(cd "$SUPER" && "$PCC/pcc-target-manifest" | python3 -c 'import json,sys; print(json.load(sys.stdin)["target_digest"])')"
[ "$SM1" != "$SM2" ] || note "dirty initialized submodule content must change target digest"
SM_REF="$(cd "$SUPER" && "$PCC/pcc-evidence" capture)"; SM_REF_RC=$?
[ "$SM_REF_RC" -eq 3 ] || note "PCC evidence must refuse unsupported submodule source universes"
printf '%s' "$SM_REF" | python3 -c 'import json,sys,os; d=json.load(sys.stdin); assert "submodule_source_universe_unsupported" in d["request_mismatches"]; os.unlink(d["target_artifact"]); os.unlink(d["expected_inputs_artifact"])' \
  || note "submodule refusal must be explicit and clean its authenticated artifacts"

rm -rf "$IDX_FX" "$DOS_FX" "$PRE_PASS" "$PRE_FAIL" "$PRE_MUT" "$SM" "$SUPER"
if [ "$fails" -eq 0 ]; then echo "selftest-pcc: PASS"; else echo "selftest-pcc: $fails FAILURE(S)"; exit 1; fi
