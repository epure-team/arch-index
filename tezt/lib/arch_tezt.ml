(******************************************************************************)
(*                                                                            *)
(* Copyright (c) 2026 Epure Team                                              *)
(* All rights reserved.                                                       *)
(*                                                                            *)
(******************************************************************************)

(** Helpers shared by the Tezt integration tests.

    These tests replace shell selftests that shelled out to the [sqlite3] CLI
    and matched its formatted output as text — a comparison in which an empty
    result set, a NULL and the literal string "NULL" all look alike, and in
    which a mistyped column name reads as a passing assertion.  Everything here
    goes through the sqlite3 binding the project already depends on, so those
    are three distinct outcomes and a malformed query is an error.

    [Tezt] and [Tezt.Base] are re-exported so a test file needs a single
    [open Arch_tezt]. *)

include Tezt
include Tezt.Base

(* Under [dune runtest] the cwd is _build/default/tezt/tests and the artefacts
   sit next to it, already inside _build; run by hand from a source directory
   they sit under _build/default.  Trying both at every ancestor covers the two
   without the test having to know which way it was started. *)
let rec find_upwards ~from rel =
  let candidates =
    [Filename.concat from rel; Filename.concat from (Filename.concat "_build/default" rel)]
  in
  match List.find_opt Sys.file_exists candidates with
  | Some _ as found -> found
  | None ->
      let parent = Filename.dirname from in
      if parent = from then None else find_upwards ~from:parent rel

(* An override that points nowhere is a typo, not a request to fall back: the
   search below would quietly find a different binary and the run would look
   like it honoured the variable. *)
let locate ~env_var rel =
  match Sys.getenv_opt env_var with
  | Some p when Sys.file_exists p -> p
  | Some p -> Test.fail "%s is set to %s, which does not exist" env_var p
  | None -> (
      match find_upwards ~from:(Sys.getcwd ()) rel with
      | Some p -> p
      | None ->
          Test.fail "%s not found (looked for %s upwards from %s; set %s to override)"
            env_var rel (Sys.getcwd ()) env_var)

let callgraph_ocaml () =
  locate ~env_var:"ARCH_CALLGRAPH_OCAML"
    "bin/arch_callgraph_ocaml/arch_callgraph_ocaml.exe"

let arch_query () = locate ~env_var:"ARCH_QUERY" "bin/arch_query/arch_query.exe"

let arch_index_cli () =
  locate ~env_var:"ARCH_INDEX_CLI" "bin/arch_index_cli/arch_index_cli.exe"

let schema () = locate ~env_var:"ARCH_SCHEMA" "architecture-schema.sql"

let write_file path contents =
  let dir = Filename.dirname path in
  let rec mkdirs d =
    if not (Sys.file_exists d) then begin
      mkdirs (Filename.dirname d) ;
      try Unix.mkdir d 0o755 with Unix.Unix_error (Unix.EEXIST, _, _) -> ()
    end
  in
  mkdirs dir ;
  let oc = open_out path in
  Fun.protect ~finally:(fun () -> close_out_noerr oc) (fun () ->
      output_string oc contents)

(* The redirection has to cover the [cd] too: [cd d && prog > out] binds the
   redirect to [prog] alone, so a [cd] that fails writes its diagnostic to the
   test's own stderr and hands back an empty capture. *)
let run_command ?(env = []) ?cwd prog args =
  let out = Temp.file (Filename.basename prog ^ ".output") in
  let quoted = List.map Filename.quote (prog :: args) |> String.concat " " in
  let prelude =
    match cwd with None -> "" | Some d -> Printf.sprintf "cd %s && " (Filename.quote d)
  in
  let assignments =
    List.map (fun (k, v) -> Printf.sprintf "%s=%s" k (Filename.quote v)) env
  in
  let cmd =
    Printf.sprintf "{ %s%s %s ; } > %s 2>&1" prelude
      (String.concat " " assignments)
      quoted (Filename.quote out)
  in
  let code = Sys.command cmd in
  let ic = open_in_bin out in
  let contents =
    Fun.protect
      ~finally:(fun () -> close_in_noerr ic)
      (fun () -> really_input_string ic (in_channel_length ic))
  in
  (code, contents)

(* Probe a tool by RUNNING it, never by looking it up on PATH: rustup installs a
   rust-analyzer shim whose component may be missing, and that shim answers a
   PATH check happily and then indexes nothing. *)
let runnable prog args = fst (run_command prog args) = 0

(* [Temp.dir] roots the directory at /tmp/tezt-<pid>/<n>, so two runs on one
   machine cannot collide and nothing outside that root is ever removed.  A
   fixed name under the temp dir would be both racy and, since a directory
   symlink planted at a predictable path resolves before the walk, a way to
   make the test delete somebody else's tree. *)
let with_project ~name ~files k =
  let root = Temp.dir name in
  List.iter
    (fun (rel, contents) -> write_file (Filename.concat root rel) contents)
    files ;
  k root

(* A fixture is a throwaway dune project: the files are written, dune builds it,
   and the .cmt files it produces are what the indexer reads.  Building it here
   rather than committing .cmt files keeps the fixture readable and pins it to
   the compiler in use rather than to the one that happened to generate it. *)
type fixture = {name : string; root : string; build_dir : string}

let with_fixture ~name ~files k =
  with_project ~name ~files @@ fun root ->
  let code, output = run_command "dune" ["build"; "--root"; root] in
  if code <> 0 then Test.fail "fixture %s failed to build:\n%s" name output ;
  k {name; root; build_dir = Filename.concat root "_build/default"}

(* sqlite writes -wal and -shm beside the database.  Tezt's clean-up removes the
   files it handed out, so the sidecars have to be claimed by name too or they
   stay behind at a couple of megabytes a run. *)
let temp_db name =
  let db = Temp.file (name ^ ".db") in
  List.iter (fun ext -> ignore (Temp.file (name ^ ".db" ^ ext))) ["-wal"; "-shm"] ;
  db

let index fixture =
  let db = temp_db fixture.name in
  let code, output =
    run_command (callgraph_ocaml ())
      ["--build-dir"; fixture.build_dir; "--db-path"; db; "--schema-path"; schema ()]
  in
  if code <> 0 then Test.fail "indexing failed (exit %d):\n%s" code output ;
  db

(* The LSP path: [arch_index_cli] drives a real language server over the project
   directory.  A non-zero exit is reported rather than fatal, because a server
   that answers nothing still produces a database, and the assertions on that
   empty database say far more than an exit code does. *)
let index_project ~name project =
  let db = temp_db name in
  let code, output = run_command (arch_index_cli ()) ["--project"; project; "--output"; db] in
  if not (Sys.file_exists db) then
    Test.fail "arch_index produced no database (exit %d):\n%s" code output ;
  db

(* [box] is the default output format and renders as UTF-8 box drawing, which a
   failed [Check] then prints back through %S as octal escapes. *)
let query db args =
  let code, output =
    run_command ~env:[("ARCH_QUERY_FORMAT", "list")] (arch_query ()) (db :: args)
  in
  if code <> 0 then
    Test.fail "arch-query %s failed (exit %d):\n%s" (String.concat " " args) code output ;
  output

(* Typed reads, against the sqlite3 binding the project already depends on. *)
module Db = struct
  let with_db path k =
    let db = Sqlite3.db_open ~mode:`READONLY path in
    Fun.protect ~finally:(fun () -> ignore (Sqlite3.db_close db)) (fun () -> k db)

  (* [prepare] is what rejects a mistyped column, so it has to be inside the
     framing: left bare it raises a Sqlite3.Error naming neither the test nor
     the assertion that issued it. *)
  let rows db sql =
    let stmt =
      try Sqlite3.prepare db sql
      with Sqlite3.Error msg -> Test.fail "malformed query (%s): %s" msg sql
    in
    Fun.protect
      ~finally:(fun () -> ignore (Sqlite3.finalize stmt))
      (fun () ->
        let acc = ref [] in
        let rec step () =
          match Sqlite3.step stmt with
          | Sqlite3.Rc.ROW ->
              let n = Sqlite3.data_count stmt in
              acc := List.init n (fun i -> Sqlite3.column stmt i) :: !acc ;
              step ()
          | Sqlite3.Rc.DONE -> ()
          | rc -> Test.fail "query failed (%s): %s" (Sqlite3.Rc.to_string rc) sql
        in
        step () ;
        List.rev !acc)

  (* Three outcomes, kept distinct.  [None] is "no such row"; a row holding NULL
     is a failure, not a quiet [None], because every column these tests read is
     one whose NULL would itself be the bug; and a value is [Some v]. *)
  let first_column ~sql = function
    | [] -> None
    | [value :: _] -> (
        match value with
        | Sqlite3.Data.NULL -> Test.fail "row holds NULL where a value was expected: %s" sql
        | value -> Some value)
    | (_ :: _ :: _ | [[]]) -> Test.fail "expected at most one row from: %s" sql

  let to_int ~sql = function
    | Sqlite3.Data.INT i -> Int64.to_int i
    | Sqlite3.Data.FLOAT f -> int_of_float f
    | Sqlite3.Data.TEXT s -> (
        match int_of_string_opt s with
        | Some i -> i
        | None -> Test.fail "expected an integer from: %s" sql)
    | _ -> Test.fail "expected an integer from: %s" sql

  let to_string ~sql = function
    | Sqlite3.Data.TEXT s -> s
    | Sqlite3.Data.INT i -> Int64.to_string i
    | Sqlite3.Data.FLOAT f -> string_of_float f
    | _ -> Test.fail "expected a string from: %s" sql

  let int_opt db sql = Option.map (to_int ~sql) (first_column ~sql (rows db sql))

  let int db sql =
    match int_opt db sql with
    | Some i -> i
    | None -> Test.fail "expected one row from: %s" sql

  let string_opt db sql = Option.map (to_string ~sql) (first_column ~sql (rows db sql))

  let strings db sql =
    rows db sql
    |> List.map (function
         | value :: _ -> to_string ~sql value
         | [] -> Test.fail "row has no columns: %s" sql)
end
