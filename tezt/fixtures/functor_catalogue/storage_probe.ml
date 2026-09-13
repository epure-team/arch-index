(* Real savepoint rollback probe.  The trigger is owned by this in-memory test
   database; production receives no fault-injection flag or branch. *)

module Functors = Arch_index__Arch_index_functors

exception Setup_error of string
exception Assertion_failure of string

let setup fmt = Printf.ksprintf (fun message -> raise (Setup_error message)) fmt
let assertion fmt = Printf.ksprintf (fun message -> raise (Assertion_failure message)) fmt

let exec db sql =
  match Sqlite3.exec db sql with
  | Sqlite3.Rc.OK -> ()
  | rc -> setup "SQL setup failed (%s): %s" (Sqlite3.Rc.to_string rc) (Sqlite3.errmsg db)

let scalar db sql =
  let statement = Sqlite3.prepare db sql in
  Fun.protect ~finally:(fun () -> ignore (Sqlite3.finalize statement)) @@ fun () ->
  match Sqlite3.step statement with
  | Sqlite3.Rc.ROW -> Sqlite3.column_int statement 0
  | rc -> setup "scalar read failed: %s" (Sqlite3.Rc.to_string rc)

let occurrence ordinal : Functors.occurrence =
  { ordinal; application_kind = Functors.Apply;
    location = {|{"file":"fixture.ml","start_line":1,"start_col":0,"end_line":1,"end_col":1,"ghost":false}|};
    head = {|{"kind":"path","compiler":"F","source":"F","contains_apply":false}|};
    argument = {|{"kind":"path","compiler":"A","source":"A","contains_apply":false}|};
    diagnostics = "[]" }

let run () =
  let db = Sqlite3.db_open ":memory:" in
  Fun.protect ~finally:(fun () -> ignore (Sqlite3.db_close db)) @@ fun () ->
  exec db "CREATE TABLE graph_facts(value TEXT NOT NULL)" ;
  exec db "INSERT INTO graph_facts VALUES('preserved')" ;
  exec db "CREATE TABLE functor_catalogue_inputs(producer_run_id INTEGER,artifact TEXT,source TEXT,compiler_unit TEXT,module_id INTEGER,outcome TEXT,expected_applications INTEGER)" ;
  exec db "CREATE TABLE functor_applications(producer_run_id INTEGER,artifact TEXT,ordinal INTEGER,application_kind TEXT,location TEXT,head TEXT,argument TEXT,diagnostics TEXT)" ;
  (* Fail after ordinal 1 has been inserted.  The real store's SAVEPOINT must
     roll that inserted row and its input row back together. *)
  exec db "CREATE TRIGGER fail_after_first AFTER INSERT ON functor_applications WHEN NEW.ordinal=1 BEGIN SELECT RAISE(FAIL,'owned mid-input trigger'); END" ;
  let raised =
    try
      Functors.store_collected db ~producer_run_id:7 ~artifact:"seed.cmt"
        ~source:"fixture.ml" ~compiler_unit:"Fixture" ~module_id:1
        [occurrence 1; occurrence 2] ;
      false
    with Failure _ -> true
  in
  let inputs = scalar db "SELECT count(*) FROM functor_catalogue_inputs" in
  let applications = scalar db "SELECT count(*) FROM functor_applications" in
  let graph_facts = scalar db "SELECT count(*) FROM graph_facts WHERE value='preserved'" in
  if not raised then assertion "expected real store_collected to surface owned trigger failure" ;
  if inputs <> 0 || applications <> 0 || graph_facts <> 1 then
    assertion "rollback invariant failed: inputs=%d applications=%d graph_facts=%d" inputs applications graph_facts ;
  Yojson.Safe.to_channel stdout
    (`Assoc [("ok", `Bool true); ("premise", `String "mid-input-storage-rollback");
             ("trigger", `String "after-first-functor-application");
             ("raised", `Bool raised); ("catalogue_inputs", `Int inputs);
             ("functor_applications", `Int applications); ("graph_facts", `Int graph_facts)])

let collection_failed () =
  let db = Sqlite3.db_open ":memory:" in
  Fun.protect ~finally:(fun () -> ignore (Sqlite3.db_close db)) @@ fun () ->
  exec db "CREATE TABLE graph_facts(value TEXT NOT NULL)" ;
  exec db "INSERT INTO graph_facts VALUES('preserved')" ;
  exec db "CREATE TABLE functor_catalogue_inputs(producer_run_id INTEGER,artifact TEXT,source TEXT,compiler_unit TEXT,module_id INTEGER,outcome TEXT,expected_applications INTEGER)" ;
  exec db "CREATE TABLE functor_applications(producer_run_id INTEGER,artifact TEXT,ordinal INTEGER,application_kind TEXT,location TEXT,head TEXT,argument TEXT,diagnostics TEXT)" ;
  exec db "CREATE TRIGGER fail_after_first AFTER INSERT ON functor_applications WHEN NEW.ordinal=1 BEGIN SELECT RAISE(FAIL,'owned mid-input trigger'); END" ;
  let raised =
    try Functors.store_collected db ~producer_run_id:7 ~artifact:"failed.cmt"
      ~source:"fixture.ml" ~compiler_unit:"Fixture" ~module_id:1 [occurrence 1; occurrence 2] ; false
    with Failure _ -> true
  in
  if not raised || scalar db "SELECT count(*) FROM functor_catalogue_inputs" <> 0
     || scalar db "SELECT count(*) FROM functor_applications" <> 0 then
    assertion "failed collection did not roll back before outcome recording" ;
  Functors.store_outcome db ~producer_run_id:7 ~artifact:"failed.cmt" ~outcome:"collection_failed" ;
  let inputs = scalar db "SELECT count(*) FROM functor_catalogue_inputs" in
  let applications = scalar db "SELECT count(*) FROM functor_applications" in
  let graph_facts = scalar db "SELECT count(*) FROM graph_facts WHERE value='preserved'" in
  let statement = Sqlite3.prepare db "SELECT outcome,expected_applications FROM functor_catalogue_inputs" in
  let outcome, expected = Fun.protect ~finally:(fun () -> ignore (Sqlite3.finalize statement)) @@ fun () ->
    match Sqlite3.step statement with
    | Sqlite3.Rc.ROW ->
        (match Sqlite3.column statement 0, Sqlite3.column statement 1 with
        | Sqlite3.Data.TEXT value, Sqlite3.Data.INT count -> (value, Int64.to_int count)
        | _ -> setup "outcome row has unexpected column types")
    | rc -> setup "outcome query failed: %s" (Sqlite3.Rc.to_string rc) in
  if inputs <> 1 || applications <> 0 || graph_facts <> 1 || outcome <> "collection_failed" || expected <> 0 then assertion "collection_failed persistence invariant failed" ;
  Yojson.Safe.to_channel stdout (`Assoc [("ok", `Bool true); ("premise", `String "real-store-outcome");
    ("raised", `Bool raised); ("outcome", `String outcome); ("expected_applications", `Int expected);
    ("catalogue_inputs", `Int inputs); ("functor_applications", `Int applications); ("graph_facts", `Int graph_facts)])

let () =
  try (match Array.to_list Sys.argv with [_] -> run () | [_; "--collection-failed"] -> collection_failed () | _ -> raise (Setup_error "usage: storage_probe [--collection-failed]")) with
  | Setup_error message -> prerr_endline ("storage_probe setup: " ^ message) ; exit 2
  | Assertion_failure message -> prerr_endline ("storage_probe assertion: " ^ message) ; exit 1
  | Failure message -> prerr_endline ("storage_probe setup: unexpected product/runtime failure: " ^ message) ; exit 2
  | exn -> prerr_endline ("storage_probe setup: " ^ Printexc.to_string exn) ; exit 2
