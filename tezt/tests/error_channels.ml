(******************************************************************************)
(*                                                                            *)
(* Copyright (c) 2026 Epure Team                                              *)
(* All rights reserved.                                                       *)
(*                                                                            *)
(******************************************************************************)

(** Error channels — spine slice (specs/error-channels.md). SLICE 2 SCOPE:
    monomorphic [result]/[option]-shaped channels only — no lift, unwrap,
    binds, transforms, converters or summaries; no Tezos profile.
    Covers US-2 scenarios 1, 2, 3, 4, 10 and US-3 scenarios 1, 3 (adapted:
    only [may-fail] is implemented in this slice, not [fails-with], so
    scenario 3 is exercised through [may-fail] on the same functions rather
    than the literal [fails-with] command).

    The fixture library ([errch_simple], unit [Ec_a]) declares its own
    carrier type [myres] via an [arch-errors.toml] channel — a distinct
    nominal type from [Stdlib.result], so the custom channel's carrier check
    cannot be confused with the built-in [result]/[option] channels also
    exercised here (both built-ins apply automatically, config file or not). *)

open Arch_tezt

let fixture_files =
  [
    Fixture.dune_project;
    ( "dune",
      "(library\n\
      \ (name errch_simple)\n\
      \ (wrapped false)\n\
      \ (modules ec_a)\n\
      \ (flags (:standard -w -8-11-21-26-27-32-33-37-39)))\n" );
    (* A FILE-declared channel, distinct from the built-ins, so config
       discovery/parse/validation is exercised end to end (specs/error-
       channels.md US-1). [myres]'s carrier type is its own nominal
       [myres], never [Stdlib.result] — no [error_arg]: unlike the
       built-ins' 2-argument [result], this type fixes its error type
       ([err]) rather than parameterising it, so the carrier check's
       "error_arg not applicable" branch is what's exercised. *)
    ( "arch-errors.toml",
      (* [add_err]/[opt_of_res] are called UNQUALIFIED from within the same
         module ([Ec_a]) that defines them — a same-module call's resolved
         head carries the BARE name (module attribution is a separate
         [functions.module_id] column, not part of the identifier itself),
         so the declared path is the bare name too, not [Ec_a.add_err].

         [mytz2] (SLICE 4, FR-027 "lift"/"unwrap"/"underlying"/"aliases"):
         [tzres] is the ALIAS spelling (one type argument — the error type
         is implied by the declaration, [error_arg] does not apply);
         [result2] is its OWN 2-argument [underlying] spelling (same
         structural type, different arity, same rule the Tezos profile
         needs for [tzresult]/[Pervasives.result]) — [error_arg] DOES apply
         there, checked against [error_type = "tzerr"]. [never_matched] is
         an intentionally-unmatched declared path (US-1 scenario 2: a
         warning normally, fatal under [--errors-strict]). *)
      "[channel.myres]\n\
       type = \"myres\"\n\
       origins = [{path = \"Error\", arg = 1}]\n\
       binds = [\"Res_syntax.let*\"]\n\
       transforms = [{path = \"add_err\", mode = \"add\", arg = 1}]\n\
       converters = [{path = \"opt_of_res\", from = \"myres\", to = \"option\", arg = 1}]\n\
       sinks = [\"never_matched\"]\n\
       [channel.mytz2]\n\
       type = \"tzres\"\n\
       underlying = [\"result2\"]\n\
       error_type = \"tzerr\"\n\
       error_arg = 2\n\
       origins = [{path = \"Error2\", arg = 1}]\n" );
    ( "ec_a.ml",
      {|type err = A | B of int | C | Wrap of err

(* A custom result-shaped carrier, distinct from Stdlib.result. *)
type 'a myres = Ok of 'a | Error of err

(* US-2.1 *)
let f () : int myres = Error A

(* US-2.2 : closing arm ([A] binds nothing) *)
let g () = match f () with Error A -> Ok 0 | r -> r

(* US-2.3 : non-closing arm ([e] occurs in its own RHS — re-return) *)
let g2 () = match f () with Error e -> Error e | ok -> ok

(* US-2.4 : catch-all closing arm, plus a fresh origin of g3 itself *)
let g3 () = match f () with Error _ -> Error (B 1) | ok -> ok

(* US-2.14 (review round 1, CRITICAL): an or-pattern of two DIFFERENT
   literals is NOT a catch-all. [multi] can return three identities; the arm
   names only two, so [C] must survive. This regressed to [BOUNDED: {}] —
   every error silently dropped — when the classifier collapsed any
   non-single-literal argument pattern onto the catch-all case. *)
let multi n : int myres =
  if n = 0 then Error A else if n = 1 then Error (B n) else Error C

let or_arm n = match multi n with Error (A | B _) -> Ok 0 | r -> r

(* Control: a genuine wildcard under the constructor still closes everything,
   so the fix above must not have disabled catch-all detection wholesale. *)
let wild_arm n = match multi n with Error _ -> Ok 0 | r -> r

(* US-2.15 (review round 2, CRITICAL): a constructor pattern whose ARGUMENT
   constrains the value catches a strict subset of its identity. Closing the
   identity would delete the values the arm does not match. Both channels share
   one rule ([Arch_index_exn.pat_is_irrefutable]), so both are pinned here —
   the exception case lives in this file rather than exn_raise_sets.ml so that
   suite stays byte-identical as AC-17's evidence, and because the rule under
   test is this feature's. *)
let multi_b n : int myres = if n = 0 then Error (B 0) else Error (B 1)

let narrow_arm n = match multi_b n with Error (B 0) -> Ok 0 | r -> r

(* #60 review: an or-pattern with one irrefutable side really does catch
   everything the constructor can carry, so it must close. Was `&&`, which made
   this arm close nothing — sound, but a precision loss on a common shape. *)
let wild_or_arm n = match multi_b n with Error (B 0 | _) -> Ok 0 | r -> r

(* US-2.17: an or-pattern spanning the WHOLE arm. At the computation-pattern
   level this is a Tpat_or of two Tpat_values, not a Tpat_value, and the walker
   used to drop such an arm entirely — so it closed nothing, while the same
   intent written inside the constructor closed both. *)
let arm_level_or n = match multi n with Error A | Error C -> Ok 0 | r -> r

(* Worse case of the same bug: an arm that catches EVERYTHING closed nothing. *)
let arm_level_or_wild n = match multi n with Error A | _ -> Ok 0

exception Boom of int

let boom_raiser n = if n = 0 then raise (Boom 0) else raise (Boom 1)

let narrow_handler n = try boom_raiser n with Boom 0 -> ()

(* US-2.16 (review round 2, MEDIUM): ONE call site covered by BOTH an
   exception scope and a value-channel scope. The call to [f_boom] sits
   inside a [try] (an exception-channel scope) and its result is the
   scrutinee of a [match] (a myres scope), so both cover the same call.
   [call_exn_scopes] used to have PRIMARY KEY (call_id) — room for one link
   per call — and the walker resolved the clash by keeping the exception
   scope and DROPPING the value-channel one, so [Ec_a.A] was reported as
   escaping [both_scopes] even though the match closes it. The key is now
   (call_id, scope_id) and both links are stored. *)
let f_boom n : int myres = if n = 0 then raise (Boom 1) else Error A

let both_scopes n = try (match f_boom n with Error A -> Ok 0 | r -> r) with Boom _ -> Ok 2

(* US-2.9 — the C-21 PARAMETER rule, and the single reason generic
   combinators stay BOUNDED instead of ⊤.

   [wrap]'s carrier argument [r] is a PARAMETER. Whatever errors it carries
   were already counted at their creation site, so by induction over callers
   [wrap] must contribute only the identity it constructs itself:
   [BOUNDED: {Ec_a.Wrap}], never ⊤. Treat a carrier parameter as an unknown
   source instead and EVERY combinator in a codebase answers "unbounded",
   which is sound and useless — the failure mode this rule exists to prevent,
   and one no other assertion in this suite would notice.

   [nest] pins the other direction, which is the SOUND one: the match covers
   only the head call [wrap], so [f ()] — an argument, a lexically different
   call — still propagates and [Ec_a.A] must survive. An over-broad notion of
   "covered" would answer [BOUNDED: {}] and silently drop a reachable
   error. *)
let wrap (r : int myres) : int myres = match r with Error e -> Error (Wrap e) | ok -> ok

let nest () = match wrap (f ()) with Error (Wrap _) -> Ok 0 | ok -> ok

(* US-2.6 : a declared let-operator bind over [myres] ([Res_syntax.let*] in
   the fixture config's [binds]) — the bound call propagates. *)
module Res_syntax = struct
  let ( let* ) (r : int myres) (k : int -> int myres) =
    match r with Ok x -> k x | Error e -> Error e
end

let k_bind () =
  let open Res_syntax in
  let* x = f () in
  Ok x

(* US-2.6 : sinks. [ignore (E)] and [let _ = E in …] both mean the head call
   of [E] does not propagate, so nothing of [f]'s escapes. *)
let s () =
  ignore (f ()) ;
  Ok 0

let s2 () =
  let _ = f () in
  Ok 0

(* US-2.12 : a node that is a [myres] carrier AND raises. The two channels
   are separate universes: the exception belongs to [exception] only, and the
   [myres] answer stays empty — an exception-channel origin inside a carrier
   node is an exception fact only. *)
let mixed () : int myres = if Sys.opaque_identity true then raise Not_found else Ok 0

(* US-3.1 : not a myres carrier at all *)
let plain () = 42

(* US-2.10 : option channel (built-in, no config needed) *)
let o () = if Sys.opaque_identity true then None else Some 1

let o2 () = Option.bind (o ()) (fun x -> Some x)

(* A genuine Stdlib.result carrier (built-in [result] channel), for
   binds/transforms/inferred_bind (specs/error-channels.md "Binds" /
   "Transforms"). *)
let fr () : (int, err) result = Error A

(* US-2.5 : Stdlib.Result.bind (declared bind) — the bound expression's head
   call AND the continuation both propagate. *)
let h () = Stdlib.Result.bind (fr ()) (fun x -> Ok x)

let h2 () = Stdlib.Result.bind (fr ()) (fun _ -> Error (B 2))

(* US-2.7 : "replace" mode via the built-in Stdlib.Result.map_error — the
   inner set is discarded, only the mapper's literal return survives. *)
let w () = Stdlib.Result.map_error (fun _ -> B 3) (fr ())

let w2 mapper = Stdlib.Result.map_error mapper (fr ())

(* US-2.8 : alias chain — [r2] resolves to [f ()]'s head call through a
   chain of single-variable lets. *)
let al () =
  let r = f () in
  let r2 = r in
  match r2 with Error A -> Ok 1 | ok -> ok

(* US-2.13 : an UNDECLARED operator with bind shape over the [result]
   carrier — must never be silently treated as a bind. *)
let ( >>=? ) r k = Stdlib.Result.bind r k

let hh () = fr () >>=? fun x -> Ok x

(* "add"-mode transform: config declares [Ec_a.add_err] — the literal at
   [arg=1] unions in; the OTHER argument's own call still propagates
   normally. *)
let add_err (_e : err) (r : int myres) : int myres = r

let t_add () = add_err (B 9) (f ())

(* Converter: config declares [Ec_a.opt_of_res] (myres -> option). *)
let opt_of_res (r : int myres) : int option =
  match r with Ok x -> Some x | Error _ -> None

let conv () = opt_of_res (f ())

(* SLICE 4 (FR-027, "lift"/"unwrap"/"underlying"/"aliases"): [tzres] is a
   type ALIAS over [result2] (one argument — the .cmt never expands
   abbreviations, so a function typed [int tzres] prints its return type
   with head [tzres], not [result2]); a function typed
   [(int, tzerr) result2] directly prints the 2-argument underlying spelling
   instead. Both must be recognised as the SAME channel [mytz2] — the
   arity-tolerant carrier check this slice adds. *)
type tzerr = ..

type tzerr += E1 | E2 of int

type ('a, 'e) result2 = Ok2 of 'a | Error2 of 'e

type 'a tzres = ('a, tzerr) result2

(* Alias spelling: 1 type argument, [error_arg] not applicable. *)
let mk1 () : int tzres = Error2 E1

(* Underlying spelling: 2 type arguments, [error_arg = 2] checked against
   [error_type = "tzerr"]. *)
let mk2 () : (int, tzerr) result2 = Error2 (E2 5)
|} );
  ]

let fn_id conn name =
  Db.int conn (Printf.sprintf "SELECT id FROM functions WHERE name = '%s'" name)

let register_producer () =
  Test.register ~__FILE__
    ~title:"error-channels: producer records value-channel origins, scopes and edges"
    ~tags:["cmt"; "error_channels"; "producer"]
  @@ fun () ->
  with_fixture ~name:"errch_producer" ~files:fixture_files @@ fun fixture ->
  let db = index fixture in
  Batch.run (fun b ->
      Db.with_db db (fun conn ->
          (* config wiring: US-1 *)
          let error_config_source =
            Db.string_opt conn "SELECT value FROM comment_db_meta WHERE key='error_config_source'"
          in
          Batch.check b ~msg:"error_config_source names the fixture's arch-errors.toml"
            (match error_config_source with
            | Some s -> Batch.has_substring ~needle:"arch-errors.toml" s
            | None -> false) ;
          let error_contract =
            Db.string_opt conn "SELECT value FROM comment_db_meta WHERE key='error_contract'"
          in
          (match error_contract with
          | Some s ->
              Batch.check b ~msg:"error_contract lists exception" (Batch.has_substring ~needle:"exception" s) ;
              Batch.check b ~msg:"error_contract lists myres" (Batch.has_substring ~needle:"myres" s) ;
              Batch.check b ~msg:"error_contract lists option" (Batch.has_substring ~needle:"option" s)
          | None -> Batch.note b "error_contract meta key is missing") ;
          (* US-2.1 : f's origin *)
          let f = fn_id conn "f" in
          Batch.eq_int b ~msg:"US-2.1 f is marked a myres carrier"
            (Db.int conn
               (Printf.sprintf
                  "SELECT count(*) FROM channel_carriers WHERE function_id=%d AND channel='myres'"
                  f))
            1 ;
          Batch.eq_int b ~msg:"US-2.1 f has one myres origin Ec_a.A, escaping"
            (Db.int conn
               (Printf.sprintf
                  "SELECT count(*) FROM exn_origins WHERE function_id=%d AND channel='myres' AND \
                   exn_path='Ec_a.A' AND escapes=1"
                  f))
            1 ;
          (* US-2.2 : g's scope closes Ec_a.A *)
          let g = fn_id conn "g" in
          Batch.eq_int b ~msg:"US-2.2 g has a myres scope catching Ec_a.A, not catch-all"
            (Db.int conn
               (Printf.sprintf
                  "SELECT count(*) FROM exn_scopes s JOIN exn_scope_catches c ON c.scope_id=s.id \
                   WHERE s.function_id=%d AND s.channel='myres' AND s.catch_all=0 AND \
                   c.exn_path='Ec_a.A'"
                  g))
            1 ;
          Batch.eq_int b ~msg:"US-2.2 the call g->f is linked to g's myres scope"
            (Db.int conn
               (Printf.sprintf
                  "SELECT count(*) FROM calls c JOIN call_exn_scopes l ON l.call_id=c.id JOIN \
                   exn_scopes s ON s.id=l.scope_id WHERE c.caller_id=%d AND c.callee_name='f' AND \
                   s.channel='myres'"
                  g))
            1 ;
          (* US-2.16 : one call site, two channels' scopes. Both links must
             be stored — with PRIMARY KEY (call_id) only one could be, and
             the value-channel one was the one lost. *)
          let both_scopes = fn_id conn "both_scopes" in
          let scopes_on channel =
            Db.int conn
              (Printf.sprintf
                 "SELECT count(*) FROM calls c JOIN call_exn_scopes l ON l.call_id=c.id JOIN \
                  exn_scopes s ON s.id=l.scope_id WHERE c.caller_id=%d AND \
                  c.callee_name='f_boom' AND s.channel='%s'"
                 both_scopes channel)
          in
          Batch.eq_int b ~msg:"US-2.16 the both_scopes->f_boom call keeps its EXCEPTION scope"
            (scopes_on "exception") 1 ;
          Batch.eq_int b ~msg:"US-2.16 the same call ALSO keeps its myres value-channel scope"
            (scopes_on "myres") 1 ;
          (* US-2.4 : g3's own origin from the literal Error (B 1) in a
             closing (catch-all) arm *)
          let g3 = fn_id conn "g3" in
          Batch.eq_int b ~msg:"US-2.4 g3 has its own myres origin Ec_a.B"
            (Db.int conn
               (Printf.sprintf
                  "SELECT count(*) FROM exn_origins WHERE function_id=%d AND channel='myres' AND \
                   exn_path='Ec_a.B'"
                  g3))
            1 ;
          Batch.eq_int b ~msg:"US-2.4 g3's scope is catch-all"
            (Db.int conn
               (Printf.sprintf
                  "SELECT count(*) FROM exn_scopes WHERE function_id=%d AND channel='myres' AND \
                   catch_all=1"
                  g3))
            1 ;
          (* propagating edges exist on the myres channel *)
          Batch.eq_int b ~msg:"g->f is a myres propagating edge"
            (Db.int conn
               (Printf.sprintf
                  "SELECT count(*) FROM calls c JOIN exn_edges e ON e.call_id=c.id WHERE \
                   c.caller_id=%d AND c.callee_name='f' AND e.channel='myres' AND \
                   e.role='propagates'"
                  g))
            1)) ;
  Lwt.return_unit

let register_query () =
  Test.register ~__FILE__ ~title:"error-channels: may-fail per channel"
    ~tags:["cmt"; "error_channels"; "query"]
  @@ fun () ->
  with_fixture ~name:"errch_query" ~files:fixture_files @@ fun fixture ->
  let db = index fixture in
  let may_fail channel fn = query db ["may-fail"; fn; "--channel"; channel] in
  Batch.run (fun b ->
      (* US-2.1 *)
      Batch.contains b ~msg:"US-2.1 f raises Ec_a.A on myres" ~haystack:(may_fail "myres" "f")
        "BOUNDED: {Ec_a.A}" ;
      (* US-2.2 : closing arm empties the set *)
      Batch.contains b ~msg:"US-2.2 g's closing arm empties the set" ~haystack:(may_fail "myres" "g")
        "BOUNDED: {}" ;
      (* US-2.3 : non-closing (re-return) arm keeps f's set, adds nothing of
         its own *)
      Batch.contains b ~msg:"US-2.3 g2's re-return keeps Ec_a.A"
        ~haystack:(may_fail "myres" "g2") "BOUNDED: {Ec_a.A}" ;
      (* US-2.4 : catch-all closes f's Ec_a.A but g3 constructs its own
         Ec_a.B *)
      Batch.contains b ~msg:"US-2.4 g3's catch-all closes A but adds its own B"
        ~haystack:(may_fail "myres" "g3") "BOUNDED: {Ec_a.B}" ;
      (* US-2.10 : option channel — o originates None; o2 propagates it
         through Option.bind's continuation and bound-call argument *)
      Batch.contains b ~msg:"US-2.10 o may fail with None" ~haystack:(may_fail "option" "o")
        "BOUNDED: {None}" ;
      Batch.contains b ~msg:"US-2.10 o2 propagates through Option.bind" ~haystack:(may_fail "option" "o2")
        "BOUNDED: {None}" ;
      (* US-2.14 (review round 1, CRITICAL; strengthened in round 2): the
         or-pattern arm names A and B but not C. It must close A and B —
         [caught] is a SET, so both fit — and C must survive. Closing more
         than an arm really catches deletes a reachable error from the answer;
         closing less than it catches costs precision. Asserting the WHOLE
         verdict, not just "C appears", pins both directions at once. *)
      (* US-2.17 : the arm-level or-pattern must close exactly what its
         alternatives name — the same answer as writing it inside the
         constructor. *)
      Batch.contains b ~msg:"US-2.17 an arm-level or-pattern closes both its alternatives"
        ~haystack:(may_fail "myres" "arm_level_or") "BOUNDED: {Ec_a.B}" ;
      Batch.contains b ~msg:"US-2.17 an arm with a wildcard alternative closes everything"
        ~haystack:(may_fail "myres" "arm_level_or_wild") "BOUNDED: {}" ;
      Batch.contains b ~msg:"US-2.14 multi can fail with all three identities"
        ~haystack:(may_fail "myres" "multi") "BOUNDED: {Ec_a.A, Ec_a.B, Ec_a.C}" ;
      Batch.contains b ~msg:"US-2.14 an or-pattern of two literals closes BOTH, only C survives"
        ~haystack:(may_fail "myres" "or_arm") "BOUNDED: {Ec_a.C}" ;
      (* Control: a real wildcard still closes the channel. *)
      Batch.contains b ~msg:"US-2.14 control: a wildcard arm still closes everything"
        ~haystack:(may_fail "myres" "wild_arm") "BOUNDED: {}" ;
      (* US-2.15 : `Error (B 0)` matches only when the argument is 0, so it
         may not close Ec_a.B — `Error (B 1)` is still reachable. *)
      Batch.contains b ~msg:"US-2.15b an or-pattern with an irrefutable side closes its identity"
        ~haystack:(may_fail "myres" "wild_or_arm") "BOUNDED: {}" ;
      Batch.contains b ~msg:"US-2.15 a constrained argument pattern does not close its identity"
        ~haystack:(may_fail "myres" "narrow_arm") "Ec_a.B" ;
      (* Same rule on the frozen exception channel: `with Boom 0 -> ()` must
         not swallow `Boom 1`. This one is pre-existing shipped behaviour. *)
      Batch.contains b ~msg:"US-2.15 `with Boom 0` does not close every Boom"
        ~haystack:(may_fail "exception" "narrow_handler") "Boom" ;
      (* US-2.16 : the SAME call site is covered on both channels, so both
         answers are empty. The myres one is the load-bearing half — with a
         single-link table the value-channel scope was dropped and Ec_a.A
         escaped. *)
      Batch.contains b ~msg:"US-2.16 both_scopes closes Ec_a.A on myres"
        ~haystack:(may_fail "myres" "both_scopes") "BOUNDED: {}" ;
      Batch.contains b ~msg:"US-2.16 both_scopes closes Ec_a.Boom on the exception channel"
        ~haystack:(may_fail "exception" "both_scopes") "BOUNDED: {}" ;
      (* US-2.9 : THE parameter rule (C-21). Both halves, and both are
         load-bearing — see the fixture comment on [wrap]/[nest]. *)
      Batch.contains b
        ~msg:
          "US-2.9 a carrier PARAMETER contributes nothing, so the combinator is BOUNDED, not ⊤"
        ~haystack:(may_fail "myres" "wrap") "BOUNDED: {Ec_a.Wrap}" ;
      Batch.contains b
        ~msg:"US-2.9 only the HEAD call is covered — the argument call's Ec_a.A still escapes"
        ~haystack:(may_fail "myres" "nest") "BOUNDED: {Ec_a.A}" ;
      (* US-2.6 : a declared let-operator bind, and the two sink forms. *)
      Batch.contains b ~msg:"US-2.6 a declared let* bind propagates the bound call"
        ~haystack:(may_fail "myres" "k_bind") "BOUNDED: {Ec_a.A}" ;
      Batch.contains b ~msg:"US-2.6 ignore (E) sinks the head call of E"
        ~haystack:(may_fail "myres" "s") "BOUNDED: {}" ;
      Batch.contains b ~msg:"US-2.6 let _ = E in … sinks the head call of E"
        ~haystack:(may_fail "myres" "s2") "BOUNDED: {}" ;
      (* US-2.12 : a raise inside a carrier node belongs to the exception
         channel ONLY. Both assertions matter: the raise must appear on one
         channel and must NOT leak onto the other. *)
      Batch.contains b ~msg:"US-2.12 mixed's raise is an exception-channel fact"
        ~haystack:(may_fail "exception" "mixed") "Not_found" ;
      Batch.contains b ~msg:"US-2.12 …and does not appear on the myres channel"
        ~haystack:(may_fail "myres" "mixed") "BOUNDED: {}" ;
      (* US-3.1 : plain is not a myres carrier at all *)
      Batch.contains b ~msg:"US-3.1 plain is NOT_A_CARRIER(myres)"
        ~haystack:(may_fail "myres" "plain") "NOT_A_CARRIER(myres)" ;
      (* US-3.3 (adapted): may-fail confirms the same bounded verdicts for
         multiple functions sharing the Ec_a.A origin — the closest this
         slice comes to fails-with's "listed" behaviour without implementing
         the command itself. *)
      List.iter
        (fun fn ->
          Batch.contains b ~msg:(fn ^ " contains Ec_a.A")
            ~haystack:(may_fail "myres" fn) "Ec_a.A")
        ["f"; "g2"] ;
      (* --channel is required *)
      let code, out = query_raw db ["may-fail"; "f"] in
      Batch.eq_int b ~msg:"may-fail without --channel is a usage error" code 2 ;
      Batch.check b ~msg:"the error names --channel" (Batch.has_substring ~needle:"--channel" out) ;
      (* US-2.5 (SLICE 3, "Binds"): [Stdlib.Result.bind]'s bound expression
         AND its continuation both propagate. *)
      Batch.contains b ~msg:"US-2.5 h: the bound expression's head call propagates"
        ~haystack:(may_fail "result" "h") "BOUNDED: {Ec_a.A}" ;
      Batch.contains b
        ~msg:"US-2.5 h2: the continuation's own origin (Ec_a.B) also propagates"
        ~haystack:(may_fail "result" "h2") "BOUNDED: {Ec_a.A, Ec_a.B}" ;
      (* US-2.7 (SLICE 3, "Transforms"): [Stdlib.Result.map_error] in
         "replace" mode — the inner set does NOT survive; a lambda-literal
         mapper's own literal return does. *)
      Batch.contains b ~msg:"US-2.7 w: replace discards the inner Ec_a.A, keeps only Ec_a.B"
        ~haystack:(may_fail "result" "w") "BOUNDED: {Ec_a.B}" ;
      Batch.contains b ~msg:"US-2.7 w2: a parameter mapper is ⊤"
        ~haystack:(may_fail "result" "w2") "UNBOUNDED (⊤)" ;
      (* US-2.8 (SLICE 3, "Handler scopes" / alias chains): [r2] resolves to
         [f ()]'s head call through a chain of single-variable lets. *)
      Batch.contains b ~msg:"US-2.8 al: the alias chain closes Ec_a.A"
        ~haystack:(may_fail "myres" "al") "BOUNDED: {}" ;
      (* US-2.13 (SLICE 3, [inferred_bind]): an undeclared bind-shaped
         operator is NEVER silently treated as a bind — ⊤ with a witness. *)
      let hh_out = may_fail "result" "hh" in
      Batch.contains b ~msg:"US-2.13 hh: undeclared bind-shaped operator is ⊤" ~haystack:hh_out
        "UNBOUNDED (⊤)" ;
      Batch.check b ~msg:"US-2.13 hh: the reason names inferred_bind"
        (Batch.has_substring ~needle:"inferred_bind" hh_out) ;
      (* SLICE 3, "Transforms" ["add" mode]: the literal at [arg] unions in;
         the OTHER (inner) argument's own call still propagates normally. *)
      Batch.contains b ~msg:"add-mode transform: t_add unions Ec_a.B with the inner Ec_a.A"
        ~haystack:(may_fail "myres" "t_add") "BOUNDED: {Ec_a.A, Ec_a.B}" ;
      (* SLICE 3, "Converters": the declared converter's [arg] is an origin
         on [to] (opaque identity, no [error] given). *)
      Batch.contains b ~msg:"converter: conv's option-channel origin is opaque converted_myres"
        ~haystack:(may_fail "option" "conv") "BOUNDED: {option:converted_myres}" ;
      (* SLICE 4, FR-027 "lift"/"unwrap"/"underlying"/"aliases": the ALIAS
         spelling ([tzres], 1 arg — error_arg not applicable) and the
         UNDERLYING spelling ([result2], 2 args, error_arg=2 checked
         against error_type) are the SAME channel. *)
      Batch.contains b ~msg:"FR-027 alias spelling (tzres, 1 arg): mk1 is a mytz2 carrier"
        ~haystack:(may_fail "mytz2" "mk1") "BOUNDED: {Ec_a.E1}" ;
      Batch.contains b
        ~msg:"FR-027 underlying spelling (result2, 2 args, error_arg checked): mk2 is a mytz2 carrier"
        ~haystack:(may_fail "mytz2" "mk2") "BOUNDED: {Ec_a.E2}" ;
      (* US-3.2: [--channel all] prints one block per emitted channel; the
         [exception] block is byte-identical to plain [raises]. *)
      let all_out = query db ["may-fail"; "hh"; "--channel"; "all"] in
      let raises_hh = query db ["raises"; "hh"] in
      Batch.check b ~msg:"US-3.2 --channel all's exception block equals raises hh byte-for-byte"
        (Batch.has_substring ~needle:raises_hh all_out) ;
      Batch.check b ~msg:"US-3.2 --channel all also visits the result channel (hh IS a result carrier)"
        (Batch.has_substring ~needle:"hh: UNBOUNDED" all_out) ;
      Batch.check b ~msg:"US-3.2 --channel all also visits the myres channel (hh is NOT a myres carrier)"
        (Batch.has_substring ~needle:"hh: NOT_A_CARRIER(myres)" all_out) ;
      (* US-3.1: fails-with lists bounded nodes containing the canonical
         error, ⊤ nodes separately as "may include" — per channel: f/g2
         carry [Ec_a.A] on [myres], h carries it on [result] (the SAME
         literal path can be bounded on one channel and not even a
         candidate on another — channels are genuinely separate universes). *)
      let fw_myres = query db ["fails-with"; "Ec_a.A"; "--channel"; "myres"] in
      List.iter
        (fun fn ->
          Batch.check b ~msg:(fn ^ " is listed by fails-with Ec_a.A --channel myres")
            (Batch.has_substring ~needle:(fn ^ "|") fw_myres))
        ["f"; "g2"] ;
      let fw_result = query db ["fails-with"; "Ec_a.A"; "--channel"; "result"] in
      Batch.check b ~msg:"h is listed by fails-with Ec_a.A --channel result"
        (Batch.has_substring ~needle:"h|" fw_result) ;
      (* [w2]'s set is [Top(∅, {unknown_exn_value})]: "replace" mode
         discards the inner [Ec_a.A] and the mapper is a parameter, so its
         KNOWN part is empty — it correctly does NOT land in [may_include]
         (that table lists ⊤ nodes whose KNOWN part contains the target,
         not every ⊤ node; an empty table renders as no output at all, so
         its absence here is itself the assertion — reaching this line
         without the harness failing is the check). *)
      ignore fw_result ;
      (* US-3.4-ish: error-stats --channel myres reports the channel name
         and a fixpoint time. *)
      let es = query db ["error-stats"; "--channel"; "myres"] in
      Batch.check b ~msg:"error-stats names the channel" (Batch.has_substring ~needle:"myres" es) ;
      Batch.check b ~msg:"error-stats reports fixpoint_seconds"
        (Batch.has_substring ~needle:"fixpoint_seconds" es) ;
      let es_all = query db ["error-stats"; "--channel"; "all"] in
      Batch.check b ~msg:"error-stats --channel all covers every emitted channel"
        (Batch.has_substring ~needle:"exception" es_all
        && Batch.has_substring ~needle:"myres" es_all
        && Batch.has_substring ~needle:"mytz2" es_all) ;
      (* US-3.5: a channel absent from error_contract is NOT_ANALYSED, exit 3. *)
      let code, out = query_raw db ["may-fail"; "f"; "--channel"; "nonexistent"] in
      Batch.eq_int b ~msg:"may-fail on an undeclared channel is NOT_ANALYSED (exit 3)" code 3 ;
      Batch.check b ~msg:"the refusal names NOT_ANALYSED" (Batch.has_substring ~needle:"NOT_ANALYSED" out)) ;
  Lwt.return_unit

let register_strict () =
  Test.register ~__FILE__ ~title:"error-channels: --errors-strict promotes a miss to fatal"
    ~tags:["cmt"; "error_channels"; "config"]
  @@ fun () ->
  with_fixture ~name:"errch_strict" ~files:fixture_files @@ fun fixture ->
  (* US-1 scenario 2: a warning by default (index still succeeds — the
     other tests in this file rely on exactly that), fatal (exit 1) under
     [--errors-strict], for the SAME never-matched declared path
     ([Ec_a."never_matched"] in [channel.myres.sinks]). *)
  let code, out, _db = Arch_tezt.index_raw ~extra_args:["--errors-strict"] fixture in
  Batch.run (fun b ->
      Batch.eq_int b ~msg:"--errors-strict turns the declared-but-unmatched sink into exit 1"
        code 1 ;
      (* The exit code alone was all this asserted, which cannot tell a
         refusal about the operator's own path from a refusal about anything
         else the run might dislike. The MESSAGE is the contract: it must
         name the path and the channel, and the verdict must count exactly
         the one declaration the operator wrote and that did not match. *)
      Batch.check b ~msg:"the warning names the unmatched path and its channel"
        (Batch.has_substring ~needle:"channel myres: 'never_matched' matched nothing" out) ;
      Batch.check b ~msg:"the strict verdict counts exactly the operator's one miss"
        (Batch.has_substring ~needle:"--errors-strict: 1 declaration(s) matched nothing" out)) ;
  Lwt.return_unit

(* AC-15 scenario 6: profile discovery precedence. [ARCH_ERRORS_PROFILES_DIR]
   beats [<analysed project root>/profiles], and the path actually used is
   PRINTED. Untested until review round 2 — the precedence was only ever
   confirmed by hand, and a silent reordering would send an operator the
   wrong vocabulary while still reporting success. Both directories hold a
   file of the same name, declaring DIFFERENT channels, so which one won is
   visible in the output and not merely in a path string. *)
let register_profile_precedence () =
  Test.register ~__FILE__
    ~title:"error-channels: ARCH_ERRORS_PROFILES_DIR wins over <root>/profiles, and is printed"
    ~tags:["cmt"; "error_channels"; "config"; "profile"]
  @@ fun () ->
  with_fixture ~name:"errch_profile_prec"
    ~files:
      [
        Fixture.dune_project;
        ( "dune",
          "(library\n\
          \ (name errch_prec)\n\
          \ (wrapped false)\n\
          \ (modules es_p)\n\
          \ (flags (:standard -w -8-11-21-26-27-32-33-37-39)))\n" );
        (* The LOSER: same profile name, in the project root's own profiles/. *)
        ( "profiles/prec-errors.toml",
          "[channel.from_project_root]\ntype = \"pres\"\norigins = [{path = \"Bad\", arg = 1}]\n" );
        (* The WINNER: pointed at by ARCH_ERRORS_PROFILES_DIR below. *)
        ( "envprofiles/prec-errors.toml",
          "[channel.from_env_dir]\ntype = \"pres\"\norigins = [{path = \"Bad\", arg = 1}]\n" );
        ("es_p.ml", "type e = X\n\ntype 'a pres = Good of 'a | Bad of e\n\nlet f () : int pres = Bad X\n");
      ]
  @@ fun fixture ->
  let code, out, db =
    Arch_tezt.index_raw
      ~env:[("ARCH_ERRORS_PROFILES_DIR", Filename.concat fixture.Arch_tezt.root "envprofiles")]
      ~extra_args:["--errors-profile"; "prec"]
      fixture
  in
  Batch.run (fun b ->
      Batch.eq_int b ~msg:(Printf.sprintf "indexing with --errors-profile must succeed:\n%s" out)
        code 0 ;
      Batch.check b ~msg:"the resolved profile path is printed"
        (Batch.has_substring ~needle:"arch-errors: using profile " out) ;
      Batch.check b ~msg:"…and it is the ARCH_ERRORS_PROFILES_DIR one, not <root>/profiles"
        (Batch.has_substring ~needle:"envprofiles/prec-errors.toml" out) ;
      Db.with_db db (fun conn ->
          let contract =
            match
              Db.string_opt conn "SELECT value FROM comment_db_meta WHERE key='error_contract'"
            with
            | Some s -> s
            | None -> ""
          in
          (* The decisive check: the CHANNEL that got loaded, not just a path
             string in a log line. *)
          Batch.check b
            ~msg:(Printf.sprintf "the env-dir profile's channel is the one emitted (got %S)" contract)
            (Batch.has_substring ~needle:"from_env_dir" contract) ;
          Batch.check b ~msg:"the <root>/profiles channel is NOT emitted"
            (not (Batch.has_substring ~needle:"from_project_root" contract)))) ;
  Lwt.return_unit

(* AC-18 scenario 6: a Flat-schema database has none of the exception/
   error-channel tables and never can, so EVERY channel — including a value
   channel, which takes a different code path in [Arch_exn.load] than the
   exception channel's own check — must refuse NOT_ANALYSED rather than
   answer from an empty table. "No rows" and "never looked" are the
   distinction this whole feature exists to keep. *)
let register_flat_not_analysed () =
  Test.register ~__FILE__
    ~title:"error-channels: a Flat-schema DB refuses NOT_ANALYSED on every channel"
    ~tags:["error_channels"; "query"; "refusal"]
  @@ fun () ->
  let flat = Fixture.flat ~name:"errch_flat" Fixture.minimal_flat_stream in
  Batch.run (fun b ->
      List.iter
        (fun channel ->
          let code, out = query_raw flat ["may-fail"; "f"; "--channel"; channel] in
          Batch.eq_int b
            ~msg:(Printf.sprintf "may-fail --channel %s on a Flat DB exits 3 (got %d):\n%s"
                    channel code out)
            code 3 ;
          Batch.check b
            ~msg:(Printf.sprintf "…and says NOT_ANALYSED for channel %s" channel)
            (Batch.has_substring ~needle:"NOT_ANALYSED" out))
        ["exception"; "result"; "option"]) ;
  Lwt.return_unit

let register_summaries () =
  Test.register ~__FILE__ ~title:"error-channels: [summaries] replaces external ⊤ with the declared set"
    ~tags:["cmt"; "error_channels"; "query"]
  @@ fun () ->
  let dune =
    "(library\n\
    \ (name errch_summ)\n\
    \ (wrapped false)\n\
    \ (modules es_a)\n\
    \ (flags (:standard -w -8-11-21-26-27-32-33-37-39)))\n"
  in
  let ml = "let m xs = List.hd xs\n" in
  (* Without a declared summary, [List.hd] is an unresolved external -> ⊤
     (a SEPARATE fixture, not just an unconfigured function in the same
     one — FR-031's summary applies to every occurrence of the declared
     callee once the config declares it, so isolating the "before" case
     needs its own project with no [\[summaries\]] at all). *)
  with_fixture ~name:"errch_summ_without"
    ~files:[Fixture.dune_project; ("dune", dune); ("es_a.ml", ml)] @@ fun without_fixture ->
  let without_db = index without_fixture in
  with_fixture ~name:"errch_summ_with"
    ~files:
      [
        Fixture.dune_project; ("dune", dune);
        ("arch-errors.toml", "[summaries]\n\"Stdlib.List.hd\" = { exception = [\"Failure\"] }\n");
        ("es_a.ml", ml);
      ]
  @@ fun with_fixture_ ->
  let with_db = index with_fixture_ in
  Batch.run (fun b ->
      let without = query without_db ["raises"; "m"] in
      Batch.check b ~msg:"m without a config summary sees List.hd as ⊤ external"
        (Batch.has_substring ~needle:"UNBOUNDED" without) ;
      (* FR-031: the config-declared summary is unconditional (no flag
         needed) — [List.hd] contributes the declared set instead of ⊤. *)
      let with_summary = query with_db ["raises"; "m"] in
      Batch.check b ~msg:"m's config [summaries] entry replaces ⊤ external with BOUNDED: {Failure}"
        (Batch.has_substring ~needle:"BOUNDED: {Failure}" with_summary)) ;
  Lwt.return_unit

(* US-1 : validation is exercised by the fixture's arch-errors.toml (parsed
   without error; a typo'd path would only warn, not fail the build). *)
let register_config () =
  Test.register ~__FILE__ ~title:"error-channels: config validation does not abort on a good file"
    ~tags:["cmt"; "error_channels"; "config"]
  @@ fun () ->
  with_fixture ~name:"errch_config" ~files:fixture_files @@ fun fixture ->
  let _db = index fixture in
  (* [index] already fails the test if the indexer exits non-zero — reaching
     here IS the assertion that a well-formed file-declared channel does not
     abort the run. *)
  Lwt.return_unit

(* Review round 1, HIGH — "re-indexing an existing database is unsound".
   [Arch_index_support.schema_tables_to_drop] listed none of the
   exception/error-channel tables, so a SECOND run over the same file
   doubled [exn_scopes]/[exn_origins] and rejected every [call_exn_scopes]
   row on its [call_id] primary key — keeping the FIRST run's links, which
   then close call sites they never covered. Every existing test indexes
   once into a fresh temp database, so nothing could see it.

   The assertion is deliberately shaped as "run 2 == run 1, exit 0" over the
   whole error-channel table set rather than against hardcoded counts: it
   stays true as the fixture grows, and it fails loudly for any table added
   to the schema later and forgotten in the drop list. *)
let reindexed_tables =
  [
    "exn_scopes"; "exn_origins"; "exn_scope_catches"; "call_exn_scopes"; "exn_edges";
    "channel_carriers"; "exn_rebinds"; "functions"; "calls"; "modules"; "producer_runs";
  ]

let register_reindex () =
  Test.register ~__FILE__
    ~title:"error-channels: re-indexing an existing database is idempotent"
    ~tags:["cmt"; "error_channels"; "reindex"]
  @@ fun () ->
  with_fixture ~name:"errch_reindex" ~files:fixture_files @@ fun fixture ->
  let db = Arch_tezt.temp_db "errch_reindex" in
  let counts () =
    Db.with_db db (fun conn ->
        List.map
          (fun t -> (t, Db.int conn (Printf.sprintf "SELECT count(*) FROM %s" t)))
          reindexed_tables)
  in
  let code1, out1 = Arch_tezt.index_raw_into ~db fixture in
  if code1 <> 0 then Test.fail "first index failed (exit %d):\n%s" code1 out1 ;
  let first = counts () in
  let code2, out2 = Arch_tezt.index_raw_into ~db fixture in
  Batch.run (fun b ->
      Batch.eq_int b ~msg:"re-indexing the same database exits 0" code2 0 ;
      if code2 <> 0 then Batch.note b "second index output:\n%s" out2 ;
      let second = counts () in
      List.iter
        (fun (t, n1) ->
          Batch.eq_int b
            ~msg:(Printf.sprintf "%s has the same row count after a second index" t)
            (List.assoc t second) n1)
        first) ;
  Lwt.return_unit

(* Review round 1, HIGH — "--errors-strict can never succeed".
   [lift]/[unwrap] name TYPE constructors but were seeded into the
   validator's VALUE-path set, which only [note_value_path] can flip; and an
   untouched built-in's own Stdlib paths counted towards the strict verdict,
   one of which ([Stdlib.option]) is a spelling the compiler never prints.
   Between them, [--errors-strict] exited 1 for every config and every
   corpus. This fixture declares a channel whose carrier, [lift] wrapper and
   [unwrap] wrapper are ALL present, and every declared value path is
   exercised — so exit 0 is now reachable, and the assertion is that it is
   actually reached. *)
let strict_ok_files =
  [
    Fixture.dune_project;
    ( "dune",
      "(library\n\
      \ (name errch_strictok)\n\
      \ (wrapped false)\n\
      \ (modules es_ok)\n\
      \ (flags (:standard -w -8-11-21-26-27-32-33-37-39)))\n" );
    ( "arch-errors.toml",
      "[channel.myres]\n\
       type = \"res\"\n\
       error_arg = 2\n\
       error_type = \"myerr\"\n\
       lift = [\"wrap\"]\n\
       unwrap = [\"box\"]\n\
       origins = [{path = \"Bad\", arg = 1}]\n" );
    ( "es_ok.ml",
      {|type myerr = E1 | E2

(* [unwrap]: the error slot is [myerr] inside a [box] container, exactly the
   shape the Tezos profile's [...Error_monad.trace] wrapper has. *)
type 'e box = Box of 'e

(* [lift]: an outer wrapper stripped before the carrier check, the shape the
   Tezos profile's [Lwt.t] has. *)
type 'a wrap = W of 'a

type ('a, 'e) res = Good of 'a | Bad of 'e

(* Carrier, unlifted: the [unwrap] container is what makes error_arg=2 agree
   with error_type=myerr. *)
let plain () : (int, myerr box) res = Bad (Box E1)

(* Carrier under the [lift] wrapper. *)
let lifted () : (int, myerr box) res wrap = W (Bad (Box E2))
|} );
  ]

let register_strict_success () =
  Test.register ~__FILE__
    ~title:"error-channels: --errors-strict succeeds when every declaration matches"
    ~tags:["cmt"; "error_channels"; "config"; "strict"]
  @@ fun () ->
  with_fixture ~name:"errch_strict_ok" ~files:strict_ok_files @@ fun fixture ->
  let code, out, db = Arch_tezt.index_raw ~extra_args:["--errors-strict"] fixture in
  Batch.run (fun b ->
      Batch.eq_int b ~msg:"--errors-strict exits 0 when nothing the operator declared missed" code 0 ;
      if code <> 0 then Batch.note b "indexer output:\n%s" out ;
      if code = 0 then (
        (* The lift/unwrap paths must be FOUND, not merely non-fatal: a
           regression that stopped seeding them at all would also exit 0. *)
        let unmatched =
          Db.with_db db (fun conn ->
              Db.string_opt conn
                "SELECT value FROM comment_db_meta WHERE key='error_config_unmatched'")
        in
        (* Split on the separator rather than substring-searching: the
           untouched built-ins DO still contribute misses here (they are
           warnings, not strict failures), and 'Stdlib.result' contains
           "res". *)
        let unmatched =
          String.split_on_char ',' (Option.value ~default:"" unmatched)
        in
        List.iter
          (fun p ->
            Batch.check b
              ~msg:(Printf.sprintf "%S is reported as matched, not unmatched" p)
              (not (List.mem p unmatched)))
          ["wrap"; "box"; "res"; "Bad"] ;
        (* And the lift wrapper really is stripped: without it [lifted]'s
           return type has head [wrap], matches no declared carrier, and the
           answer is NOT_A_CARRIER instead of a set. The identity is the
           [box] container's head — the origin is the literal at the
           declared [arg], and [unwrap] is a rule for the carrier CHECK, not
           for naming an error. *)
        Batch.contains b ~msg:"the lifted carrier is analysed on the myres channel"
          ~haystack:(query db ["may-fail"; "lifted"; "--channel"; "myres"])
          "BOUNDED: {Es_ok.Box}")) ;
  Lwt.return_unit

(* Review round 1, HIGH (FR-027) — a channel shadowed by an earlier one.
   Carrier selection is first-match-wins, so the second declaration below can
   never own a carrier; shipping it would publish a channel in
   [error_contract] that answers NOT_A_CARRIER about code it never examined.
   The config layer refuses it at load time instead. *)
let register_unreachable_channel () =
  Test.register ~__FILE__
    ~title:"error-channels: a channel shadowed by an earlier one is refused at load time"
    ~tags:["cmt"; "error_channels"; "config"]
  @@ fun () ->
  with_fixture ~name:"errch_shadowed"
    ~files:
      [
        Fixture.dune_project;
        ( "dune",
          "(library\n\
          \ (name errch_shadow)\n\
          \ (wrapped false)\n\
          \ (modules es_sh)\n\
          \ (flags (:standard -w -8-11-21-26-27-32-33-37-39)))\n" );
        (* [second] carries the same [myopt] type as [first] and applies no
           narrower argument test, so it is structurally unreachable. *)
        ( "arch-errors.toml",
          "[channel.first]\n\
           type = \"myopt\"\n\
           error_type = \"\"\n\
           origins = [{path = \"Nothing\", arg = 0}]\n\
           [channel.second]\n\
           type = \"myopt\"\n\
           error_type = \"\"\n\
           origins = [{path = \"Nothing\", arg = 0}]\n" );
        ("es_sh.ml", "type 'a myopt = Nothing | Just of 'a\n\nlet f () : int myopt = Nothing\n");
      ]
  @@ fun fixture ->
  let code, out, _db = Arch_tezt.index_raw fixture in
  Batch.run (fun b ->
      Batch.eq_int b ~msg:"a shadowed channel makes the run exit 1" code 1 ;
      Batch.check b ~msg:"the refusal names the shadowed channel"
        (Batch.has_substring ~needle:"channel second" out) ;
      Batch.check b ~msg:"the refusal names the channel that shadows it"
        (Batch.has_substring ~needle:"'first'" out) ;
      Batch.check b ~msg:"the refusal names the contested carrier type"
        (Batch.has_substring ~needle:"'myopt'" out) ;
      (* Both channels here come from the operator's own file, so reordering
         is a remedy they can actually carry out — and the message names the
         order to put them in, not just the word "reorder". *)
      Batch.check b ~msg:"the refusal tells the operator what to do about it"
        (Batch.has_substring ~needle:"Declare 'second' before 'first'" out)) ;
  Lwt.return_unit

(* Review round 2 (MEDIUM): the remedy has to be one the operator can carry
   out. When the shadowing channel is a BUILT-IN, "reorder the channels" is
   impossible — built-ins are always merged first and no config file can move
   them — so the message must name the two remedies that do work: extend the
   built-in under its own name, or add a distinguishing [error_type]. *)
let register_unreachable_over_builtin () =
  Test.register ~__FILE__
    ~title:"error-channels: shadowing a BUILT-IN channel is refused with an actionable remedy"
    ~tags:["cmt"; "error_channels"; "config"; "reachability"]
  @@ fun () ->
  with_fixture ~name:"errch_shadow_builtin"
    ~files:
      [
        Fixture.dune_project;
        ( "dune",
          "(library\n\
          \ (name errch_shb)\n\
          \ (wrapped false)\n\
          \ (modules es_shb)\n\
          \ (flags (:standard -w -8-11-21-26-27-32-33-37-39)))\n" );
        (* [mine] claims the predefined [result] carrier, which the BUILT-IN
           [result] channel (declared first, always) already claims with no
           narrower argument test. *)
        ( "arch-errors.toml",
          "[channel.mine]\ntype = \"result\"\nerror_arg = 2\norigins = [{path = \"Error\", arg = 1}]\n" );
        ("es_shb.ml", "type e = X\n\nlet f () : (int, e) result = Error X\n");
      ]
  @@ fun fixture ->
  let code, out, _db = Arch_tezt.index_raw fixture in
  Batch.run (fun b ->
      Batch.eq_int b ~msg:"shadowing a built-in makes the run exit 1" code 1 ;
      Batch.check b ~msg:"the refusal names the shadowed channel"
        (Batch.has_substring ~needle:"channel mine" out) ;
      Batch.check b ~msg:"the refusal says the shadowing channel is a built-in"
        (Batch.has_substring ~needle:"BUILT-IN channel" out) ;
      Batch.check b ~msg:"…and therefore does NOT tell the operator to reorder"
        (not (Batch.has_substring ~needle:"before 'result'" out)) ;
      Batch.check b ~msg:"the refusal offers extending the built-in under its own name"
        (Batch.has_substring ~needle:"[channel.result]" out) ;
      Batch.check b ~msg:"the refusal offers a distinguishing error_type as the other remedy"
        (Batch.has_substring ~needle:"error_type" out)) ;
  Lwt.return_unit

(* Review round 2 (HIGH): the point of [merge] extending rather than
   replacing. A profile-shaped config that adds ONE bind to a built-in must
   pass [--errors-strict] without restating the built-in's own vocabulary —
   the inherited [Stdlib.*] paths are not the operator's declarations, and
   holding them to those made strict unsatisfiable for every real profile. *)
let register_strict_over_extended_builtin () =
  Test.register ~__FILE__
    ~title:"error-channels: --errors-strict passes over a config that EXTENDS a built-in"
    ~tags:["cmt"; "error_channels"; "config"; "strict"]
  @@ fun () ->
  with_fixture ~name:"errch_strict_extend"
    ~files:
      [
        Fixture.dune_project;
        ( "dune",
          "(library\n\
          \ (name errch_ext)\n\
          \ (wrapped false)\n\
          \ (modules es_ext)\n\
          \ (flags (:standard -w -8-11-21-26-27-32-33-37-39)))\n" );
        (* Exactly the shipped Tezos profile's shape: name the built-in
           [option] channel and add a bind vocabulary of our own. Nothing of
           the built-in's is restated — under the old replace-semantics this
           file would have had to copy six [Stdlib.Option.*] paths in, and
           those copies would then have counted against the strict run. *)
        ( "arch-errors.toml",
          (* [my_bind] is called UNQUALIFIED from inside the module that
             defines it, so its resolved head is the bare name — same rule as
             the main fixture's [add_err]/[opt_of_res]. *)
          "[channel.option]\ntype = \"option\"\nbinds = [\"my_bind\"]\n" );
        ( "es_ext.ml",
          {|let my_bind (o : int option) (k : int -> int option) =
  match o with None -> None | Some x -> k x

let src () : int option = if Sys.opaque_identity true then None else Some 1

let use () = my_bind (src ()) (fun x -> Some x)
|} );
      ]
  @@ fun fixture ->
  let code, out, _db = Arch_tezt.index_raw ~extra_args:["--errors-strict"] fixture in
  Batch.run (fun b ->
      Batch.eq_int b
        ~msg:
          (Printf.sprintf
             "--errors-strict must exit 0 when the operator's own paths all matched; got %d, \
              output:\n\
              %s"
             code out)
        code 0 ;
      (* The built-in's unmatched Stdlib vocabulary is still REPORTED — it is
         a warning, which is the honest thing to print; it just may not fail
         the run. *)
      Batch.check b ~msg:"an inherited built-in path that matched nothing is still warned about"
        (Batch.has_substring ~needle:"'Stdlib.Option.value' matched nothing" out) ;
      Batch.check b ~msg:"…but does not appear in a strict verdict"
        (not (Batch.has_substring ~needle:"--errors-strict:" out))) ;
  Lwt.return_unit

(* Review round 2, CRITICAL — a completion marker that outlives its evidence.

   Moving [error_contract] after its transaction made its presence honest on a
   FRESH database only. On a RE-INDEX the previous run's marker is already on
   disk and nothing removed it: [comment_db_meta] is deliberately outside
   [schema_tables_to_drop] (the [self_managed] allowlist in
   tezt/tests/schema_drop_list.ml), on the grounds that "INSERT OR REPLACE, so
   a re-index overwrites it" — true only for a run that REACHES the write.

   This pins the fix without depending on process timing. The second run is
   given a VALID but EMPTY build directory: it gets past the drop/recreate
   step, indexes zero functions, and therefore never re-writes
   [callgraph_contract]/[exn_contract], which are gated on a non-empty
   universe. So whatever those keys hold afterwards can only have come from
   run 1 — and before the fix, that is exactly what they held: run 1's
   markers, standing over run 2's empty tables. A timing-based SIGKILL test
   reproduces the same defect but cannot be made deterministic in CI; this
   can, and it fails for the same reason.

   WHAT THIS DOES NOT COVER: [error_contract] itself. Run 2 rewrites it
   unconditionally after the commit, whereas [callgraph_contract]/[exn_contract]
   are gated on a non-empty universe — so it cannot be a detector in this
   scenario, and this test does not pretend otherwise. The DELETE covers all
   three; the assertion covers two. [tezt/tests/completion_markers.ml] pins the
   classification of every marker key, and a SIGKILL sweep (21/60 torn states
   without the pre-demolition delete, 0/60 with it) covers the timing case no
   deterministic test can reach. *)
let register_stale_completion_markers () =
  Test.register ~__FILE__
    ~title:"error-channels: a re-index never inherits the previous run's completion markers"
    ~tags:["cmt"; "error_channels"; "reindex"; "markers"]
  @@ fun () ->
  with_fixture ~name:"errch_markers" ~files:fixture_files @@ fun fixture ->
  let db = Arch_tezt.temp_db "errch_markers" in
  let marker_keys = ["callgraph_contract"; "exn_contract"] in
  let marker key =
    Db.with_db db (fun conn ->
        Db.int conn
          (Printf.sprintf
             "SELECT count(*) FROM comment_db_meta WHERE key = '%s'" key))
  in
  let n_functions () =
    Db.with_db db (fun conn -> Db.int conn "SELECT count(*) FROM functions")
  in
  (* Run 1: a real corpus. Every marker is legitimately earned here. *)
  let code1, out1 = Arch_tezt.index_raw_into ~db fixture in
  if code1 <> 0 then Test.fail "first index failed (exit %d):\n%s" code1 out1 ;
  if n_functions () = 0 then
    Test.fail "fixture indexed no functions — the test cannot distinguish anything" ;
  List.iter
    (fun key ->
      if marker key <> 1 then
        Test.fail "run 1 did not write %s; the test's premise is broken" key)
    marker_keys ;
  (* Run 2: same database, a valid but empty build directory. *)
  let empty = Temp.dir "errch_markers_empty" in
  let code2, out2 =
    Arch_tezt.index_raw_into ~db {fixture with build_dir = empty}
  in
  Batch.run (fun b ->
      Batch.eq_int b ~msg:"re-index over an empty build dir exits 0" code2 0 ;
      if code2 <> 0 then Batch.note b "second index output:\n%s" out2 ;
      Batch.eq_int b
        ~msg:"run 2 indexed nothing, so no marker can have been earned"
        (n_functions ()) 0 ;
      List.iter
        (fun key ->
          Batch.eq_int b
            ~msg:
              (Printf.sprintf
                 "%s does not survive from the previous run" key)
            (marker key) 0)
        marker_keys) ;
  Lwt.return_unit

let register () =
  register_producer () ;
  register_reindex () ;
  register_stale_completion_markers () ;
  register_strict_success () ;
  register_unreachable_channel () ;
  register_unreachable_over_builtin () ;
  register_strict_over_extended_builtin () ;
  register_query () ;
  register_config () ;
  register_strict () ;
  register_profile_precedence () ;
  register_flat_not_analysed () ;
  register_summaries ()
