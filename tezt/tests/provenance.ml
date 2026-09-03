(******************************************************************************)
(*                                                                            *)
(* Copyright (c) 2026 Epure Team                                              *)
(* All rights reserved.                                                       *)
(*                                                                            *)
(******************************************************************************)

(** Roadmap 1.2 (ADR 002): provenance columns.

    Two independent mechanisms, pinned separately:
    - the main schema's [producer_runs] table + [functions]/[calls].[producer_run_id]
      FK — one row per invocation, joined rather than repeated per row;
    - [bin/arch_load]'s own [--producer]/[--producer-version]/[--soundness-class]
      flags, since that loader is producer-agnostic by design and cannot hardcode
      a producer identity the way the main schema's CMT walker does.

    [tezt/tests/multilang.ml] pins the third mechanism (runner.ml's flat-schema
    [comment_db_meta] keys) alongside its own LSP-backend assertions, since it
    already stands up the real language-server fixtures this would otherwise
    have to duplicate. *)

open Arch_tezt

let main_seed =
  {|
INSERT INTO producer_runs(producer, producer_version, invocation_digest, soundness_class)
  VALUES ('test-producer', 'v9', 'deadbeef', 'sound_with_top');
INSERT INTO modules(path, lines, has_mli) VALUES ('lib/x.ml', 10, 0);
INSERT INTO functions(module_id, name, line_start, line_end, exposed, producer_run_id) VALUES
  ((SELECT id FROM modules WHERE path='lib/x.ml'), 'f', 1, 2, 1,
   (SELECT id FROM producer_runs WHERE producer='test-producer'));
INSERT INTO calls(caller_id, callee_id, callee_name, call_site, kind, producer_run_id) VALUES
  ((SELECT id FROM functions WHERE name='f'), NULL, 'g', 'lib/x.ml:1', 'MUST',
   (SELECT id FROM producer_runs WHERE producer='test-producer'));
-- No producer_run_id: legal (NULL, not a guess) — most historical rows will
-- never have one.
INSERT INTO functions(module_id, name, line_start, line_end, exposed) VALUES
  ((SELECT id FROM modules WHERE path='lib/x.ml'), 'unattributed', 3, 4, 0);
|}

(* A tiny real fixture, indexed by the ACTUAL `arch_callgraph_ocaml` binary —
   not hand-seeded SQL. [main_seed]'s join test below only proves SQLite's own
   FK/JOIN behavior; this proves the CMT walker's write path (arch_index.ml's
   `insert_producer_run` call, `process_cmt`'s threading of `producer_run_id`
   down to `insert_function`, `insert_call_rowid`'s own bind) actually stamps
   real rows — the placeholder-count regression class `insert_rowid_attribution.ml`
   caught once already in this same diff. *)
let real_fixture_files =
  [
    Fixture.dune_project;
    ("dune", "(library\n (name provfix)\n (modules provfix))\n");
    ( "provfix.ml",
      {ocaml|let callee () : int = 1
let caller () : int = callee ()
|ocaml} );
  ]

let register_real_cmt_run () =
  Test.register ~__FILE__
    ~title:"provenance: Arch_index.run stamps a real producer_runs row on real functions/calls"
    ~tags:["provenance"; "cmt"]
  @@ fun () ->
  with_fixture ~name:"arch_tezt_provfix" ~files:real_fixture_files @@ fun fixture ->
  let db_path = index fixture in
  Db.with_db db_path (fun db ->
      Check.(
        (Db.int db "SELECT count(*) FROM functions WHERE producer_run_id IS NULL" = 0)
          int
          ~error_msg:"%L function row(s) have a NULL producer_run_id") ;
      Check.(
        (Db.int db "SELECT count(*) FROM calls WHERE producer_run_id IS NULL" = 0)
          int
          ~error_msg:"%L call row(s) have a NULL producer_run_id") ;
      Check.(
        (Db.string_opt db
           "SELECT DISTINCT pr.producer FROM functions f JOIN producer_runs pr \
            ON f.producer_run_id = pr.id"
         = Some "arch_index_cmt")
          (option string)
          ~error_msg:"functions.producer_run_id should join to producer %R, got %L") ;
      Check.(
        (Db.string_opt db
           "SELECT DISTINCT pr.soundness_class FROM calls c JOIN producer_runs pr \
            ON c.producer_run_id = pr.id"
         = Some "sound_with_top")
          (option string)
          ~error_msg:"calls.producer_run_id should join to soundness_class %R, got %L") ;
      Check.(
        (Db.int db "SELECT count(*) FROM producer_runs" = 1)
          int
          ~error_msg:"exactly one producer_runs row should exist for one invocation, got %L") ;
      Lwt.return_unit)

let register_producer_runs_not_accumulated_across_reindex () =
  Test.register ~__FILE__
    ~title:"provenance: re-indexing the same database does not accumulate producer_runs rows"
    ~tags:["provenance"; "cmt"]
  @@ fun () ->
  with_fixture ~name:"arch_tezt_provfix_reindex" ~files:real_fixture_files @@ fun fixture ->
  let db_path = temp_db "provenance-reindex" in
  let run () =
    let code, output =
      run_command (callgraph_ocaml ())
        ["--build-dir"; fixture.build_dir; "--db-path"; db_path; "--schema-path"; schema ()]
    in
    if code <> 0 then Test.fail "indexing failed (exit %d):\n%s" code output
  in
  run () ;
  run () ;
  Db.with_db db_path (fun db ->
      Check.(
        (Db.int db "SELECT count(*) FROM producer_runs" = 1)
          int
          ~error_msg:
            "re-indexing the same database twice should leave exactly one producer_runs row \
             (the schema is dropped and recreated each run), got %L") ;
      Lwt.return_unit)

let register_main_schema () =
  Test.register ~__FILE__
    ~title:"provenance: functions/calls join producer_runs, not five text columns"
    ~tags:["provenance"; "schema"]
  @@ fun () ->
  let db = Fixture.main ~name:"provenance-main" ~seed:main_seed () in
  Db.with_db db (fun db ->
      Check.(
        (Db.string_opt db
           "SELECT pr.producer FROM functions f JOIN producer_runs pr \
            ON f.producer_run_id = pr.id WHERE f.name = 'f'"
         = Some "test-producer")
          (option string)
          ~error_msg:"functions.producer_run_id should join to %R, got %L") ;
      Check.(
        (Db.string_opt db
           "SELECT pr.soundness_class FROM calls c JOIN producer_runs pr \
            ON c.producer_run_id = pr.id WHERE c.callee_name = 'g'"
         = Some "sound_with_top")
          (option string)
          ~error_msg:"calls.producer_run_id should join to soundness_class %R, got %L") ;
      Check.(
        (Db.int db
           "SELECT producer_run_id IS NULL FROM functions WHERE name = 'unattributed'"
         = 1)
          int
          ~error_msg:"an un-attributed function row should have NULL producer_run_id") ;
      Lwt.return_unit)

let register_soundness_check_constraint () =
  Test.register ~__FILE__
    ~title:"provenance: an invalid soundness_class is rejected, not stored"
    ~tags:["provenance"; "schema"]
  @@ fun () ->
  let db = Fixture.main ~name:"provenance-check" () in
  Db.with_db_rw db (fun conn ->
      (* Positive control first: if this fails, the CHECK constraint (or the
         table) is broken in a way that would make the negative assertion
         below pass for the wrong reason — e.g. on a schema where
         [producer_runs] does not exist at all. *)
      let ok_rc =
        Sqlite3.exec conn
          "INSERT INTO producer_runs(producer, soundness_class) VALUES ('good', 'asserted')"
      in
      let accepted = ok_rc = Sqlite3.Rc.OK in
      Check.((accepted = true) bool ~error_msg:"a valid soundness_class must be accepted") ;
      let rc =
        Sqlite3.exec conn
          "INSERT INTO producer_runs(producer, soundness_class) VALUES ('bad', 'made_up')"
      in
      let rejected = rc <> Sqlite3.Rc.OK in
      Check.(
        (rejected = true)
          bool
          ~error_msg:"an out-of-vocabulary soundness_class must violate the CHECK constraint") ;
      Check.(
        (Db.int conn "SELECT count(*) FROM producer_runs WHERE producer = 'bad'" = 0)
          int
          ~error_msg:"a rejected soundness_class must not leave a row behind, got %L") ;
      Lwt.return_unit)

let register_arch_load_flags () =
  Test.register ~__FILE__
    ~title:"provenance: arch-load's --producer/--soundness-class flags"
    ~tags:["provenance"; "load"]
  @@ fun () ->
  let declared_db = temp_db "provenance-load-declared" in
  if Sys.file_exists declared_db then Sys.remove declared_db ;
  let code, output =
    run_command ~stdin:Fixture.minimal_flat_stream (arch_load ())
      [
        "--producer=callgraph-go"; "--producer-version=v1.2.3";
        "--soundness-class=sound_with_top"; declared_db;
      ]
  in
  if code <> 0 then
    Test.fail "arch-load with provenance flags failed (exit %d):\n%s" code output ;
  Db.with_db declared_db (fun db ->
      Check.(
        (Db.string_opt db "SELECT value FROM comment_db_meta WHERE key = 'producer'"
         = Some "callgraph-go")
          (option string)
          ~error_msg:"comment_db_meta.producer should be %R, got %L") ;
      Check.(
        (Db.string_opt db "SELECT value FROM comment_db_meta WHERE key = 'producer_version'"
         = Some "v1.2.3")
          (option string)
          ~error_msg:"comment_db_meta.producer_version should be %R, got %L") ;
      Check.(
        (Db.string_opt db "SELECT value FROM comment_db_meta WHERE key = 'soundness_class'"
         = Some "sound_with_top")
          (option string)
          ~error_msg:"comment_db_meta.soundness_class should be %R, got %L") ;
      Check.(
        (Db.string_opt db "SELECT value FROM comment_db_meta WHERE key = 'invocation_digest'"
         <> None)
          (option string)
          ~error_msg:"comment_db_meta.invocation_digest should be stamped, got %L")) ;

  (* No flags: the conservative default, and no 'producer' key at all — an
     absent declaration must never be silently reported as a known one. *)
  let default_db = Fixture.minimal_flat ~name:"provenance-load-default" in
  Db.with_db default_db (fun db ->
      Check.(
        (Db.string_opt db "SELECT value FROM comment_db_meta WHERE key = 'soundness_class'"
         = Some "heuristic")
          (option string)
          ~error_msg:"comment_db_meta.soundness_class should default to %R, got %L") ;
      Check.(
        (Db.string_opt db "SELECT value FROM comment_db_meta WHERE key = 'producer'" = None)
          (option string)
          ~error_msg:
            "comment_db_meta.producer must be absent when not declared, got %L — never a \
             guessed value")) ;

  (* An out-of-vocabulary --soundness-class ABORTS, matching this loader's own
     strictness discipline for an invalid `kind`. *)
  let rejected_db = temp_db "provenance-load-rejected" in
  if Sys.file_exists rejected_db then Sys.remove rejected_db ;
  let code, _output =
    run_command ~stdin:Fixture.minimal_flat_stream (arch_load ())
      ["--soundness-class=made_up"; rejected_db]
  in
  Check.(
    (code = 2) int ~error_msg:"an invalid --soundness-class should exit 2, got %L") ;
  Check.(
    (Sys.file_exists rejected_db = false)
      bool
      ~error_msg:"a rejected --soundness-class must not leave a database behind") ;
  Lwt.return_unit

let register () =
  register_real_cmt_run () ;
  register_producer_runs_not_accumulated_across_reindex () ;
  register_main_schema () ;
  register_soundness_check_constraint () ;
  register_arch_load_flags ()
