module Functors = Arch_index__Arch_index_functors
exception Setup_error of string
exception Assertion_failure of string
let setup f = Printf.ksprintf (fun s -> raise (Setup_error s)) f
let assertion f = Printf.ksprintf (fun s -> raise (Assertion_failure s)) f
let exec db sql = match Sqlite3.exec db sql with Sqlite3.Rc.OK -> () | rc -> setup "SQL setup failed (%s): %s" (Sqlite3.Rc.to_string rc) (Sqlite3.errmsg db)
let scalar db sql =
  let s = Sqlite3.prepare db sql in
  Fun.protect ~finally:(fun () -> ignore (Sqlite3.finalize s)) @@ fun () ->
  match Sqlite3.step s with Sqlite3.Rc.ROW -> Sqlite3.column_int s 0 | rc -> setup "scalar read failed: %s" (Sqlite3.Rc.to_string rc)
let marker db = scalar db "SELECT count(*) FROM comment_db_meta WHERE key='functor_catalogue_contract' AND value='v1'"
let require_not_finalized db label =
  let finalized = Functors.finalize_contract db ~selected_inputs:1 in
  if finalized || marker db <> 0 then assertion "%s unexpectedly finalized" label
let app artifact = Printf.sprintf "INSERT INTO functor_applications VALUES(1,'%s',1,'apply','{\"file\":\"fixture.ml\",\"start_line\":1,\"start_col\":0,\"end_line\":1,\"end_col\":1,\"ghost\":false}','{\"kind\":\"path\",\"compiler\":\"F\",\"source\":\"F\",\"contains_apply\":false}','{\"kind\":\"path\",\"compiler\":\"A\",\"source\":\"A\",\"contains_apply\":false}','[]')" artifact
let run () =
  let db = Sqlite3.db_open ":memory:" in
  Fun.protect ~finally:(fun () -> ignore (Sqlite3.db_close db)) @@ fun () ->
  List.iter (exec db) [
    "CREATE TABLE comment_db_meta(key TEXT PRIMARY KEY,value TEXT)";
    "CREATE TABLE graph_facts(value TEXT NOT NULL)"; "INSERT INTO graph_facts VALUES('preserved')";
    "CREATE TABLE producer_runs(id INTEGER PRIMARY KEY)"; "CREATE TABLE modules(id INTEGER PRIMARY KEY,path TEXT)";
    "CREATE TABLE functor_catalogue_runs(producer_run_id INTEGER PRIMARY KEY,selected_inputs INTEGER)";
    "CREATE TABLE functor_catalogue_inputs(producer_run_id INTEGER,artifact TEXT,source TEXT,compiler_unit TEXT,module_id INTEGER,outcome TEXT,expected_applications INTEGER)";
    "CREATE TABLE functor_applications(producer_run_id INTEGER,artifact TEXT,ordinal INTEGER,application_kind TEXT,location TEXT,head TEXT,argument TEXT,diagnostics TEXT)";
    "INSERT INTO comment_db_meta VALUES('functor_catalogue_contract','v1')" ];
  Functors.clear_contract db ; if marker db <> 0 then assertion "clear_contract left marker";
  List.iter (exec db) ["INSERT INTO producer_runs VALUES(1)"; "INSERT INTO modules VALUES(1,'fixture.ml')";
    "INSERT INTO functor_catalogue_inputs VALUES(1,'seed.cmt','fixture.ml','Fixture',1,'collected',1)"];
  exec db (app "seed.cmt"); require_not_finalized db "missing header";
  exec db "INSERT INTO functor_catalogue_runs VALUES(1,1)";
  exec db "UPDATE functor_catalogue_inputs SET producer_run_id=2"; exec db "UPDATE functor_applications SET producer_run_id=2"; require_not_finalized db "input run differs from header run";
  exec db "UPDATE functor_catalogue_inputs SET producer_run_id=1"; exec db "UPDATE functor_applications SET producer_run_id=1";
  exec db "UPDATE functor_catalogue_inputs SET source='wrong-source.ml'"; require_not_finalized db "source differs from module path";
  exec db "UPDATE functor_catalogue_inputs SET source='fixture.ml'";
  exec db "UPDATE functor_catalogue_inputs SET module_id=2"; require_not_finalized db "dangling module";
  exec db "UPDATE functor_catalogue_inputs SET module_id=1,expected_applications=2"; require_not_finalized db "expected mismatch";
  exec db "UPDATE functor_catalogue_inputs SET expected_applications=1"; exec db (app "orphan.cmt"); require_not_finalized db "orphan application";
  exec db "DELETE FROM functor_applications WHERE artifact='orphan.cmt'";
  let before = marker db and finalized = Functors.finalize_contract db ~selected_inputs:1 in
  let after = marker db and graph = scalar db "SELECT count(*) FROM graph_facts WHERE value='preserved'" in
  if before <> 0 || not finalized || after <> 1 || graph <> 1 then assertion "valid lifecycle finalization failed";
  Yojson.Safe.to_channel stdout (`Assoc [("ok", `Bool true); ("premise", `String "real-lifecycle-boundaries"); ("negative_variants", `List (List.map (fun x -> `String x) ["missing-header";"wrong-input-run";"wrong-source";"dangling-module";"expected-count-mismatch";"orphan-application"])); ("marker_before_finalize", `Int before); ("finalized", `Bool finalized); ("marker_after_finalize", `Int after); ("graph_facts", `Int graph)])
let () = try run () with Setup_error s -> prerr_endline ("lifecycle_probe setup: " ^ s); exit 2 | Assertion_failure s -> prerr_endline ("lifecycle_probe assertion: " ^ s); exit 1 | Failure s -> prerr_endline ("lifecycle_probe setup: " ^ s); exit 2 | exn -> prerr_endline ("lifecycle_probe setup: " ^ Printexc.to_string exn); exit 2
