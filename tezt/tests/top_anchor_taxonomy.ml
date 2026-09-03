(******************************************************************************)
(*                                                                            *)
(* Copyright (c) 2026 Epure Team                                              *)
(* All rights reserved.                                                       *)
(*                                                                            *)
(******************************************************************************)

(** Roadmap 1.4: the ⊤-anchor taxonomy.

    [calls.top_reason] must be [NULL] for every resolved or bounded-candidate
    edge, and a member of the agnostic vocabulary for every [MAY_TOP] edge —
    never a silent NULL there, which would be the same "unknowable, no
    further data" gap the roadmap's own note opens with. [dropped_node_dependents.ml]
    already covers the [dropped_node] reason (it needs the reject-trigger
    fixture mechanism that lives there); this file covers the two reasons
    the CMT walker itself decides at emission time — [callback_param] and
    [module_param] — plus the CHECK constraint and the NULL-outside-MAY_TOP
    invariant. *)

open Arch_tezt

let fixture_files =
  [
    Fixture.dune_project;
    ("dune", "(library (name topanchorfix) (modules topanchorfix)\n (flags (:standard -w -32-26-27-34-37-69)))\n");
    ( "topanchorfix.ml",
      {ocaml|(* callback_param: a bare function-typed PARAMETER invoked as a callback. *)
let apply_it (f : int -> int) (x : int) : int = f x

(* callback_param: a function-typed parameter passed onward as an ARGUMENT
   (add_arg_escapes' Texp_ident-Pident branch), not invoked directly. *)
let forward_it (g : int -> int) (h : (int -> int) -> int) : int = h g

(* module_param: a functor argument's own member invoked — the qualified
   path's root (the functor parameter) is a non-persistent ident. *)
module type S = sig
  val op : int -> int
end

module Wrap (M : S) = struct
  let call_member (x : int) : int = M.op x
end

(* control: an ordinary, fully-resolved same-module call — MUST, no top_reason. *)
let helper (x : int) : int = x + 1
let control_caller (x : int) : int = helper x
|ocaml} );
  ]

let register_callback_param () =
  Test.register ~__FILE__
    ~title:"top-anchor: a function-typed parameter invoked as a callback is callback_param"
    ~tags:["top_anchor"; "cmt"]
  @@ fun () ->
  with_fixture ~name:"top_anchor_callback" ~files:fixture_files @@ fun fixture ->
  let db_path = index fixture in
  Db.with_db db_path (fun db ->
      Check.(
        (Db.string_opt db
           "SELECT top_reason FROM calls c JOIN functions f ON c.caller_id = f.id \
            WHERE f.name = 'apply_it' AND c.callee_name = 'f' AND c.kind = 'MAY_TOP'"
         = Some "callback_param")
          (option string)
          ~error_msg:"apply_it's call to its own parameter f should be callback_param, got %L") ;
      Check.(
        (Db.string_opt db
           "SELECT top_anchor FROM calls c JOIN functions f ON c.caller_id = f.id \
            WHERE f.name = 'apply_it' AND c.callee_name = 'f' AND c.kind = 'MAY_TOP'"
         <> None)
          (option string)
          ~error_msg:"a MAY_TOP edge must carry a non-NULL top_anchor, got %L") ;
      Check.(
        (Db.string_opt db
           "SELECT top_reason FROM calls c JOIN functions f ON c.caller_id = f.id \
            WHERE f.name = 'forward_it' AND c.callee_name = 'g' AND c.kind = 'MAY_TOP'"
         = Some "callback_param")
          (option string)
          ~error_msg:
            "forward_it passing its parameter g onward as an argument should also be \
             callback_param, got %L") ;
      Lwt.return_unit)

let register_module_param () =
  Test.register ~__FILE__
    ~title:"top-anchor: a functor argument's member invoked is module_param"
    ~tags:["top_anchor"; "cmt"]
  @@ fun () ->
  with_fixture ~name:"top_anchor_module" ~files:fixture_files @@ fun fixture ->
  let db_path = index fixture in
  Db.with_db db_path (fun db ->
      Check.(
        (Db.string_opt db
           "SELECT top_reason FROM calls c JOIN functions f ON c.caller_id = f.id \
            WHERE f.name = 'Wrap.call_member' AND c.callee_name = 'M.op' AND c.kind = 'MAY_TOP'"
         = Some "module_param")
          (option string)
          ~error_msg:"Wrap.call_member's call to its functor argument should be module_param, got %L") ;
      Lwt.return_unit)

let register_resolved_edge_has_no_top_reason () =
  Test.register ~__FILE__
    ~title:"top-anchor: a resolved MUST edge has NULL top_reason and NULL top_anchor"
    ~tags:["top_anchor"; "cmt"]
  @@ fun () ->
  with_fixture ~name:"top_anchor_control" ~files:fixture_files @@ fun fixture ->
  let db_path = index fixture in
  Db.with_db db_path (fun db ->
      Check.(
        (Db.string_opt db "SELECT kind FROM calls WHERE callee_name = 'helper'" = Some "MUST")
          (option string)
          ~error_msg:"control_caller -> helper should resolve MUST, got %L") ;
      Check.(
        (Db.int db "SELECT top_reason IS NULL FROM calls WHERE callee_name = 'helper'" = 1)
          int
          ~error_msg:"a resolved MUST edge must have NULL top_reason, got %L") ;
      Check.(
        (Db.int db "SELECT top_anchor IS NULL FROM calls WHERE callee_name = 'helper'" = 1)
          int
          ~error_msg:"a resolved MUST edge must have NULL top_anchor, got %L") ;
      Lwt.return_unit)

let register_global_invariant () =
  Test.register ~__FILE__
    ~title:"top-anchor: top_reason/top_anchor are non-NULL iff kind is MAY_TOP, across every row"
    ~tags:["top_anchor"; "cmt"]
  @@ fun () ->
  (* Reuses the callback/module fixture: it already has a mix of MAY_TOP
     (apply_it -> f, forward_it -> g -> h, Wrap.call_member -> M.op) and MUST
     (control_caller -> helper) edges, so this is a real cross-check over
     several branches of the classification match, not just the ones the
     other tests in this file already name individually. *)
  with_fixture ~name:"top_anchor_global" ~files:fixture_files @@ fun fixture ->
  let db_path = index fixture in
  Db.with_db db_path (fun db ->
      Check.(
        (Db.int db "SELECT count(*) FROM calls WHERE kind = 'MAY_TOP' AND top_reason IS NULL" = 0)
          int
          ~error_msg:"%L MAY_TOP row(s) have a NULL top_reason — the silent-absence gap this taxonomy exists to close") ;
      Check.(
        (Db.int db "SELECT count(*) FROM calls WHERE kind != 'MAY_TOP' AND top_reason IS NOT NULL" = 0)
          int
          ~error_msg:"%L non-MAY_TOP row(s) have a non-NULL top_reason") ;
      Check.(
        (Db.int db "SELECT count(*) FROM calls WHERE kind = 'MAY_TOP' AND top_anchor IS NULL" = 0)
          int
          ~error_msg:"%L MAY_TOP row(s) have a NULL top_anchor") ;
      Check.(
        (Db.int db "SELECT count(*) FROM calls WHERE kind != 'MAY_TOP' AND top_anchor IS NOT NULL" = 0)
          int
          ~error_msg:"%L non-MAY_TOP row(s) have a non-NULL top_anchor") ;
      (* A sanity floor: the invariant checks above are vacuously true on a
         database with zero MAY_TOP rows, which would be a much bigger
         problem hiding as a pass. *)
      let has_may_top = Db.int db "SELECT count(*) FROM calls WHERE kind = 'MAY_TOP'" > 0 in
      Check.(
        (has_may_top = true) bool
          ~error_msg:"this fixture must contain at least one MAY_TOP row, or the checks above are vacuous") ;
      Lwt.return_unit)

let register_kind_top_reason_pairing_constraint () =
  Test.register ~__FILE__
    ~title:"top-anchor: a top_reason on a non-MAY_TOP row violates the CHECK constraint"
    ~tags:["top_anchor"; "schema"]
  @@ fun () ->
  let db =
    Fixture.main
      ~name:"top-anchor-pairing"
      ~seed:
        "INSERT INTO modules(path, lines, has_mli) VALUES ('lib/x.ml', 10, 0); \
         INSERT INTO functions(module_id, name, line_start, line_end, exposed) VALUES \
         ((SELECT id FROM modules WHERE path='lib/x.ml'), 'f', 1, 2, 1); \
         INSERT INTO functions(module_id, name, line_start, line_end, exposed) VALUES \
         ((SELECT id FROM modules WHERE path='lib/x.ml'), 'g', 3, 4, 0);"
      ()
  in
  Db.with_db_rw db (fun conn ->
      let rc =
        Sqlite3.exec conn
          "INSERT INTO calls(caller_id, callee_id, callee_name, kind, top_reason) VALUES \
           ((SELECT id FROM functions WHERE name='f'), (SELECT id FROM functions WHERE name='g'), \
           'g', 'MUST', 'callback_param')"
      in
      let rejected = rc <> Sqlite3.Rc.OK in
      Check.(
        (rejected = true) bool
          ~error_msg:"a top_reason on a MUST row must violate the CHECK constraint") ;
      Check.(
        (Db.int conn "SELECT count(*) FROM calls WHERE callee_name = 'g'" = 0)
          int
          ~error_msg:"a rejected row must not leave a row behind, got %L") ;
      Lwt.return_unit)

let register_check_constraint () =
  Test.register ~__FILE__
    ~title:"top-anchor: an out-of-vocabulary top_reason violates the CHECK constraint"
    ~tags:["top_anchor"; "schema"]
  @@ fun () ->
  let db =
    Fixture.main
      ~name:"top-anchor-check"
      ~seed:
        "INSERT INTO modules(path, lines, has_mli) VALUES ('lib/x.ml', 10, 0); \
         INSERT INTO functions(module_id, name, line_start, line_end, exposed) VALUES \
         ((SELECT id FROM modules WHERE path='lib/x.ml'), 'f', 1, 2, 1); \
         INSERT INTO functions(module_id, name, line_start, line_end, exposed) VALUES \
         ((SELECT id FROM modules WHERE path='lib/x.ml'), 'g', 3, 4, 0);"
      ()
  in
  Db.with_db_rw db (fun conn ->
      let ok_rc =
        Sqlite3.exec conn
          "INSERT INTO calls(caller_id, callee_id, callee_name, kind, top_reason) VALUES \
           ((SELECT id FROM functions WHERE name='f'), (SELECT id FROM functions WHERE name='g'), \
           'g', 'MAY_TOP', 'callback_param')"
      in
      let accepted = ok_rc = Sqlite3.Rc.OK in
      Check.((accepted = true) bool ~error_msg:"a valid top_reason must be accepted") ;
      let bad_rc =
        Sqlite3.exec conn
          "INSERT INTO calls(caller_id, callee_id, callee_name, kind, top_reason) VALUES \
           ((SELECT id FROM functions WHERE name='f'), NULL, 'h', 'MAY_TOP', 'made_up')"
      in
      let rejected = bad_rc <> Sqlite3.Rc.OK in
      Check.(
        (rejected = true) bool
          ~error_msg:"an out-of-vocabulary top_reason must violate the CHECK constraint") ;
      Check.(
        (Db.int conn "SELECT count(*) FROM calls WHERE top_reason = 'made_up'" = 0)
          int
          ~error_msg:"a rejected top_reason must not leave a row behind, got %L") ;
      Lwt.return_unit)

let register () =
  register_callback_param () ;
  register_module_param () ;
  register_resolved_edge_has_no_top_reason () ;
  register_global_invariant () ;
  register_kind_top_reason_pairing_constraint () ;
  register_check_constraint ()
