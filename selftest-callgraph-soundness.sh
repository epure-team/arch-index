#!/usr/bin/env bash
# selftest-callgraph-soundness.sh — regression corpus for the arch-callgraph-ocaml
# edge-kind SOUNDNESS redesign (task: callgraph-ocaml-edge-kinds, option 2).
#
# It encodes the TARGET execution-sound semantics of MUST / reaches / unreachable:
#   A call site is a MUST edge of function F only if it sits directly in F's own
#   body — NOT inside a nested function literal (fun … / nested let) that F does
#   not itself invoke. Calls inside a nested closure count only once that closure
#   is invoked; a closure passed/stored/returned links via MAY_ENUMERATED/MAY_TOP.
#   Branches (if/match) still count both arms.
#
# Each assertion is tagged:
#   P1 — must PASS now (already-correct behaviour: F1 shadow, F2 cross-module id
#        closure, F3 function-typed value, F4 empty/unknown-root refuse, named &
#        parameter callbacks).
#   P2 — the redesign's TARGETS: expected to FAIL now (XFAIL) and flip to PASS
#        when Phase 2 lands. Set STRICT=1 to make P2 mismatches fatal (use once
#        Phase 2 is done to promote the whole suite).
#
# Exit 0 iff every P1 assertion passes (and, under STRICT=1, every P2 too).
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
Q="$HERE/arch-query"
SCHEMA="$HERE/architecture-schema.sql"
STRICT="${STRICT:-0}"
command -v opam    >/dev/null 2>&1 || { echo "soundness: opam required" >&2; exit 2; }
command -v sqlite3 >/dev/null 2>&1 || { echo "soundness: sqlite3 required" >&2; exit 2; }
# Pin the switch resolved from the repo root before we cd into the fixture dir.
eval "$(cd "$HERE" && opam env 2>/dev/null)" || true

BIN_DEFAULT="$HERE/_build/default/bin/arch_callgraph_ocaml/arch_callgraph_ocaml.exe"
BIN_INSTALL="$HERE/_build/install/default/bin/arch_callgraph_ocaml"
if   [ -x "$BIN_INSTALL" ]; then BIN="$BIN_INSTALL"
elif [ -x "$BIN_DEFAULT" ]; then BIN="$BIN_DEFAULT"
else echo "soundness: arch_callgraph_ocaml not built — run ./build.sh" >&2; exit 2; fi

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
MOD="$TMP/corpus"; mkdir -p "$MOD"
cat > "$MOD/dune-project" <<'DP'
(lang dune 3.0)
DP
cat > "$MOD/dune" <<'DF'
(library (name corpus) (modules cg crb))
DF

cat > "$MOD/crb.ml" <<'ML'
let sink2 (x : int) : int = x
let direct2 (x : int) : int = sink2 (x + 1)
let mid (f : int -> int) (x : int) : int = f x
ML

cat > "$MOD/cg.ml" <<'ML'
module type S = sig val run : int -> int end

let sink (x : int) : int = x
let g (x : int) : int = sink x
let island (x : int) : int = x + 1

(* direct MUST chain: direct -> g -> sink *)
let direct (x : int) : int = g x

(* nested closure that is NEVER invoked: island MUST NOT be a MUST target *)
let unused_closure (x : int) : int =
  let h () = island x in
  ignore h ;
  x

(* nested closure that IS invoked: island is reachable *)
let invoked_closure (x : int) : int =
  let h () = island x in
  h ()

(* lambda passed to a HOF: island call is conditional, not a MUST edge *)
let lam_map (xs : int list) : int list = List.map (fun y -> island y) xs

(* named local callback: MAY_ENUMERATED → reachable, not MUST *)
let named_map (xs : int list) : int list = List.map island xs

(* parameter callback: unknown target → MAY_TOP *)
let param_map (f : int -> int) (xs : int list) : int list = List.map f xs

(* computed callback (function returned by a call): unknown → MAY_TOP *)
let make () : int -> int = island
let computed_map (xs : int list) : int list = List.map (make ()) xs

(* parameter application *)
let apply_param (f : int -> int) (x : int) : int = f x

(* parameter shadowing a top-level function name (F1) *)
let call_param (island : int -> int) (x : int) : int = island x

(* function-typed value with non-function RHS (F3) *)
let chosen : int -> int = if Array.length Sys.argv > 0 then g else sink
let val_call (x : int) : int = chosen x

(* first-class module parameter: M.run target is caller-supplied → MAY_TOP *)
let fcm_param (module M : S) (x : int) : int = M.run x

(* cross-module MUST chain (F2) *)
let entry_direct (x : int) : int = Crb.direct2 x
(* cross-module callee that internally escapes (F2 UNKNOWN preservation) *)
let entry_unknown (x : int) : int = Crb.mid (fun y -> y) x

(* self / mutual recursion sanity *)
let rec ping (n : int) : int = if n <= 0 then 0 else pong (n - 1)
and pong (n : int) : int = ping (n - 1)
ML

( cd "$MOD" && dune build 2>/tmp/soundness-dune.txt ) \
  || { cat /tmp/soundness-dune.txt >&2; echo "soundness: fixture build failed" >&2; exit 2; }
DB="$TMP/corpus.db"
"$BIN" --build-dir "$MOD/_build/default" --db-path "$DB" --schema-path "$SCHEMA" \
  2>/tmp/soundness-idx.txt || { cat /tmp/soundness-idx.txt >&2; echo "soundness: index failed" >&2; exit 2; }

# ── assertion engine ──────────────────────────────────────────────────────────
p1_pass=0; p1_fail=0; p2_xfail=0; p2_xpass=0
# verdict token from an arch-query invocation
verdict() { "$Q" "$DB" "$@" 2>&1 | grep -oE 'PATH EXISTS|no MUST path|REACHABLE \(may-reach\)|UNREACHABLE:|UNKNOWN:|REFUSED' | head -1; }
# refusal detection (exit 3)
refuses() { local rc=0; "$Q" "$DB" "$@" >/dev/null 2>&1 || rc=$?; [ "$rc" -eq 3 ] && echo REFUSED || echo NOREFUSE; }
# chk <P1|P2> "<desc>" "<actual>" "<expected>"
chk() {
  local phase="$1" desc="$2" actual="$3" expected="$4"
  if [ "$actual" = "$expected" ]; then
    if [ "$phase" = P1 ]; then p1_pass=$((p1_pass+1)); printf '  [P1 ok]   %s\n' "$desc"
    else p2_xpass=$((p2_xpass+1)); printf '  [P2 XPASS]%s  (target already met!)\n' " $desc"; fi
  else
    if [ "$phase" = P1 ]; then p1_fail=$((p1_fail+1)); printf '  [P1 FAIL] %s — got "%s" want "%s"\n' "$desc" "$actual" "$expected"
    else p2_xfail=$((p2_xfail+1)); printf '  [P2 xfail]%s — got "%s" want "%s"\n' " $desc" "$actual" "$expected"; fi
  fi
}

echo "── P1: already-sound behaviour (must pass now) ──"
chk P1 "reaches direct sink = must-path"            "$(verdict reaches direct sink)"          "PATH EXISTS"
chk P1 "reaches entry_direct sink2 = cross-mod must" "$(verdict reaches entry_direct sink2)"   "PATH EXISTS"
chk P1 "unreachable entry_unknown sink2 = UNKNOWN"  "$(verdict unreachable entry_unknown sink2)" "UNKNOWN:"
chk P1 "reaches call_param island = no must (param shadow)" "$(verdict reaches call_param island)" "no MUST path"
chk P1 "unreachable call_param island = UNKNOWN"    "$(verdict unreachable call_param island)" "UNKNOWN:"
chk P1 "unreachable val_call sink = UNKNOWN (fn-value)" "$(verdict unreachable val_call sink)" "UNKNOWN:"
chk P1 "unreachable named_map island = REACHABLE (callback)" "$(verdict unreachable named_map island)" "REACHABLE (may-reach)"
chk P1 "reaches named_map island = no must (callback not must)" "$(verdict reaches named_map island)" "no MUST path"
chk P1 "unreachable param_map island = UNKNOWN (param cb)" "$(verdict unreachable param_map island)" "UNKNOWN:"
chk P1 "unreachable apply_param island = UNKNOWN"   "$(verdict unreachable apply_param island)" "UNKNOWN:"
chk P1 "reaches ping pong = must (mutual rec)"      "$(verdict reaches ping pong)"            "PATH EXISTS"
chk P1 "unreachable on unknown root = REFUSED"      "$(refuses unreachable no_such_fn also_missing)" "REFUSED"
chk P1 "no NULL/invalid kinds" "$(sqlite3 "$DB" "SELECT count(*) FROM calls WHERE kind IS NULL OR kind NOT IN ('MUST','MAY_ENUMERATED','MAY_TOP');")" "0"

echo "── P2: redesign targets (expected xfail now, must pass after Phase 2) ──"
chk P2 "reaches unused_closure island = no must (uninvoked nested body)" "$(verdict reaches unused_closure island)" "no MUST path"
chk P2 "unreachable unused_closure island = UNREACHABLE"                 "$(verdict unreachable unused_closure island)" "UNREACHABLE:"
chk P2 "reaches lam_map island = no must (lambda body not must)"         "$(verdict reaches lam_map island)"       "no MUST path"
chk P2 "unreachable computed_map island = UNKNOWN (computed callback)"   "$(verdict unreachable computed_map island)" "UNKNOWN:"
chk P2 "unreachable fcm_param sink = UNKNOWN (first-class module param)"  "$(verdict unreachable fcm_param sink)"  "UNKNOWN:"
# invoked nested closure: island IS reachable either way (verdict stable) — sanity that the redesign keeps it
chk P2 "reaches invoked_closure island = must (invoked nested body)"     "$(verdict reaches invoked_closure island)" "PATH EXISTS"

echo
echo "P1: $p1_pass passed, $p1_fail failed | P2: $p2_xfail xfail (targets), $p2_xpass xpass"
if [ "$p1_fail" -gt 0 ]; then echo "callgraph-soundness: FAIL (P1 regressions)"; exit 1; fi
if [ "$STRICT" = 1 ] && [ "$p2_xfail" -gt 0 ]; then echo "callgraph-soundness: FAIL (STRICT: $p2_xfail P2 targets unmet)"; exit 1; fi
echo "callgraph-soundness: PASS (Phase 1 baseline)"; exit 0
