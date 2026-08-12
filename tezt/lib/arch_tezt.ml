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

let arch_load () = locate ~env_var:"ARCH_LOAD" "bin/arch_load/arch_load.exe"

let arch_body_compare () =
  locate ~env_var:"ARCH_BODY_COMPARE" "bin/arch_body_compare/arch_body_compare.exe"

let arch_coverage_load () =
  locate ~env_var:"ARCH_COVERAGE_LOAD" "bin/arch_coverage_load/arch_coverage_load.exe"

let arch_curate () = locate ~env_var:"ARCH_CURATE" "bin/arch_curate/arch_curate.exe"

let arch_coverage () = locate ~env_var:"ARCH_COVERAGE" "bin/arch_coverage/arch_coverage.exe"

let arch_mutants () = locate ~env_var:"ARCH_MUTANTS" "bin/arch_mutants/arch_mutants.exe"

let decision_lint () =
  locate ~env_var:"ARCH_DECISION_LINT" "poc/decision-lint/bin/decision_lint.exe"
let schema () = locate ~env_var:"ARCH_SCHEMA" "architecture-schema.sql"

let read_file path =
  let ic = open_in_bin path in
  Fun.protect
    ~finally:(fun () -> close_in_noerr ic)
    (fun () -> really_input_string ic (in_channel_length ic))

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

(* A file that must be runnable: stub solvers are written and then executed, and
   a stub written without the execute bit fails as "not found", which reads
   exactly like the absent-solver case it is meant to be distinguished from. *)
let write_exec path contents =
  write_file path contents ;
  Unix.chmod path 0o755

(* The redirection has to cover the [cd] too: [cd d && prog > out] binds the
   redirect to [prog] alone, so a [cd] that fails writes its diagnostic to the
   test's own stderr and hands back an empty capture. *)
let run_command ?(env = []) ?cwd ?stdin prog args =
  let out = Temp.file (Filename.basename prog ^ ".output") in
  let quoted = List.map Filename.quote (prog :: args) |> String.concat " " in
  let prelude =
    match cwd with None -> "" | Some d -> Printf.sprintf "cd %s && " (Filename.quote d)
  in
  let assignments =
    List.map (fun (k, v) -> Printf.sprintf "%s=%s" k (Filename.quote v)) env
  in
  (* Fed from a file rather than a here-doc: the payloads are NDJSON containing
     quotes and braces, and routing them through the shell twice is a quoting
     bug waiting to happen. *)
  let redirect_in =
    match stdin with
    | None -> ""
    | Some contents ->
        let path = Temp.file (Filename.basename prog ^ ".stdin") in
        write_file path contents ;
        Printf.sprintf " < %s" (Filename.quote path)
  in
  let cmd =
    Printf.sprintf "{ %s%s %s%s ; } > %s 2>&1" prelude
      (String.concat " " assignments)
      quoted redirect_in (Filename.quote out)
  in
  let code = Sys.command cmd in
  let ic = open_in_bin out in
  let contents =
    Fun.protect
      ~finally:(fun () -> close_in_noerr ic)
      (fun () -> really_input_string ic (in_channel_length ic))
  in
  (code, contents)

(* Absolute path of a PATH-resolved tool, resolved while PATH is still intact.
   Needed by tests that deliberately empty PATH: the wrapper they run (timeout)
   would otherwise become unfindable too, and the run would fail as 127 rather
   than exercising the case under test. *)
let which prog =
  let code, out = run_command "sh" ["-c"; "command -v " ^ Filename.quote prog] in
  let path = String.trim out in
  if code <> 0 || path = "" then Test.fail "%s not found on PATH" prog else path

(* Probe a tool by RUNNING it, never by looking it up on PATH: rustup installs a
   rust-analyzer shim whose component may be missing, and that shim answers a
   PATH check happily and then indexes nothing. *)
let runnable prog args = fst (run_command prog args) = 0

(* A test that skips itself and reports success is the failure mode this whole
   port is about, so it must not be how CI behaves once the servers are meant to
   be installed: there, ARCH_TEZT_REQUIRE_SERVERS turns a missing toolchain into
   a red test.  On a workstation with only some servers, the run stays useful. *)
let not_exercised fmt =
  Printf.ksprintf
    (fun reason ->
      if Sys.getenv_opt "ARCH_TEZT_REQUIRE_SERVERS" = Some "1" then
        Test.fail "%s -- and ARCH_TEZT_REQUIRE_SERVERS=1 forbids skipping" reason
      else Log.warn "not exercised: %s" reason)
    fmt

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
(* Exit code AND output: several assertions are about arch-query REFUSING (exit
   3 on an index that cannot support the verdict), where a helper that turns a
   non-zero exit into a test failure would make the refusal untestable. *)
let query_raw db args =
  run_command ~env:[("ARCH_QUERY_FORMAT", "list")] (arch_query ()) (db :: args)

let query db args =
  let code, output = query_raw db args in
  if code <> 0 then
    Test.fail "arch-query %s failed (exit %d):\n%s" (String.concat " " args) code output ;
  output

(* Batched assertions.

   Tezt's [Check] raises on the first failure, which is the right default for a
   test whose assertions build on each other. The shell selftests being ported
   here are not that shape: they run dozens of independent probes over one
   fixture and their [note] accumulator reported the whole batch, so one run told
   you everything that was broken. Losing that would make a 76-assertion suite
   take 76 runs to diagnose.

   Tezt does not export the exception [Check] raises, so a batch cannot be built
   by catching it. The assertions below therefore format their own comparisons —
   giving up [Check]'s %L/%R for messages that name the expectation, the actual
   value and the query that produced it — and [run] turns a non-empty batch into
   a single [Test.fail] carrying all of them.

   Use [Check] for a precondition the rest of the test depends on; use a batch
   for independent probes. *)
module Batch = struct
  type t = {mutable failures : string list}

  let note t fmt = Printf.ksprintf (fun s -> t.failures <- s :: t.failures) fmt

  let check t ~msg cond = if not cond then note t "%s" msg

  let eq_int t ~msg actual expected =
    if actual <> expected then note t "%s: got %d, expected %d" msg actual expected

  let ge_int t ~msg actual bound =
    if actual < bound then note t "%s: got %d, expected >= %d" msg actual bound

  let eq_string t ~msg actual expected =
    if actual <> expected then note t "%s: got %S, expected %S" msg actual expected

  let eq_string_opt t ~msg actual expected =
    let show = function None -> "<no row>" | Some s -> Printf.sprintf "%S" s in
    if actual <> expected then
      note t "%s: got %s, expected %s" msg (show actual) (show expected)

  (* Substring search on a tool's output. Reported with the haystack truncated,
     because these are multi-line CLI captures and an untruncated dump buries
     the other failures in the batch. *)
  let contains t ~msg ~haystack needle =
    let n = String.length needle and h = String.length haystack in
    let found = ref false in
    for i = 0 to h - n do
      if (not !found) && String.sub haystack i n = needle then found := true
    done ;
    if not !found then
      let shown =
        if h <= 400 then haystack else String.sub haystack 0 400 ^ "\n  [...truncated]"
      in
      note t "%s: %S not found in:\n%s" msg needle shown

  let not_contains t ~msg ~haystack needle =
    let n = String.length needle and h = String.length haystack in
    let found = ref false in
    for i = 0 to h - n do
      if (not !found) && String.sub haystack i n = needle then found := true
    done ;
    if !found then note t "%s: %S should not appear, but does" msg needle

  (* Exit codes carry meaning in this project — 2 is broken input, 3 is "this
     index cannot answer that soundly" — so they are asserted constantly. The
     output is folded into the message because a bare "got 1, expected 3" sends
     you back to re-run the command by hand to find out why. *)
  let exit_code t ~msg ~expected (code, output) =
    if code <> expected then
      note t "%s: exited %d, expected %d\n%s" msg code expected
        (if String.length output <= 400 then output
         else String.sub output 0 400 ^ "\n  [...truncated]")

  (* The Result-returning JSON accessors fold into a batch instead of raising, so
     one malformed field does not hide every later assertion. *)
  let expect t = function
    | Ok v -> Some v
    | Error e ->
        note t "%s" e ;
        None

  let run k =
    let t = {failures = []} in
    k t ;
    match List.rev t.failures with
    | [] -> ()
    | fs ->
        Test.fail "%d assertion(s) failed:\n%s" (List.length fs)
          (String.concat "\n" (List.map (fun f -> "  - " ^ f) fs))
end

(* Machine-output assertions.

   These surfaces are consumed by other programs, so their SHAPE is the
   contract: a renamed key breaks a caller even when the human-readable line
   still reads correctly. Parsing rather than grepping is what makes that
   testable — and it also removes the python3 dependency the shell versions
   carried, where an absent interpreter silently skipped the check. *)
module Json = struct
  let parse ~what s =
    match Yojson.Safe.from_string s with
    | v -> Ok v
    | exception exn -> Error (Printf.sprintf "%s is not parseable JSON (%s):\n%s" what (Printexc.to_string exn) s)

  let member k = function `Assoc fields -> List.assoc_opt k fields | _ -> None

  let show = function None -> "<absent>" | Some v -> Yojson.Safe.to_string v

  let int ~what k j =
    match member k j with
    | Some (`Int n) -> Ok n
    | other -> Error (Printf.sprintf "%s.%s is not an int (%s)" what k (show other))

  let bool ~what k j =
    match member k j with
    | Some (`Bool v) -> Ok v
    | other -> Error (Printf.sprintf "%s.%s is not a bool (%s)" what k (show other))

  let list ~what k j =
    match member k j with
    | Some (`List l) -> Ok l
    | other -> Error (Printf.sprintf "%s.%s is not a list (%s)" what k (show other))

  (* A list of strings, or of one string field pulled out of a list of objects —
     the two shapes these reports actually use. *)
  let strings ~what k j =
    match member k j with
    | Some (`List l) ->
        Ok (List.filter_map (function `String s -> Some s | _ -> None) l)
    | other -> Error (Printf.sprintf "%s.%s is not a list of strings (%s)" what k (show other))

  let field_of_objects ~field l =
    List.filter_map
      (function `Assoc f -> ( match List.assoc_opt field f with Some (`String s) -> Some s | _ -> None)
        | _ -> None)
      l
end

(* Typed reads, against the sqlite3 binding the project already depends on. *)
module Db = struct
  let with_db path k =
    let db = Sqlite3.db_open ~mode:`READONLY path in
    Fun.protect ~finally:(fun () -> ignore (Sqlite3.db_close db)) (fun () -> k db)

  (* Read-write, for tests that BUILD a fixture database rather than read one the
     indexer produced. *)
  let with_db_rw path k =
    let db = Sqlite3.db_open path in
    Fun.protect ~finally:(fun () -> ignore (Sqlite3.db_close db)) (fun () -> k db)

  (* Multi-statement script. Returns the sqlite error rather than failing, so a
     caller testing "does this SQL still run" can report it as one batched
     assertion instead of aborting the whole test. *)
  let exec_result db sql =
    match Sqlite3.exec db sql with
    | Sqlite3.Rc.OK -> Ok ()
    | rc -> Error (Printf.sprintf "%s: %s" (Sqlite3.Rc.to_string rc) (Sqlite3.errmsg db))
    | exception Sqlite3.Error msg -> Error msg

  let exec db sql =
    match exec_result db sql with Ok () -> () | Error e -> Test.fail "SQL failed (%s): %s" e sql

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

(* Fixtures shared across tests.

   These live here rather than being copied per test file for a specific reason:
   the shell selftests could not share them, and said so — four of them carried a
   comment reading "same malformed-⊤-marked fixture as selftest-contract.sh's ML
   case", which is a cross-reference standing in for the sharing bash could not
   express. Repeating that duplication in OCaml would be importing a limitation
   along with the tests. When the contract changes, one definition changes. *)
module Fixture = struct
  (* The smallest well-formed producer stream: one exported function calling one
     private one, over a MUST edge. Used wherever a test needs "a valid flat
     index" as a backdrop rather than as its subject. *)
  let minimal_flat_stream =
    {|{"type":"function","name":"f","file_path":"x","exported":true}
{"type":"function","name":"g","file_path":"x"}
{"type":"call","caller_name":"f","callee_name":"g","call_site":"x:1","kind":"MUST"}
|}

  (* A flat (arch-load) index built from an NDJSON stream.

     The database is removed first: arch-load must ABORT without creating one on
     a bad stream, and Temp.file only reserves a name, so a leftover from an
     earlier case would make that assertion meaningless. *)
  let flat ~name stream =
    let db = temp_db name in
    if Sys.file_exists db then Sys.remove db ;
    let code, output = run_command ~stdin:stream (arch_load ()) [db] in
    if code <> 0 then
      Test.fail "building flat fixture %s failed (exit %d):\n%s" name code output ;
    db

  let minimal_flat ~name = flat ~name minimal_flat_stream

  (* A main-schema index: architecture-schema.sql, then the caller's seed rows. *)
  let main ~name ?seed () =
    let db = temp_db name in
    Db.with_db_rw db (fun conn ->
        Db.exec conn (read_file (schema ())) ;
        Option.iter (Db.exec conn) seed) ;
    db

  (* The flag is set and `kind` exists, but a REAL edge on the A -> mid -> sink
     path carries NULL.

     This is the adversarial case every consumer of the contract is measured
     against: NULL is invisible to both sides of a SQL filter under three-valued
     logic, so an index that merely LOOKS marked reads as a false-sound
     UNREACHABLE. arch-query must refuse it, and arch-impact, arch-rules,
     arch-coverage and arch-mutants must all agree it is unsound — they share
     Arch_db.contract_ok, so a fixture they share is the honest way to test that
     they cannot drift apart. *)
  let malformed_contract ~name =
    let db = temp_db name in
    Db.with_db_rw db (fun conn ->
        Db.exec conn
          {|
CREATE TABLE comment_db_meta(key TEXT, value TEXT);
INSERT INTO comment_db_meta VALUES('callgraph_contract','v1');
CREATE TABLE functions(name TEXT, file_path TEXT, exported INT, line_start INT, line_end INT);
INSERT INTO functions VALUES('A','x',1,NULL,NULL),('mid','x',0,NULL,NULL),('sink','x',0,NULL,NULL);
CREATE TABLE calls(caller_name TEXT, caller_file TEXT, callee_name TEXT, callee_file TEXT, call_site TEXT, kind TEXT);
INSERT INTO calls VALUES ('A','x','mid','x','x:1','MUST'),('mid','x','sink','x','x:2',NULL);
|}) ;
    db
end

(* Non-empty lines of a tool's output: a row count should count rows, not the
   blank lines a formatter happens to emit. *)
let lines output =
  String.split_on_char '\n' output |> List.filter (fun l -> String.trim l <> "")

let has_prefix ~prefix s =
  String.length s >= String.length prefix && String.sub s 0 (String.length prefix) = prefix
