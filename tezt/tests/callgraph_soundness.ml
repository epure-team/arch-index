(******************************************************************************)
(*                                                                            *)
(* Copyright (c) 2026 Epure Team                                              *)
(* All rights reserved.                                                       *)
(*                                                                            *)
(******************************************************************************)

(** The edge-kind soundness corpus.

    It encodes execution-sound DOMINANCE: a call site is a MUST edge of [F] only
    if it runs on EVERY execution of [F]. Everything that is not guaranteed to
    run — a deferred body (function literal, lazy thunk, object method,
    unapplied functor) or a conditional one (if/match arm, try handler, loop
    body, assert condition, the right operand of [&&]) — is recorded but
    demoted. Demoted, never dropped: [reaches] stays an honest
    under-approximation and [unreachable] a sound over-approximation, and the
    two failure modes are opposite, so the corpus asserts both directions on the
    same fixture.

    Assertions carry the phase they were written in. P1 is behaviour that must
    hold now. P2 marks the redesign's targets, expected to fail until the phase
    that implements them lands: an XFAIL is reported, not failed, unless
    ARCH_TEZT_STRICT_P2=1 — which is how the suite gets promoted once the work
    is done. A P2 that starts passing is reported as XPASS rather than silently
    counted, because a target that has been met should be re-tagged rather than
    left looking outstanding. *)

open Arch_tezt

type phase = P1 | P2

let fixture_files =
  [
    ("dune-project", "(lang dune 3.0)\n");
    ("dune", "(library (name corpus) (modules cg crb))\n");
    ("crb.ml", {|let sink2 (x : int) : int = x
let direct2 (x : int) : int = sink2 (x + 1)
let mid (f : int -> int) (x : int) : int = f x
|});
    ("cg.ml", {|[@@@warning "-60-21-20-8"] (* -60 functor; -21/-20 divergence; -8 partial-match fixtures *)
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

(* diverging let* operand: the bind operator is applied AFTER its operand, so
   [let* y = raise Exit in …] must NOT record a MUST edge to the operator *)
let letop_diverge () : int option =
  let* y = raise Exit in
  Some y
(* beta-redex: an immediately-applied literal head resolves to the lambda node
   (MUST — always-exec + saturated), never to a ⊤ marker *)
let beta_redex (x : int) : int = (fun y -> island y) x
|});
  ]

(* The single token arch-query's answer turns on. Matching the FIRST occurrence
   of one of these, rather than scanning for a substring anywhere, is what stops
   a function whose own name contains "UNREACHABLE" inverting its own verdict. *)
let verdict_token output =
  let tokens =
    ["PATH EXISTS"; "no MUST path"; "REACHABLE (may-reach)"; "UNREACHABLE:"; "UNKNOWN:"; "REFUSED"]
  in
  let best = ref None in
  List.iter
    (fun t ->
      let n = String.length t and h = String.length output in
      let i = ref 0 in
      while !i <= h - n do
        if String.sub output !i n = t then begin
          (match !best with
          | Some (j, _) when j <= !i -> ()
          | _ -> best := Some (!i, t)) ;
          i := h
        end
        else incr i
      done)
    tokens ;
  match !best with Some (_, t) -> t | None -> "<no verdict token>"

let verdict_checks =
  [
    (P1, "reaches direct sink = must-path", `Verdict (["reaches"; "direct"; "sink"], "PATH EXISTS"));
    (P1, "reaches entry_direct sink2 = cross-mod must", `Verdict (["reaches"; "entry_direct"; "sink2"], "PATH EXISTS"));
    (P1, "unreachable entry_unknown sink2 = UNKNOWN", `Verdict (["unreachable"; "entry_unknown"; "sink2"], "UNKNOWN:"));
    (P1, "reaches call_param island = no must (param shadow)", `Verdict (["reaches"; "call_param"; "island"], "no MUST path"));
    (P1, "unreachable call_param island = UNKNOWN", `Verdict (["unreachable"; "call_param"; "island"], "UNKNOWN:"));
    (P1, "unreachable val_call sink = UNKNOWN (fn-value)", `Verdict (["unreachable"; "val_call"; "sink"], "UNKNOWN:"));
    (P1, "unreachable named_map island = REACHABLE (callback)", `Verdict (["unreachable"; "named_map"; "island"], "REACHABLE (may-reach)"));
    (P1, "reaches named_map island = no must (callback not must)", `Verdict (["reaches"; "named_map"; "island"], "no MUST path"));
    (P1, "unreachable param_map island = UNKNOWN (param cb)", `Verdict (["unreachable"; "param_map"; "island"], "UNKNOWN:"));
    (P1, "unreachable apply_param island = UNKNOWN", `Verdict (["unreachable"; "apply_param"; "island"], "UNKNOWN:"));
    (P1, "reaches ping pong = no must (recursive call is in an else-branch)", `Verdict (["reaches"; "ping"; "pong"], "no MUST path"));
    (P1, "unreachable on unknown root = REFUSED", `Refuses ["unreachable"; "no_such_fn"; "also_missing"]);
    (P1, "reaches cond_if sink = no must (if-branch conditional)", `Verdict (["reaches"; "cond_if"; "sink"], "no MUST path"));
    (P1, "reaches cond_match sink = no must (match arm conditional)", `Verdict (["reaches"; "cond_match"; "sink"], "no MUST path"));
    (P1, "reaches cond_try sink = no must (exception handler)", `Verdict (["reaches"; "cond_try"; "sink"], "no MUST path"));
    (P1, "reaches cond_andalso sink = no must (&& right operand)", `Verdict (["reaches"; "cond_andalso"; "sink"], "no MUST path"));
    (P1, "reaches cond_assert sink = no must (assert elided by -noassert)", `Verdict (["reaches"; "cond_assert"; "sink"], "no MUST path"));
    (P1, "reaches cond_functor sink = no must (unapplied functor body)", `Verdict (["reaches"; "cond_functor"; "sink"], "no MUST path"));
    (P1, "reaches root_fun sink = no must (root function arm conditional)", `Verdict (["reaches"; "root_fun"; "sink"], "no MUST path"));
    (P1, "reaches root_guard sink = no must (root function guard conditional)", `Verdict (["reaches"; "root_guard"; "sink"], "no MUST path"));
    (P1, "reaches letop_body sink = no must (let* continuation conditional)", `Verdict (["reaches"; "letop_body"; "sink"], "no MUST path"));
    (P1, "reaches overapp_entry choose2 = must (over-applied head is saturated)", `Verdict (["reaches"; "overapp_entry"; "choose2"], "PATH EXISTS"));
    (P1, "reaches add2 sink = must (saturated call runs the body)", `Verdict (["reaches"; "add2"; "sink"], "PATH EXISTS"));
    (P1, "reaches partial_app sink = no must (partial application defers body)", `Verdict (["reaches"; "partial_app"; "sink"], "no MUST path"));
    (P1, "reaches alias_partial sink = no must (alias-hidden partial application)", `Verdict (["reaches"; "alias_partial"; "sink"], "no MUST path"));
    (P1, "reaches unused_closure island = no must (uninvoked nested body)", `Verdict (["reaches"; "unused_closure"; "island"], "no MUST path"));
    (P1, "reaches lam_map island = no must (passed lambda never a MUST path)", `Verdict (["reaches"; "lam_map"; "island"], "no MUST path"));
    (P1, "reaches lazy_thunk island = no must (lazy thunk deferred)", `Verdict (["reaches"; "lazy_thunk"; "island"], "no MUST path"));
    (P1, "reaches opt_default island = no must (opt-arg default conditional)", `Verdict (["reaches"; "opt_default"; "island"], "no MUST path"));
    (P1, "unreachable computed_map island = UNKNOWN (computed callback = true ⊤)", `Verdict (["unreachable"; "computed_map"; "island"], "UNKNOWN:"));
    (P1, "unreachable fcm_param sink = UNKNOWN (first-class module param = true ⊤)", `Verdict (["unreachable"; "fcm_param"; "sink"], "UNKNOWN:"));
    (P1, "unreachable direct sink = REACHABLE (direct MUST chain intact)", `Verdict (["unreachable"; "direct"; "sink"], "REACHABLE (may-reach)"));
    (P1, "reaches try_body_must sink = must (try body is eager)", `Verdict (["reaches"; "try_body_must"; "sink"], "PATH EXISTS"));
    (P1, "reaches join_after sink = must (join after a branch is unconditional)", `Verdict (["reaches"; "join_after"; "sink"], "PATH EXISTS"));
    (P1, "reaches try_noreturn sink = no must (handler never post-dominates)", `Verdict (["reaches"; "try_noreturn"; "sink"], "no MUST path"));
    (P1, "reaches single_total sink = must (total unguarded single arm always runs)", `Verdict (["reaches"; "single_total"; "sink"], "PATH EXISTS"));
    (P1, "reaches single_partial sink = no must (refutable arm may fail)", `Verdict (["reaches"; "single_partial"; "sink"], "no MUST path"));
    (P1, "reaches single_guarded sink = no must (guard may fail)", `Verdict (["reaches"; "single_guarded"; "sink"], "no MUST path"));
    (P1, "reaches false_arg sink = no must (raising argument precedes the call)", `Verdict (["reaches"; "false_arg"; "sink"], "no MUST path"));
    (P1, "reaches no_shadow_stdlib g = must (local Stdlib.failwith is not a terminator)", `Verdict (["reaches"; "no_shadow_stdlib"; "g"], "PATH EXISTS"));
    (P1, "reaches cond_bind island = no must (conditional binding not recorded)", `Verdict (["reaches"; "cond_bind"; "island"], "no MUST path"));
    (P1, "unreachable cond_bind island = REACHABLE (arm literals are enumerated occurrences)", `Verdict (["unreachable"; "cond_bind"; "island"], "REACHABLE (may-reach)"));
    (P1, "reaches tuple_bind island = no must (tuple pattern not recorded)", `Verdict (["reaches"; "tuple_bind"; "island"], "no MUST path"));
    (P1, "reaches shadow_bind island = no must (rebound name is a fresh stamp)", `Verdict (["reaches"; "shadow_bind"; "island"], "no MUST path"));
    (P1, "reaches partial_bind island = no must (partial application of bound lambda)", `Verdict (["reaches"; "partial_bind"; "island"], "no MUST path"));
    (P1, "unreachable stored_bind island = REACHABLE (tuple-stored lambda escapes)", `Verdict (["unreachable"; "stored_bind"; "island"], "REACHABLE (may-reach)"));
    (P1, "reaches beta_redex island = must (beta-redex head is the lambda node)", `Verdict (["reaches"; "beta_redex"; "island"], "PATH EXISTS"));
    (P2, "reaches after_raise sink = no must (post-raise block entry-unreachable)", `Verdict (["reaches"; "after_raise"; "sink"], "no MUST path"));
    (P2, "unreachable cond_if sink = REACHABLE (enumerated conditional callee)", `Verdict (["unreachable"; "cond_if"; "sink"], "REACHABLE (may-reach)"));
    (P2, "unreachable cond_if island = UNREACHABLE (no ⊤ in cond_if closure)", `Verdict (["unreachable"; "cond_if"; "island"], "UNREACHABLE:"));
    (P2, "unreachable cond_functor sink = REACHABLE (deferred but enumerated)", `Verdict (["unreachable"; "cond_functor"; "sink"], "REACHABLE (may-reach)"));
    (P2, "unreachable root_fun sink = REACHABLE (arm callee enumerated)", `Verdict (["unreachable"; "root_fun"; "sink"], "REACHABLE (may-reach)"));
    (P2, "unreachable lazy_thunk island = REACHABLE (thunk callee enumerated)", `Verdict (["unreachable"; "lazy_thunk"; "island"], "REACHABLE (may-reach)"));
    (P2, "unreachable opt_default island = REACHABLE (default callee enumerated)", `Verdict (["unreachable"; "opt_default"; "island"], "REACHABLE (may-reach)"));
    (P2, "unreachable try_noreturn sink = REACHABLE (handler callee enumerated)", `Verdict (["unreachable"; "try_noreturn"; "sink"], "REACHABLE (may-reach)"));
    (P2, "unreachable lam_map island = REACHABLE (through the lambda node)", `Verdict (["unreachable"; "lam_map"; "island"], "REACHABLE (may-reach)"));
    (P2, "unreachable unused_closure island = REACHABLE (ignore h = escape occurrence)", `Verdict (["unreachable"; "unused_closure"; "island"], "REACHABLE (may-reach)"));
    (P2, "reaches invoked_closure island = must (invoked local lambda → MUST chain)", `Verdict (["reaches"; "invoked_closure"; "island"], "PATH EXISTS"));
    (P2, "unreachable dead_lambda island = UNREACHABLE (dead lambda, no ⊤)", `Verdict (["unreachable"; "dead_lambda"; "island"], "UNREACHABLE:"));
  ]

let sql_checks =
  [
    (P1, "no NULL/invalid kinds", "SELECT count(*) FROM calls WHERE kind IS NULL OR kind NOT IN ('MUST','MAY_ENUMERATED','MAY_TOP');", "0");
    (P1, "overapp_entry emits a MAY_TOP residual (over-application ⊤)", "SELECT CASE WHEN count(*)>0 THEN 'yes' ELSE 'no' END FROM calls c JOIN functions f ON c.caller_id=f.id WHERE f.name='overapp_entry' AND c.kind='MAY_TOP';", "yes");
    (P1, "letop_body records the let* operator call (MUST, not dropped)", "SELECT COALESCE(MAX(kind),'MISSING') FROM calls c JOIN functions f ON c.caller_id=f.id WHERE f.name='letop_body' AND c.callee_name='let*';", "MUST");
    (P1, "try_noreturn raise edge is MUST (the raise always runs)", "SELECT COALESCE(MAX(kind),'MISSING') FROM calls c JOIN functions f ON c.caller_id=f.id WHERE f.name='try_noreturn' AND c.callee_name LIKE '%raise';", "MUST");
    (P1, "false_arg mk_exn edge is MUST (argument evaluation runs)", "SELECT COALESCE(MAX(kind),'MISSING') FROM calls c JOIN functions f ON c.caller_id=f.id WHERE f.name='false_arg' AND c.callee_name='mk_exn';", "MUST");
    (P1, "stored_bind lambda not orphaned (has an incoming enumerated edge)", "SELECT COALESCE(MAX(c.kind),'ORPHAN') FROM calls c WHERE c.callee_name LIKE 'stored_bind.<fun:%';", "MAY_ENUMERATED");
    (P1, "letop_diverge let* edge is not MUST (operand diverges before the bind)", "SELECT COALESCE(MAX(kind),'MISSING') FROM calls c JOIN functions f ON c.caller_id=f.id WHERE f.name='letop_diverge' AND c.callee_name='let*';", "MAY_ENUMERATED");
    (P1, "beta_redex has no ⊤ edge (literal head resolved, not *TOP*)", "SELECT count(*) FROM calls c JOIN functions f ON c.caller_id=f.id WHERE f.name='beta_redex' AND c.kind='MAY_TOP';", "0");
    (P2, "after_raise sink call recorded, demoted (never dropped)", "SELECT CASE WHEN count(*)=1 AND MAX(kind)<>'MUST' THEN 'demoted' WHEN count(*)=0 THEN 'DROPPED' ELSE 'other' END FROM calls c JOIN functions f ON c.caller_id=f.id WHERE f.name='after_raise' AND c.callee_name='sink';", "demoted");
    (P2, "lam_map lambda node exists", "SELECT CASE WHEN count(*)=1 THEN 'yes' ELSE 'no' END FROM functions WHERE name LIKE 'lam_map.<fun:%';", "yes");
    (P2, "lam_map lambda → island is MUST (lambda body straight-line)", "SELECT COALESCE(MAX(c.kind),'MISSING') FROM calls c JOIN functions f ON c.caller_id=f.id WHERE f.name LIKE 'lam_map.<fun:%' AND c.callee_name='island';", "MUST");
    (P2, "lam_map parent → lambda is MAY_ENUMERATED (passed literal)", "SELECT COALESCE(MAX(c.kind),'MISSING') FROM calls c JOIN functions f ON c.caller_id=f.id WHERE f.name='lam_map' AND c.callee_name LIKE 'lam_map.<fun:%';", "MAY_ENUMERATED");
    (P2, "dead_lambda has no parent→lambda edge (never referenced)", "SELECT CASE WHEN count(*)=0 THEN 'none' ELSE 'edge' END FROM calls c JOIN functions f ON c.caller_id=f.id WHERE f.name='dead_lambda' AND c.callee_name LIKE '%<fun:%';", "none");
    (P2, "nested lambda node chains through the outer node", "SELECT CASE WHEN count(*)>=1 THEN 'yes' ELSE 'no' END FROM functions WHERE name LIKE 'nested_lam.<fun:%.<fun:%';", "yes");
  ]

let register () =
  Test.register ~__FILE__ ~title:"soundness: the dominance corpus"
    ~tags:["cmt"; "callgraph"; "soundness"]
  @@ fun () ->
  with_fixture ~name:"soundness" ~files:fixture_files @@ fun fixture ->
  let db = index fixture in
  let strict = Sys.getenv_opt "ARCH_TEZT_STRICT_P2" = Some "1" in
  let xfail = ref 0 and xpass = ref 0 in
  Batch.run (fun b ->
      let record phase ~desc ~actual ~expected =
        match phase with
        | P1 -> Batch.eq_string b ~msg:("P1: " ^ desc) actual expected
        | P2 ->
            if actual = expected then begin
              incr xpass ;
              Log.info "P2 XPASS (target already met): %s" desc
            end
            else if strict then
              Batch.note b "P2: %s: got %S, expected %S" desc actual expected
            else begin
              incr xfail ;
              Log.info "P2 xfail: %s: got %S, expected %S" desc actual expected
            end
      in
      List.iter
        (fun (phase, desc, what) ->
          match what with
          | `Verdict (args, expected) ->
              let _, out = query_raw db args in
              record phase ~desc ~actual:(verdict_token out) ~expected
          | `Refuses args ->
              let code, _ = query_raw db args in
              record phase ~desc ~actual:(if code = 3 then "REFUSED" else "NOREFUSE")
                ~expected:"REFUSED")
        verdict_checks ;
      Db.with_db db (fun conn ->
          List.iter
            (fun (phase, desc, sql, expected) ->
              let actual =
                match Db.string_opt conn sql with Some v -> v | None -> "<no row>"
              in
              record phase ~desc ~actual ~expected)
            sql_checks) ;

      (* Three checks whose shape does not fit the table. *)
      let mentions_lambda l =
        let n = String.length "<fun:" and h = String.length l in
        let found = ref false in
        for i = 0 to h - n do
          if (not !found) && String.sub l i n = "<fun:" then found := true
        done ;
        !found
      in
      Batch.ge_int b ~msg:"P1: find locates lambda nodes on the main schema"
        (List.length (List.filter mentions_lambda (lines (query db ["find"; "<fun:"]))))
        1 ;
      Batch.not_contains b ~msg:"P1: exported never lists lambda nodes"
        ~haystack:(query db ["exported"]) "<fun:" ;
      record P2 ~desc:"escapes lam_map = empty ⊤ frontier"
        ~actual:(if lines (query db ["escapes"; "lam_map"]) = [] then "empty" else "nonempty")
        ~expected:"empty") ;
  Log.info "P2: %d xfail (targets outstanding), %d xpass" !xfail !xpass ;
  Lwt.return_unit
