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
      (* CONTROL, NOT THIS TEST'S SUBJECT. Exit 3 here is NOT this test's to lose: delete the
         vacuity guard and the generic [n_roots = 0] refusal below it still fires, printing
         "no module matches --roots 'exported' in this index." Measured, and exactly ONE
         assertion fails under that mutant — the message one below; [prints no coverage
         header] stays green too. So a reader who weakens the vacuity guard and finds this
         line green has NOT been told they are safe. What this test owns is the DIAGNOSIS.

         An earlier version of this comment credited the surviving exit 3 to [Arch_db.ok] and
         said TWO assertions fail. Both false, and false in a way nothing could catch: the
         sentence was TRUE of [register_refuses_an_index_predating_exposed] below, written
         during work that was then reverted, and carried here across the edit. Its fixture
         does [UPDATE functions SET exposed = 0], so the column EXISTS and [Arch_db.ok] has
         no missing column to convert — it cannot be the mechanism here, and the badge is now
         where it belongs. *)
      Batch.eq_int b
        ~msg:(Printf.sprintf "control (owned by the generic n_roots=0 refusal, not by this test): exit 3:\n%s" out)
        code 3 ;
      Batch.check b
        ~msg:(Printf.sprintf "…and says the cone would be empty for want of a root:\n%s" out)
        (contains ~needle:"no function in this index is marked exported" out) ;
      (* And prints no table: a refusal that still emits a header is how a consumer reading
         stdout concludes the surface is empty. *)
      Batch.check b
        ~msg:(Printf.sprintf "…and prints no coverage header before refusing:\n%s" out)
        (not (contains ~needle:"coverage:" out))) ;
  Lwt.return_unit

(* What a FLAT-schema index actually does here, and the story of getting it wrong.

   [--roots exported] against FLAT has three possible outcomes, and only one is acceptable:
   a crash (loud), an EMPTY RESULT (silent, confident, about the wrong population — and for
   THIS question an empty list reads as "nothing escapes", the reassuring answer), or a
   refusal. This test pins the refusal.

   It pins it AT THE LINE THAT ACTUALLY RUNS. A FLAT index stops at the missing-[modules]
   guard, ~180 lines before the [functions.exposed] check that [--roots exported] adds: no
   FLAT producer creates a [modules] table — [bin/arch_load/arch_load.ml],
   [lib/arch_db/arch_load.ml] and [lib/arch_index/runner.ml] each create only
   comment_db_meta/functions/calls (plus decisions/dead_code_sites in the first).

   TWO CAVEATS, stated rather than fixed. (a) This DDL is hand-written and omits the two views
   [arch_load.ml] creates, and [Arch_db.has_table] counts views ([arch_db.ml:346]) — so the
   omission sits inside the very mechanism the test depends on. It is faithful on the axis
   under test ([modules] absent) and approximate elsewhere; the reviewer replicated
   [arch_load.ml:110-132] verbatim, views and indexes included, and it still stops at the same
   line. (b) It exercises only PRE-EXISTING code: nothing [--roots exported] added runs before
   that guard. It is a characterization test of behaviour this branch inherits, not a test of
   this branch's feature, and it is here because that behaviour is what makes the feature safe.

   The first version of this test asserted the [exposed] check's message instead, and passed.
   It passed because its fixture created a [modules] table, which no producer emits — the
   fixture had manufactured the reachability its assertion depended on. A test can be green,
   kill a mutant, and still describe a state the system cannot enter. The fixture below is
   deliberately restricted to the three tables a FLAT producer really writes. *)
let register_refuses_a_flat_index () =
  Test.register ~__FILE__
    ~title:"escaping-origins --roots exported: a producer-shaped FLAT index is REFUSED, not answered empty"
    ~tags:["query"; "origins"; "exported"; "crash"; "flat"; "schema"]
  @@ fun () ->
  let db = Arch_tezt.temp_db "eoe_flat" in
  Db.with_db_rw db (fun c ->
      Db.exec c
        {|
CREATE TABLE comment_db_meta(key TEXT, value TEXT);
INSERT INTO comment_db_meta VALUES('callgraph_contract','v1');
CREATE TABLE functions(name TEXT, file_path TEXT, exported INT, line_start INT, line_end INT);
INSERT INTO functions VALUES ('flat_entry','api.ml',1,1,2),('flat_danger','vuln.ml',0,1,2);
CREATE TABLE calls(caller_name TEXT, caller_file TEXT, callee_name TEXT, callee_file TEXT, call_site TEXT, kind TEXT);
INSERT INTO calls VALUES ('flat_entry','api.ml','flat_danger','vuln.ml','api.ml:1','MUST');
|}) ;
  let code, out = query [ db; "escaping-origins"; "--roots"; "exported" ] in
  Batch.run (fun b ->
      (* PREMISE — FIDELITY OF THE FIXTURE, which is the assertion the first version of this
         test lacked and the reason it measured an unreachable state. Asserted on the absence
         a producer actually produces, not on the fixture text meant to produce it. *)
      Batch.eq_int b
        ~msg:"premise: no modules table — the shape every FLAT producer emits, and what stops \
              this command above the exposed check"
        (Db.with_db db (fun c ->
             Db.int c "SELECT count(*) FROM sqlite_master WHERE type='table' AND name='modules'"))
        0 ;
      Batch.eq_int b ~msg:"premise: functions.exported exists (this really is FLAT's spelling)"
        (Db.with_db db (fun c ->
             Db.int c "SELECT count(*) FROM pragma_table_info('functions') WHERE name='exported'"))
        1 ;
      Batch.eq_int b ~msg:(Printf.sprintf "refuses with exit 3:\n%s" out) code 3 ;
      Batch.check b
        ~msg:(Printf.sprintf "…and names the flat schema as the cause:\n%s" out)
        (contains ~needle:"flat schema" out) ;
      (* The outcome this whole test exists to exclude: no header, so nothing reads as empty. *)
      Batch.check b
        ~msg:(Printf.sprintf "…and prints no coverage header:\n%s" out)
        (not (contains ~needle:"coverage:" out))) ;
  Lwt.return_unit

(* The [functions.exposed] guard that [--roots exported] adds had NO test and never ran under
   the suite — review finding 5. Its reachable population is narrow and worth stating: not a
   FLAT index (which stops ~180 lines earlier on the missing [modules] table — see above), but
   a MAIN index that PREDATES the column. Constructed here by dropping the column from a real
   index rather than by hand-building a plausible one, so the fixture cannot drift away from
   what the producer emits in every respect except the one under test. *)
let register_refuses_an_index_predating_exposed () =
  Test.register ~__FILE__
    ~title:"escaping-origins --roots exported: an index predating functions.exposed is REFUSED"
    ~tags:["query"; "origins"; "exported"; "crash"; "schema"]
  @@ fun () ->
  with_indexed "eoe_preexposed" @@ fun db ->
  (* An index and two views reference the column, and sqlite refuses the DROP while they do.
     Removing them is faithful rather than convenient: an index that genuinely predates
     [functions.exposed] predates everything defined in terms of it. *)
  Db.with_db_rw db (fun c ->
      Db.exec c "DROP INDEX IF EXISTS idx_functions_exposed" ;
      Db.exec c "DROP VIEW IF EXISTS v_large_functions" ;
      Db.exec c "DROP VIEW IF EXISTS v_undocumented" ;
      Db.exec c "ALTER TABLE functions DROP COLUMN exposed") ;
  let code, out = query [ db; "escaping-origins"; "--roots"; "exported" ] in
  Batch.run (fun b ->
      Batch.eq_int b ~msg:"premise: functions.exposed is really gone"
        (Db.with_db db (fun c ->
             Db.int c "SELECT count(*) FROM pragma_table_info('functions') WHERE name='exposed'"))
        0 ;
      (* PREMISE — and [modules] is still THERE, which is what makes this index reach the
         guard at all. Without it this test would be pinning the earlier refusal again. *)
      Batch.eq_int b ~msg:"premise: modules survives, so the earlier flat-schema guard passes"
        (Db.with_db db (fun c ->
             Db.int c "SELECT count(*) FROM sqlite_master WHERE type='table' AND name='modules'"))
        1 ;
      (* CONTROL — and THIS is the one [Arch_db.ok] owns. Delete the guard and exit 3 survives:
         [Arch_db.ok] converts the raw "no such column: exposed" into a Refused at any site
         without a guard of its own, printing "this index predates column exposed and should be
         re-indexed with a newer producer". Measured; exactly one assertion fails under that
         mutant, the message one below. What this test owns is the DIAGNOSIS, not the refusal. *)
      Batch.eq_int b
        ~msg:(Printf.sprintf "control (owned by Arch_db.ok, not by this test): exit 3:\n%s" out)
        code 3 ;
      Batch.check b
        ~msg:(Printf.sprintf "…and the remedy it names is the one that works here:\n%s" out)
        (contains ~needle:"Re-index with a producer that records exports" out) ;
      (* No literal run of spaces: the string is assembled by concatenation and an earlier
         version rendered "this index                  predates it". *)
      Batch.check b ~msg:(Printf.sprintf "…and renders without space runs:\n%s" out)
        (not (contains ~needle:"   " out)) ;
      Batch.check b
        ~msg:(Printf.sprintf "…and prints no coverage header:\n%s" out)
        (not (contains ~needle:"coverage:" out))) ;
  Lwt.return_unit

(* The keyword SHADOWS a real function name, and nothing in the exit code says so: both
   spellings exit 0 and answer about different populations. Review finding 1 — in this
   repository's own index [tezt/tests/multilang.ml:exported] exists, so the change silently
   redirected an invocation that already worked. The escape hatch is qualification, and this
   test is what keeps it working. *)
let register_keyword_shadows_a_function_of_that_name () =
  Test.register ~__FILE__
    ~title:"escaping-origins --roots exported: the keyword shadows a function named exported, and qualifying escapes it"
    ~tags:["query"; "origins"; "exported"; "crash"; "shadow"]
  @@ fun () ->
  with_indexed "eoe_shadow" @@ fun db ->
  (* Rename an UNEXPORTED function to [exported] — unexported so the two spellings cannot
     agree by accident: the keyword's set provably excludes it. *)
  Db.with_db_rw db (fun c ->
      Db.exec c "UPDATE functions SET name='exported' WHERE name='orphan_risky'") ;
  let kw_code, kw_out = query [ db; "escaping-origins"; "--roots"; "exported" ] in
  let q_code, q_out = query [ db; "escaping-origins"; "--roots"; "eoe_a.ml:exported" ] in
  Batch.run (fun b ->
      Batch.eq_int b ~msg:"premise: a function named 'exported' now exists"
        (Db.with_db db (fun c -> Db.int c "SELECT count(*) FROM functions WHERE name='exported'"))
        1 ;
      Batch.eq_int b ~msg:"premise: and it is NOT exported, so the two spellings cannot coincide"
        (Db.with_db db (fun c ->
             Db.int c "SELECT COALESCE(exposed,0) FROM functions WHERE name='exported'"))
        0 ;
      Batch.eq_int b ~msg:(Printf.sprintf "the keyword answers:\n%s" kw_out) kw_code 0 ;
      Batch.eq_int b ~msg:(Printf.sprintf "the qualified name answers too:\n%s" q_out) q_code 0 ;
      Batch.check b
        ~msg:(Printf.sprintf "the keyword roots at the API surface, not at the function:\n%s" kw_out)
        (contains ~needle:"root: exported (2 entry point" kw_out) ;
      Batch.check b
        ~msg:(Printf.sprintf "qualifying roots at the FUNCTION — the escape hatch:\n%s" q_out)
        (contains ~needle:"root: eoe_a.ml:exported" q_out) ;
      (* THE POINT. Both exit 0; only the root line distinguishes them. A user who typed
         [--roots exported] before this feature existed gets a different answer and no signal. *)
      Batch.check b ~msg:"the two spellings really do answer about different roots"
        (kw_out <> q_out)) ;
  Lwt.return_unit

let register () =
  register_roots_the_api_surface () ;
  register_refuses_an_unmarked_index () ;
  register_refuses_a_flat_index () ;
  register_refuses_an_index_predating_exposed () ;
  register_keyword_shadows_a_function_of_that_name ()
