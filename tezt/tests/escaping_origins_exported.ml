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
      (* CONTROL, NOT THIS TEST'S SUBJECT — and the distinction is load-bearing enough to
         be in the title. Exit 3 here is guaranteed by [Arch_db.ok], which converts a raw
         "no such column: exposed" into a Refused at any site with no guard of its own;
         measured by deleting the guard below and re-running, where this line still passes
         and only the two message assertions fail. So a reader who breaks [Arch_db.ok] and
         finds this test green has NOT been told they are safe: nothing here pins the
         refusal. What this test owns is the DIAGNOSIS. *)
      Batch.eq_int b ~msg:(Printf.sprintf "control (owned by Arch_db.ok, not by this test): exit 3:\n%s" out) code 3 ;
      Batch.check b
        ~msg:(Printf.sprintf "…and says the cone would be empty for want of a root:\n%s" out)
        (contains ~needle:"no function in this index is marked exported" out) ;
      (* And prints no table: a refusal that still emits a header is how a consumer reading
         stdout concludes the surface is empty. *)
      Batch.check b
        ~msg:(Printf.sprintf "…and prints no coverage header before refusing:\n%s" out)
        (not (contains ~needle:"coverage:" out))) ;
  Lwt.return_unit

(* A FLAT-schema index spells the API-surface flag [functions.exported]; MAIN spells it
   [functions.exposed], and this subcommand reads MAIN throughout — its root CTE joins
   [functions.module_id], which FLAT has no column for. So [--roots exported] against FLAT
   has three possible outcomes and only one of them is acceptable:

     crash            loud, recoverable
     EMPTY RESULT     silent, confident, about the wrong population — and for THIS question
                      an empty list reads as "nothing escapes", the reassuring answer
     refusal          what this test pins

   The middle one is the same shape #87's [COALESCE(exported,0) -> 1] mutant was built to
   catch: no crash and no empty set is precisely what makes it invisible. This test exists
   because the convention "escaping-origins is MAIN-only" was in our heads and in no
   executable form — the defect #87 itself was written to close, one file over. *)
let register_refuses_a_flat_index () =
  Test.register ~__FILE__
    ~title:"escaping-origins --roots exported: a FLAT index is told WHY (the refusal itself is Arch_db.ok's)"
    ~tags:["query"; "origins"; "exported"; "crash"; "flat"; "schema"]
  @@ fun () ->
  let db = Arch_tezt.temp_db "eoe_flat" in
  (* The fixture must clear every EARLIER guard, or the refusal below is credited to the
     wrong one: escaping-origins refuses in turn on a missing contract flag, a missing
     exn_origins table, and an empty exn_origins, all before it looks at any column. A
     fixture that tripped one of those would make this test pass without the schema guard
     existing at all. *)
  Db.with_db_rw db (fun c ->
      Db.exec c
        {|
CREATE TABLE comment_db_meta(key TEXT, value TEXT);
INSERT INTO comment_db_meta VALUES('callgraph_contract','v1');
CREATE TABLE modules(path TEXT);
INSERT INTO modules VALUES ('api.ml'),('vuln.ml');
CREATE TABLE functions(name TEXT, file_path TEXT, exported INT, line_start INT, line_end INT);
INSERT INTO functions VALUES ('flat_entry','api.ml',1,1,2),('flat_danger','vuln.ml',0,1,2);
CREATE TABLE calls(caller_name TEXT, caller_file TEXT, callee_name TEXT, callee_file TEXT, call_site TEXT, kind TEXT);
INSERT INTO calls VALUES ('flat_entry','api.ml','flat_danger','vuln.ml','api.ml:1','MUST');
CREATE TABLE exn_origins(id INTEGER PRIMARY KEY AUTOINCREMENT, function_id INTEGER, scope_id INTEGER,
  form TEXT NOT NULL, exn_path TEXT, escapes BOOLEAN NOT NULL DEFAULT 1,
  line INTEGER NOT NULL, col INTEGER NOT NULL, channel TEXT NOT NULL DEFAULT 'exception');
INSERT INTO exn_origins(function_id,form,escapes,line,col,channel) VALUES (2,'division',1,1,0,'exception');
|}) ;
  let code, out = query [ db; "escaping-origins"; "--roots"; "exported" ] in
  Batch.run (fun b ->
      (* PREMISE — the discriminator, asserted on the columns the guard actually branches on
         rather than on the fixture text meant to produce them. *)
      Batch.eq_int b ~msg:"premise: functions.exported exists (this really is FLAT's spelling)"
        (Db.with_db db (fun c ->
             Db.int c "SELECT count(*) FROM pragma_table_info('functions') WHERE name='exported'"))
        1 ;
      Batch.eq_int b ~msg:"premise: and functions.exposed does NOT, so the MAIN path is unreachable"
        (Db.with_db db (fun c ->
             Db.int c "SELECT count(*) FROM pragma_table_info('functions') WHERE name='exposed'"))
        0 ;
      (* PREMISE — a fatal origin IS recorded, so a later empty list could not be blamed on
         an index with nothing in it. This is what makes the refusal load-bearing. *)
      Batch.check b ~msg:"premise: a fatal origin is recorded, so an empty report would be a LIE"
        (Db.with_db db (fun c -> Db.int c "SELECT count(*) FROM exn_origins") >= 1) ;
      (* CONTROL, NOT THIS TEST'S SUBJECT — and the distinction is load-bearing enough to
         be in the title. Exit 3 here is guaranteed by [Arch_db.ok], which converts a raw
         "no such column: exposed" into a Refused at any site with no guard of its own;
         measured by deleting the guard below and re-running, where this line still passes
         and only the two message assertions fail. So a reader who breaks [Arch_db.ok] and
         finds this test green has NOT been told they are safe: nothing here pins the
         refusal. What this test owns is the DIAGNOSIS. *)
      Batch.eq_int b ~msg:(Printf.sprintf "control (owned by Arch_db.ok, not by this test): exit 3:\n%s" out) code 3 ;
      (* THE TWO ASSERTIONS THIS TEST ACTUALLY OWNS. The remedy is the point, not the refusal. Telling a FLAT user to "re-index
         with a producer that records exports" names a defect they do not have: their
         producer recorded exports, in FLAT's own column. *)
      Batch.check b
        ~msg:(Printf.sprintf "…names FLAT as the cause, not an out-of-date index:\n%s" out)
        (contains ~needle:"FLAT-schema index" out) ;
      Batch.check b
        ~msg:(Printf.sprintf "…and says re-indexing will not help:\n%s" out)
        (contains ~needle:"re-indexing will not help" out) ;
      (* The outcome this whole test exists to exclude. *)
      Batch.check b
        ~msg:(Printf.sprintf "…and prints no coverage header, so nothing reads as empty:\n%s" out)
        (not (contains ~needle:"coverage:" out))) ;
  Lwt.return_unit

let register () =
  register_roots_the_api_surface () ;
  register_refuses_an_unmarked_index () ;
  register_refuses_a_flat_index ()
