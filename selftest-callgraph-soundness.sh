#!/usr/bin/env bash
# selftest-callgraph-soundness.sh — regression corpus for the arch-callgraph-ocaml
# edge-kind SOUNDNESS redesign (task: callgraph-ocaml-edge-kinds, option 2).
#
# It encodes the execution-sound (DOMINANCE) semantics of MUST / reaches /
# unreachable:
#   A call site is a MUST edge of function F only if it runs on EVERY execution
#   of F — i.e. it sits on F's unconditional straight-line path. Calls in any
#   position that is not guaranteed to run are recorded as MAY_TOP:
#     - deferred bodies: function literals (fun …), lazy thunks, object methods,
#       un-applied functor bodies (run only if invoked/forced/applied);
#     - conditional bodies: if/match arms, try handlers, loop bodies, assert
#       conditions (elided under -noassert), the right operand of && / ||.
#   MAY_TOP calls never forge a MUST path (reaches stays an honest
#   under-approximation) and are never dropped (unreachable stays a sound
#   over-approximation). A function passed as an argument links via
#   MAY_ENUMERATED (named local) / MAY_TOP.
#
#   Precision note (documented, sound): because nested closures are not modelled
#   as their own nodes, an *invoked* local helper's calls are MAY_TOP rather than
#   MUST — so `reaches` through a local helper reads as "no MUST path" and
#   `unreachable` as UNKNOWN. This is safe (never a wrong verdict); recovering the
#   MUST precision requires promoting nested functions to graph nodes (future).
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
[@@@warning "-60-21-20-8"] (* -60 functor; -21/-20 divergence; -8 partial-match fixtures *)
module type S = sig val run : int -> int end
module type T = sig end

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

(* ── dominance-MUST fixtures: conditional calls are NOT MUST edges ────────── *)
(* if-branch: sink only runs when b is true → conditional *)
let cond_if (b : bool) (x : int) : int = if b then sink x else x
(* match arm: sink only runs on the 0 case → conditional *)
let cond_match (x : int) : int = match x with 0 -> sink x | n -> n
(* try handler: sink only runs on an exception → conditional *)
let cond_try (x : int) : int = ( try x with _ -> sink x )
(* short-circuit &&: right operand runs only when b is true → conditional *)
let cond_andalso (b : bool) (x : int) : bool = b && sink x > 0
(* assert condition: elided under -noassert → conditional *)
let cond_assert (x : int) : int = assert (sink x >= 0) ; x
(* unapplied local functor: body runs only on application → deferred *)
let cond_functor (x : int) : int =
  let module F (_ : T) = struct let _ = sink x end in
  ignore x ; x
(* root [function] with refutable arms: each RHS is conditional on the arg *)
let root_fun = function 0 -> sink 0 | n -> n
(* root [function] guard: runs only when its arm is reached → conditional *)
let root_guard = function 0 when sink 0 = 0 -> 0 | n -> n
(* let* continuation: the bind operator may short-circuit → body conditional *)
let ( let* ) (x : int option) (f : int -> int option) : int option =
  match x with None -> None | Some v -> f v
let letop_body (x : int option) : int option =
  let* y = x in
  ignore (sink y) ;
  Some y

(* over-application: choose2 has arity 2 but is applied to 3 args — the head is
   MUST (saturated), and the residual (applying the returned function value to
   the extra arg) is an unknowable target recorded as a MAY_TOP ⊤, so a caller
   that reaches it cannot be proven UNREACHABLE *)
let choose2 (_a : int) (_b : int) : int -> int = island
let overapp_entry () : int = choose2 0 0 1

(* saturated call: sink runs unconditionally in add2's body → MUST edge *)
let add2 (a : int) (b : int) : int = sink a + b
(* partial application: add2 1 supplies 1 of 2 args → builds a closure, add2's
   body does NOT run → the edge is MAY_TOP, so no MUST chain to sink *)
let partial_app () : int -> int = add2 1
(* partial application whose result arrow is hidden behind a type alias — the
   under-saturation check must expand the alias, else a false MUST slips through *)
type unary = int -> int
let alias_partial () : unary = add2 1

(* lazy thunk: island call is deferred (only runs if forced) → not a MUST edge *)
let lazy_thunk (x : int) : int lazy_t = lazy (island x)

(* optional-argument default expression: island call runs only when the caller
   omits ?seed → conditional, recorded but MAY_TOP (never dropped, never MUST) *)
let opt_default ?(seed = island 0) (x : int) : int = seed + x

(* self / mutual recursion sanity *)
let rec ping (n : int) : int = if n <= 0 then 0 else pong (n - 1)
and pong (n : int) : int = ping (n - 1)

(* ── R1 CFG fixtures (cfg-postdom-dominance) ─────────────────────────────── *)
(* divergence: code after an unconditional raise never runs → sink demoted *)
let after_raise (x : int) : int = raise Exit ; sink x
(* noreturn inside a try body: the handler may not match (Exit ≠ Not_found) so
   it must never be MUST; the raise itself always runs → MUST *)
let try_noreturn (x : int) : int = try raise Exit with Not_found -> sink x
(* try body is eager: the body call is MUST *)
let try_body_must (x : int) : int = try g x with _ -> 0
(* raising ARGUMENT: h is never invoked (arg evaluation diverges first) *)
let mk_exn () : exn = Exit
let false_arg () : int = ignore (sink (raise (mk_exn ()))) ; g 1
(* local module named Stdlib: its failwith returns normally → NOT a terminator *)
let no_shadow_stdlib () : int =
  let module Stdlib = struct let failwith (x : int) = x end in
  ignore (Stdlib.failwith 3) ;
  g 2
(* join after a branch: the call AFTER the if is unconditional again (the join
   block post-dominates entry) — guards against over-demotion by the CFG *)
let join_after (b : bool) (x : int) : int =
  (if b then ignore (island x)) ;
  g x

(* ── single-arm match partiality (codex step-2 finding) ──────────────────── *)
(* total unguarded single arm always runs → MUST (sound precision gain) *)
let single_total (u : unit) : int = match u with () -> sink 3
(* refutable single arm: Match_failure possible → never MUST *)
let single_partial (o : int option) : int = match o with Some y -> sink y
(* guarded single arm: guard may fail → RHS never MUST *)
let single_guarded (x : int) : int = match x with _ when x > 0 -> sink x

(* ── R2 lambda-node fixtures ─────────────────────────────────────────────── *)
(* lambda bound but NEVER referenced: genuinely dead → no parent→lambda edge *)
let dead_lambda (x : int) : int =
  let _h () = island x in
  x
(* nested literals: inner node chains through the outer lambda node *)
let nested_lam (xs : int list list) : int list list =
  List.map (fun l -> List.map (fun y -> island y) l) xs

(* ── R2b negative fixtures: stamp table must NOT resolve these ───────────── *)
(* conditional binding: two candidate literals → invocation stays MAY_TOP *)
let cond_bind (b : bool) (x : int) : int =
  let h = if b then (fun v -> island v) else (fun v -> v) in
  h x
(* tuple-pattern binding: not recorded → invocation stays MAY_TOP *)
let tuple_bind (x : int) : int =
  let (h, k) = ((fun v -> island v), 0) in
  ignore k ; h x
(* shadowing: inner h is a NEW non-literal binding; h x must not resolve to
   the outer literal (fresh stamp → not in table) *)
let shadow_bind (f : int -> int) (x : int) : int =
  let h = fun v -> island v in
  ignore h ;
  let h = f in
  h x
(* partial application of a bound lambda (arity 2, one arg) → never MUST *)
let partial_bind (x : int) : int -> int =
  let h = fun (a : int) (b : int) -> island (a + b) in
  h x
(* lambda stored in a tuple (non-argument occurrence): the value escapes, so a
   parent→lambda enumerated edge must exist — island stays may-reachable, and
   the lambda node must NOT be orphaned (dead-code false-positive guard) *)
let stored_bind (x : int) : int =
  let h () = island x in
  let t = (h, 0) in
  ignore t ; x
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
chk P1 "reaches ping pong = no must (recursive call is in an else-branch)" "$(verdict reaches ping pong)" "no MUST path"
chk P1 "unreachable on unknown root = REFUSED"      "$(refuses unreachable no_such_fn also_missing)" "REFUSED"
chk P1 "no NULL/invalid kinds" "$(sqlite3 "$DB" "SELECT count(*) FROM calls WHERE kind IS NULL OR kind NOT IN ('MUST','MAY_ENUMERATED','MAY_TOP');")" "0"

echo "── P1: dominance-MUST — conditional/deferred calls are never MUST, never dropped ──"
chk P1 "reaches cond_if sink = no must (if-branch conditional)"       "$(verdict reaches cond_if sink)"       "no MUST path"
chk P1 "reaches cond_match sink = no must (match arm conditional)"    "$(verdict reaches cond_match sink)"    "no MUST path"
chk P1 "reaches cond_try sink = no must (exception handler)"          "$(verdict reaches cond_try sink)"      "no MUST path"
chk P1 "reaches cond_andalso sink = no must (&& right operand)"       "$(verdict reaches cond_andalso sink)"  "no MUST path"
chk P1 "reaches cond_assert sink = no must (assert elided by -noassert)" "$(verdict reaches cond_assert sink)" "no MUST path"
chk P1 "reaches cond_functor sink = no must (unapplied functor body)" "$(verdict reaches cond_functor sink)"  "no MUST path"
chk P1 "reaches root_fun sink = no must (root function arm conditional)" "$(verdict reaches root_fun sink)"   "no MUST path"
chk P1 "reaches root_guard sink = no must (root function guard conditional)" "$(verdict reaches root_guard sink)" "no MUST path"
chk P1 "reaches letop_body sink = no must (let* continuation conditional)" "$(verdict reaches letop_body sink)" "no MUST path"
chk P1 "reaches overapp_entry choose2 = must (over-applied head is saturated)" "$(verdict reaches overapp_entry choose2)" "PATH EXISTS"
chk P1 "overapp_entry emits a MAY_TOP residual (over-application ⊤)" "$(sqlite3 "$DB" "SELECT CASE WHEN count(*)>0 THEN 'yes' ELSE 'no' END FROM calls c JOIN functions f ON c.caller_id=f.id WHERE f.name='overapp_entry' AND c.kind='MAY_TOP';")" "yes"
chk P1 "reaches add2 sink = must (saturated call runs the body)"      "$(verdict reaches add2 sink)"          "PATH EXISTS"
chk P1 "reaches partial_app sink = no must (partial application defers body)" "$(verdict reaches partial_app sink)" "no MUST path"
chk P1 "reaches alias_partial sink = no must (alias-hidden partial application)" "$(verdict reaches alias_partial sink)" "no MUST path"
chk P1 "letop_body records the let* operator call (MUST, not dropped)" "$(sqlite3 "$DB" "SELECT COALESCE(MAX(kind),'MISSING') FROM calls c JOIN functions f ON c.caller_id=f.id WHERE f.name='letop_body' AND c.callee_name='let*';")" "MUST"
# stable in both designs (promoted from the previous redesign's P2 targets):
chk P1 "reaches unused_closure island = no must (uninvoked nested body)" "$(verdict reaches unused_closure island)" "no MUST path"
chk P1 "reaches lam_map island = no must (passed lambda never a MUST path)" "$(verdict reaches lam_map island)" "no MUST path"
chk P1 "reaches lazy_thunk island = no must (lazy thunk deferred)"       "$(verdict reaches lazy_thunk island)"   "no MUST path"
chk P1 "reaches opt_default island = no must (opt-arg default conditional)" "$(verdict reaches opt_default island)" "no MUST path"
chk P1 "unreachable computed_map island = UNKNOWN (computed callback = true ⊤)" "$(verdict unreachable computed_map island)" "UNKNOWN:"
chk P1 "unreachable fcm_param sink = UNKNOWN (first-class module param = true ⊤)" "$(verdict unreachable fcm_param sink)" "UNKNOWN:"
chk P1 "unreachable direct sink = REACHABLE (direct MUST chain intact)"  "$(verdict unreachable direct sink)"     "REACHABLE (may-reach)"
# R1 CFG sanity that must hold in BOTH designs:
chk P1 "reaches try_body_must sink = must (try body is eager)"        "$(verdict reaches try_body_must sink)"  "PATH EXISTS"
chk P1 "reaches join_after sink = must (join after a branch is unconditional)" "$(verdict reaches join_after sink)" "PATH EXISTS"
chk P1 "reaches try_noreturn sink = no must (handler never post-dominates)" "$(verdict reaches try_noreturn sink)" "no MUST path"
chk P1 "try_noreturn raise edge is MUST (the raise always runs)" "$(sqlite3 "$DB" "SELECT COALESCE(MAX(kind),'MISSING') FROM calls c JOIN functions f ON c.caller_id=f.id WHERE f.name='try_noreturn' AND c.callee_name LIKE '%raise';")" "MUST"
chk P1 "reaches single_total sink = must (total unguarded single arm always runs)" "$(verdict reaches single_total sink)" "PATH EXISTS"
chk P1 "reaches single_partial sink = no must (refutable arm may fail)" "$(verdict reaches single_partial sink)" "no MUST path"
chk P1 "reaches single_guarded sink = no must (guard may fail)" "$(verdict reaches single_guarded sink)" "no MUST path"
chk P1 "reaches false_arg sink = no must (raising argument precedes the call)" "$(verdict reaches false_arg sink)" "no MUST path"
chk P1 "false_arg mk_exn edge is MUST (argument evaluation runs)" "$(sqlite3 "$DB" "SELECT COALESCE(MAX(kind),'MISSING') FROM calls c JOIN functions f ON c.caller_id=f.id WHERE f.name='false_arg' AND c.callee_name='mk_exn';")" "MUST"
chk P1 "reaches no_shadow_stdlib g = must (local Stdlib.failwith is not a terminator)" "$(verdict reaches no_shadow_stdlib g)" "PATH EXISTS"
# R2b stamp-table negatives: only single-literal Tpat_var bindings resolve.
chk P1 "reaches cond_bind island = no must (conditional binding not recorded)" "$(verdict reaches cond_bind island)" "no MUST path"
chk P1 "unreachable cond_bind island = REACHABLE (arm literals are enumerated occurrences)" "$(verdict unreachable cond_bind island)" "REACHABLE (may-reach)"
chk P1 "reaches tuple_bind island = no must (tuple pattern not recorded)" "$(verdict reaches tuple_bind island)" "no MUST path"
chk P1 "reaches shadow_bind island = no must (rebound name is a fresh stamp)" "$(verdict reaches shadow_bind island)" "no MUST path"
chk P1 "reaches partial_bind island = no must (partial application of bound lambda)" "$(verdict reaches partial_bind island)" "no MUST path"
chk P1 "unreachable stored_bind island = REACHABLE (tuple-stored lambda escapes)" "$(verdict unreachable stored_bind island)" "REACHABLE (may-reach)"
chk P1 "stored_bind lambda not orphaned (has an incoming enumerated edge)" "$(sqlite3 "$DB" "SELECT COALESCE(MAX(c.kind),'ORPHAN') FROM calls c WHERE c.callee_name LIKE 'stored_bind.<fun:%';")" "MAY_ENUMERATED"

echo "── P2: cfg-postdom-dominance targets (computed dominance / lambda nodes / enumerated demotion) ──"
# R1 — divergence residual closed: code after an unconditional raise is demoted.
chk P2 "reaches after_raise sink = no must (post-raise block entry-unreachable)" "$(verdict reaches after_raise sink)" "no MUST path"
chk P2 "after_raise sink call recorded, demoted (never dropped)" "$(sqlite3 "$DB" "SELECT CASE WHEN count(*)=1 AND MAX(kind)<>'MUST' THEN 'demoted' WHEN count(*)=0 THEN 'DROPPED' ELSE 'other' END FROM calls c JOIN functions f ON c.caller_id=f.id WHERE f.name='after_raise' AND c.callee_name='sink';")" "demoted"
# US-4 — enumerated demotion: conditional calls to RESOLVED callees are MAY_ENUMERATED,
# so unreachable becomes decidable (these flip from UNKNOWN).
chk P2 "unreachable cond_if sink = REACHABLE (enumerated conditional callee)" "$(verdict unreachable cond_if sink)" "REACHABLE (may-reach)"
chk P2 "unreachable cond_if island = UNREACHABLE (no ⊤ in cond_if closure)" "$(verdict unreachable cond_if island)" "UNREACHABLE:"
chk P2 "unreachable cond_functor sink = REACHABLE (deferred but enumerated)" "$(verdict unreachable cond_functor sink)" "REACHABLE (may-reach)"
chk P2 "unreachable root_fun sink = REACHABLE (arm callee enumerated)" "$(verdict unreachable root_fun sink)" "REACHABLE (may-reach)"
chk P2 "unreachable lazy_thunk island = REACHABLE (thunk callee enumerated)" "$(verdict unreachable lazy_thunk island)" "REACHABLE (may-reach)"
chk P2 "unreachable opt_default island = REACHABLE (default callee enumerated)" "$(verdict unreachable opt_default island)" "REACHABLE (may-reach)"
chk P2 "unreachable try_noreturn sink = REACHABLE (handler callee enumerated)" "$(verdict unreachable try_noreturn sink)" "REACHABLE (may-reach)"
# R2 — lambda nodes: literals become graph nodes; callback bodies stop being ⊤.
chk P2 "lam_map lambda node exists" "$(sqlite3 "$DB" "SELECT CASE WHEN count(*)=1 THEN 'yes' ELSE 'no' END FROM functions WHERE name LIKE 'lam_map.<fun:%';")" "yes"
chk P2 "lam_map lambda → island is MUST (lambda body straight-line)" "$(sqlite3 "$DB" "SELECT COALESCE(MAX(c.kind),'MISSING') FROM calls c JOIN functions f ON c.caller_id=f.id WHERE f.name LIKE 'lam_map.<fun:%' AND c.callee_name='island';")" "MUST"
chk P2 "lam_map parent → lambda is MAY_ENUMERATED (passed literal)" "$(sqlite3 "$DB" "SELECT COALESCE(MAX(c.kind),'MISSING') FROM calls c JOIN functions f ON c.caller_id=f.id WHERE f.name='lam_map' AND c.callee_name LIKE 'lam_map.<fun:%';")" "MAY_ENUMERATED"
chk P2 "unreachable lam_map island = REACHABLE (through the lambda node)" "$(verdict unreachable lam_map island)" "REACHABLE (may-reach)"
chk P2 "escapes lam_map = empty ⊤ frontier" "$(test -z "$("$Q" "$DB" escapes lam_map 2>/dev/null | grep -v '^$')" && echo empty || echo nonempty)" "empty"
chk P2 "unreachable unused_closure island = REACHABLE (ignore h = escape occurrence)" "$(verdict unreachable unused_closure island)" "REACHABLE (may-reach)"
chk P2 "reaches invoked_closure island = must (invoked local lambda → MUST chain)" "$(verdict reaches invoked_closure island)" "PATH EXISTS"
chk P2 "dead_lambda has no parent→lambda edge (never referenced)" "$(sqlite3 "$DB" "SELECT CASE WHEN count(*)=0 THEN 'none' ELSE 'edge' END FROM calls c JOIN functions f ON c.caller_id=f.id WHERE f.name='dead_lambda' AND c.callee_name LIKE '%<fun:%';")" "none"
chk P2 "unreachable dead_lambda island = UNREACHABLE (dead lambda, no ⊤)" "$(verdict unreachable dead_lambda island)" "UNREACHABLE:"
chk P2 "nested lambda node chains through the outer node" "$(sqlite3 "$DB" "SELECT CASE WHEN count(*)>=1 THEN 'yes' ELSE 'no' END FROM functions WHERE name LIKE 'nested_lam.<fun:%.<fun:%';")" "yes"

echo
echo "P1: $p1_pass passed, $p1_fail failed | P2: $p2_xfail xfail (targets), $p2_xpass xpass"
if [ "$p1_fail" -gt 0 ]; then echo "callgraph-soundness: FAIL (P1 regressions)"; exit 1; fi
if [ "$STRICT" = 1 ] && [ "$p2_xfail" -gt 0 ]; then echo "callgraph-soundness: FAIL (STRICT: $p2_xfail P2 targets unmet)"; exit 1; fi
echo "callgraph-soundness: PASS"; exit 0
