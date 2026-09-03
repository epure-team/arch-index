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
      "[channel.myres]\ntype = \"myres\"\norigins = [{path = \"Error\", arg = 1}]\n" );
    ( "ec_a.ml",
      {|type err = A | B of int

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

(* US-3.1 : not a myres carrier at all *)
let plain () = 42

(* US-2.10 : option channel (built-in, no config needed) *)
let o () = if Sys.opaque_identity true then None else Some 1

let o2 () = Option.bind (o ()) (fun x -> Some x)
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
      Batch.check b ~msg:"the error names --channel" (Batch.has_substring ~needle:"--channel" out)) ;
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

let register () =
  register_producer () ;
  register_query () ;
  register_config ()
