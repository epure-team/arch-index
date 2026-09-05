(******************************************************************************)
(*                                                                            *)
(* Copyright (c) 2026 Epure Team                                              *)
(* All rights reserved.                                                       *)
(*                                                                            *)
(******************************************************************************)

(** [escaping-origins --roots exported] — the crash surface an external caller can reach.

    {1 The question this exists for}

    "Which crash sites can a caller outside this library trigger?" The command already
    answered it for ONE named root; the API surface is a SET, and rooting at one module
    answers for one module. [--roots exported] roots at every function that appears in an
    [.mli], which is the shape the question actually has.

    {1 Why the keyword and not a selector}

    [arch-coverage --roots exported] already means this set, computed from the same
    [functions.exposed] column. A second spelling for one set is how two names for one thing
    come to disagree in the place it matters; this is the same word over the same column.

    {1 The refusal is the load-bearing part}

    An index whose producer never marked exports gives an EMPTY cone, and every list is then
    empty for want of a starting point rather than for want of crash sites — which reads as
    "nothing here can crash", the worst available answer to this question. That is a vacuous
    PASS wearing a report's clothes, so it is refused with exit 3 rather than printed. The
    same guard [arch-coverage] applies to its own [--roots exported]. *)

open Arch_tezt

let query args = run_command (arch_query ()) args

(* [safe_entry] is exported and reaches nothing fatal. [risky_entry] is exported and calls
   [helper], which divides. [orphan_risky] also divides but is reachable from NO entry point.

   The last one is what makes the test discriminate: a [--roots exported] that quietly rooted
   at EVERY function — the failure mode with no crash and no empty set — would list
   [orphan_risky] too. *)
let fixture_files =
  [
    Fixture.dune_project;
    ( "dune",
      "(library\n\
      \ (name eoe_fixture)\n\
      \ (wrapped false)\n\
      \ (modules eoe_a)\n\
      \ (flags (:standard -w -8-11-21-26-27-32-33-37-39)))\n" );
    ( "eoe_a.ml",
      {|let helper a b = a / b

let risky_entry a b = helper a b

let safe_entry n = n + 1

(* Divides, but nothing exported reaches it. *)
let orphan_risky a b = a / b
|} );
    ("eoe_a.mli", "val risky_entry : int -> int -> int\nval safe_entry : int -> int\n");
  ]

let with_indexed name f =
  with_fixture ~name ~files:fixture_files @@ fun fixture ->
  let db = Arch_tezt.temp_db name in
  let code, output = Arch_tezt.index_raw_into ~db fixture in
  if code <> 0 then Test.fail "index failed (exit %d):\n%s" code output ;
  f db

let register_roots_the_api_surface () =
  Test.register ~__FILE__
    ~title:"escaping-origins --roots exported: the cone starts at the API surface, not everywhere"
    ~tags:["query"; "origins"; "exported"; "crash"]
  @@ fun () ->
  with_indexed "eoe_surface" @@ fun db ->
  let code, out = query [ db; "escaping-origins"; "--roots"; "exported" ] in
  Batch.run (fun b ->
      (* PREMISE 1 — the fixture really splits exported from not. Without both numbers a
         selector that matched everything and one that matched the right set are the same. *)
      Batch.eq_int b ~msg:"premise: exactly two functions are exported"
        (Db.with_db db (fun c -> Db.int c "SELECT count(*) FROM functions WHERE exposed = 1"))
        2 ;
      Batch.check b ~msg:"premise: and at least one is not"
        (Db.with_db db (fun c ->
             Db.int c "SELECT count(*) FROM functions WHERE COALESCE(exposed,0) = 0")
        >= 1) ;
      (* PREMISE 2 — the unreachable divider really is recorded as an origin, or its ABSENCE
         from the output below proves nothing about rooting. *)
      Batch.check b ~msg:"premise: orphan_risky has a division origin at all"
        (Db.with_db db (fun c ->
             Db.int c
               "SELECT count(*) FROM exn_origins o JOIN functions f ON o.function_id=f.id \
                WHERE f.name='orphan_risky' AND o.form='division'")
        >= 1) ;
      Batch.eq_int b ~msg:(Printf.sprintf "the command succeeds:\n%s" out) code 0 ;
      (* THE ROOT LINE names the set and its size, so a reader can tell the cone started
         somewhere plausible rather than at one function or at everything. *)
      Batch.check b
        ~msg:(Printf.sprintf "the root line names the exported set and its size:\n%s" out)
        (contains ~needle:"root: exported (2 entry point" out) ;
      (* ASSERTION 1 — it REACHES the site behind an entry point. *)
      Batch.check b
        ~msg:(Printf.sprintf "the divide reachable from risky_entry is listed:\n%s" out)
        (contains ~needle:"helper" out) ;
      (* ASSERTION 2 — and does NOT list the one no entry point reaches. This is the line that
         separates "rooted at the API surface" from "rooted at every function". *)
      Batch.check b
        ~msg:
          (Printf.sprintf
             "orphan_risky is NOT listed — nothing exported reaches it, so rooting is real:\n%s"
             out)
        (not (contains ~needle:"orphan_risky" out))) ;
  Lwt.return_unit

let register_refuses_an_unmarked_index () =
  Test.register ~__FILE__
    ~title:"escaping-origins --roots exported: an index with no exports is REFUSED, not reported empty"
    ~tags:["query"; "origins"; "exported"; "crash"; "vacuity"]
  @@ fun () ->
  with_indexed "eoe_vacuous" @@ fun db ->
  (* Construct the absent state rather than assume some index lacks exports: clear the flag,
     leaving the crash sites in place. The cone is then empty for want of a ROOT, which is
     exactly the situation that must not render as "nothing can crash here". *)
  Db.with_db_rw db (fun c -> Db.exec c "UPDATE functions SET exposed = 0") ;
  let code, out = query [ db; "escaping-origins"; "--roots"; "exported" ] in
  Batch.run (fun b ->
      (* PREMISE — the crash sites are STILL THERE. Without this the refusal below could be
         explained by an empty table, and the test would pass for the wrong reason. *)
      Batch.check b ~msg:"premise: fatal origins still exist in the index"
        (Db.with_db db (fun c ->
             Db.int c "SELECT count(*) FROM exn_origins WHERE form='division'")
        >= 1) ;
      Batch.eq_int b ~msg:(Printf.sprintf "refuses with exit 3:\n%s" out) code 3 ;
      Batch.check b
        ~msg:(Printf.sprintf "…and says the cone would be empty for want of a root:\n%s" out)
        (contains ~needle:"no function in this index is marked exported" out) ;
      (* And prints no table: a refusal that still emits a header is how a consumer reading
         stdout concludes the surface is empty. *)
      Batch.check b
        ~msg:(Printf.sprintf "…and prints no coverage header before refusing:\n%s" out)
        (not (contains ~needle:"coverage:" out))) ;
  Lwt.return_unit

let register () =
  register_roots_the_api_surface () ;
  register_refuses_an_unmarked_index ()
