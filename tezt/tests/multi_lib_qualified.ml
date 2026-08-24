(******************************************************************************)
(*                                                                            *)
(* Copyright (c) 2026 Epure Team                                              *)
(* All rights reserved.                                                       *)
(*                                                                            *)
(******************************************************************************)

(** Sound qualified-name resolution across dune library boundaries.

    Three dune libraries, [liba] and [libc], each define a module [api.ml]
    with a function [run] — the same basename in two different libraries.
    A third library, [libb], calls [Liba.Api.run ()] qualified through the
    persistent library-wrapper root.

    The bug this pins (spec: [specs/sound-qualified-name-resolution.md]):
    three tables in [arch_index.ml] key modules by capitalised file basename
    with last-writer-wins semantics, from a query with no [ORDER BY].  A
    qualified call whose root names a *library* rather than a bare module
    then falls through to the ambiguous global basename table and can be
    stamped [MUST] toward the wrong homonym — [libc]'s [run] instead of
    [liba]'s.

    CHECK-1 (S1): the call site resolves to [liba]'s [run], or is degraded to
    [MAY_ENUMERATED]/[MAY_TOP] — never a [MUST] to [libc]'s [run].

    CHECK-2 (S3): a call through a local module alias ([module A = Liba.Api];
    [A.run ()]) stays [MAY_TOP] — this is already-safe behaviour the fix must
    not regress by "improving" its way into a guess. *)

open Arch_tezt

let fixture_files =
  [
    Fixture.dune_project;
    ("liba/dune", "(library\n (name liba)\n (modules api)\n (flags (:standard -w -32)))\n");
    ("liba/api.ml", "let run () : int = 1\n");
    ("libc/dune", "(library\n (name libc)\n (modules api)\n (flags (:standard -w -32)))\n");
    ("libc/api.ml", "let run () : int = 2\n");
    ( "libb/dune",
      "(library\n\
      \ (name libb)\n\
      \ (libraries liba)\n\
      \ (modules caller aliaser)\n\
      \ (flags (:standard -w -32-37)))\n" );
    ("libb/caller.ml", "let go_a () : int = Liba.Api.run ()\n") ;
    ( "libb/aliaser.ml",
      "module A = Liba.Api\n\nlet via_alias () : int = A.run ()\n" );
  ]

let module_id db ~like =
  Db.int_opt db
    (Printf.sprintf "SELECT id FROM modules WHERE path LIKE '%s'" like)

let fn_id db ~module_like ~name =
  Db.int_opt db
    (Printf.sprintf
       "SELECT f.id FROM functions f JOIN modules m ON m.id = f.module_id \
        WHERE f.name = '%s' AND m.path LIKE '%s'"
       name module_like)

let call_of db ~caller =
  let row =
    Db.rows db
      (Printf.sprintf
         "SELECT c.callee_id, c.kind FROM calls c JOIN functions f ON f.id = \
          c.caller_id WHERE f.name = '%s'"
         caller)
  in
  match row with
  | [[Sqlite3.Data.NULL; kind]] -> (None, Db.to_string ~sql:"kind" kind)
  | [[callee_id; kind]] ->
      (Some (Db.to_int ~sql:"callee_id" callee_id), Db.to_string ~sql:"kind" kind)
  | [] -> Test.fail "no call row recorded for caller %s" caller
  | _ -> Test.fail "expected exactly one call row for caller %s" caller

let register () =
  Test.register ~__FILE__
    ~title:"cmt: qualified calls resolve within the owning library, not by basename"
    ~tags:["cmt"; "callgraph"; "ocaml"; "qualified"]
  @@ fun () ->
  with_fixture ~name:"arch_tezt_multi_lib" ~files:fixture_files @@ fun fixture ->
  let db_path = index fixture in
  Db.with_db db_path (fun db ->
      (* Pin the references first: were either 'run' absent, an equally absent
         resolution would agree with the property for the wrong reason. *)
      ( match module_id db ~like:"%liba/api.ml" with
      | None -> Test.fail "liba/api.ml is not indexed"
      | Some _ -> () ) ;
      ( match module_id db ~like:"%libc/api.ml" with
      | None -> Test.fail "libc/api.ml is not indexed"
      | Some _ -> () ) ;
      let liba_run =
        match fn_id db ~module_like:"%liba/api.ml" ~name:"run" with
        | Some id -> id
        | None -> Test.fail "liba's 'run' is not indexed, nothing to bind to"
      in
      let libc_run =
        match fn_id db ~module_like:"%libc/api.ml" ~name:"run" with
        | Some id -> id
        | None -> Test.fail "libc's 'run' is not indexed, nothing to bind to"
      in
      Check.is_true
        (liba_run <> libc_run)
        ~error_msg:"fixture bug: liba's and libc's 'run' resolved to the same row" ;

      (* CHECK-1 / S1: go_a calls Liba.Api.run () — must never be a MUST edge to
         libc's run, and any MUST edge must point at liba's run specifically. *)
      let callee_id, kind = call_of db ~caller:"go_a" in
      let callee_id_str () =
        match callee_id with Some i -> string_of_int i | None -> "<none>"
      in
      Check.is_true
        (kind <> "MUST" || callee_id = Some liba_run)
        ~error_msg:
          (Printf.sprintf
             "go_a -> Liba.Api.run resolved kind=%s callee_id=%s (liba's run \
              is %d, libc's run is %d): a MUST edge must name liba's run, \
              never libc's"
             kind (callee_id_str ()) liba_run libc_run) ;
      Check.is_false
        (kind = "MUST" && callee_id = Some libc_run)
        ~error_msg:
          "go_a -> Liba.Api.run stamped MUST toward libc's run: identity \
           theft across a library boundary (F1)" ;
      if kind <> "MUST" then
        Check.is_true
          (List.mem kind ["MAY_ENUMERATED"; "MAY_TOP"])
          ~error_msg:
            (Printf.sprintf
               "go_a -> Liba.Api.run: unexpected kind %s (expected MUST to \
                liba's run, or MAY_ENUMERATED/MAY_TOP)"
               kind) ;

      (* CHECK-2 / S3: a call through a local module alias must stay MAY_TOP —
         this is already-safe behaviour (module aliases are not descended
         into); the fix must not regress it into a guess. *)
      let alias_callee_id, alias_kind = call_of db ~caller:"via_alias" in
      Check.is_true
        (alias_kind = "MAY_TOP")
        ~error_msg:
          (Printf.sprintf
             "via_alias -> A.run resolved kind=%s callee_id=%s, expected \
              MAY_TOP (alias resolution must not be attempted)"
             alias_kind
             (match alias_callee_id with
             | Some i -> string_of_int i
             | None -> "<none>"))) ;
  Lwt.return_unit
