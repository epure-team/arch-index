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
  ( cd "$dir" && git add -A && git commit -qm init )
}

# ============================================================================================
# 1. pcc-index: single strict JSON object, computed:true, functions is an int
# ============================================================================================
IDX_FX="$(mktemp -d)"
new_ocaml_fixture "$IDX_FX"
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

# --- mutation check: a broken dune build must abort with exit 2 and NO stdout at all ---------
BROKEN_FX="$(mktemp -d)"
new_ocaml_fixture "$BROKEN_FX"
printf 'let x = this is not valid ocaml (((\n' >> "$BROKEN_FX/src/fixturelib.ml"
( cd "$BROKEN_FX" && git commit -qam "break the build" )
BROKEN_OUT="$(cd "$BROKEN_FX" && "$PCC/pcc-index" --db .pcc/index.db 2>/dev/null)"
BROKEN_RC=$?
[ "$BROKEN_RC" -eq 2 ] || note "pcc-index must exit 2 on a broken dune build, got $BROKEN_RC"
[ -z "$BROKEN_OUT" ] || note "pcc-index must print NO stdout on an infra failure, got [$BROKEN_OUT]"
rm -rf "$BROKEN_FX"

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
echo "$DOS_IDX_OUT" | grep -q '"computed": true' || note "pcc-dossier fixture: pcc-index did not build cleanly: $DOS_IDX_OUT"
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

rm -rf "$IDX_FX" "$DOS_FX" "$PRE_PASS" "$PRE_FAIL"
if [ "$fails" -eq 0 ]; then echo "selftest-pcc: PASS"; else echo "selftest-pcc: $fails FAILURE(S)"; exit 1; fi
