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

let arch_rules () = locate ~env_var:"ARCH_RULES" "bin/arch_rules/arch_rules.exe"

let arch_impact () = locate ~env_var:"ARCH_IMPACT" "bin/arch_impact/arch_impact.exe"

let arch_mutants () = locate ~env_var:"ARCH_MUTANTS" "bin/arch_mutants/arch_mutants.exe"

let arch_coverage_matrix () =
  locate ~env_var:"ARCH_COVERAGE_MATRIX" "bin/arch_coverage_matrix/arch_coverage_matrix.exe"

let decision_lint () =
  locate ~env_var:"ARCH_DECISION_LINT" "poc/decision-lint/bin/decision_lint.exe"
let schema () = locate ~env_var:"ARCH_SCHEMA" "architecture-schema.sql"

(* The repository root, found via a wrapper that only exists there. The pcc-*
   tools resolve their siblings with `command -v arch-impact` while running with
   CWD set to the TARGET repo, so both this directory and scripts/pcc have to be
   on PATH — which is exactly how the workflow's operator invokes them. *)
let repo_root () = Filename.dirname (locate ~env_var:"ARCH_REPO_ROOT" "arch-impact")
let pcc_dir () = Filename.dirname (locate ~env_var:"ARCH_PCC_DIR" "scripts/pcc/pcc-index")

(* The Go producer is built from source by the test rather than assumed
   installed: it is part of this repository, so a stale binary on PATH would
   test something other than the tree. *)
let callgraph_go_src () =
  Filename.dirname (locate ~env_var:"ARCH_CALLGRAPH_GO_SRC" "callgraph-go/main.go")

(* Index of the first occurrence of [needle] in [haystack]. Substring search is
   not in the stdlib, so every test that needed it grew its own loop; five
   copies of the same off-by-one is five chances to write a search that never
   matches and an assertion that therefore never fires. *)
let index_of ~needle haystack =
  let n = String.length needle and h = String.length haystack in
  if n = 0 then Some 0
  else
    let rec scan i =
      if i > h - n then None
      else if String.sub haystack i n = needle then Some i
      else scan (i + 1)
    in
    scan 0

let contains ~needle haystack = index_of ~needle haystack <> None

(* The text following the first [marker], up to the end of that line. Reading a
   value a tool prints as "label: value" is common enough to share. *)
let field_after ~marker output =
  match index_of ~needle:marker output with
  | None -> None
  | Some i ->
      let start = i + String.length marker in
      let rest = String.sub output start (String.length output - start) in
      Some
        (String.trim
           (match String.index_opt rest '\n' with
           | Some j -> String.sub rest 0 j
           | None -> rest))

(* The single token arch-query's answer turns on. Matching the FIRST occurrence
   of one of these, rather than scanning for a substring anywhere, is what stops
   a function whose own name contains "UNREACHABLE" inverting its own verdict —
   and what stops the assertion itself doing so: "REACHABLE" is a substring of
   "UNREACHABLE", so `contains "REACHABLE"` cannot tell a may-reach answer from
   a proof of unreachability. That mistake shipped in two test files while this
   function sat, unshared, in a third.

   Shared here for that reason: any test asserting on a verdict must go through
   it. *)
let verdict_token output =
  let tokens =
    ["PATH EXISTS"; "no MUST path"; "REACHABLE (may-reach)"; "UNREACHABLE:"; "UNKNOWN:"; "REFUSED"]
  in
  let best = ref None in
  List.iter
    (fun t ->
      match index_of ~needle:t output with
      | None -> ()
      | Some i -> (
          match !best with
          | Some (j, _) when j <= i -> ()
          | _ -> best := Some (i, t)))
    tokens ;
  match !best with Some (_, t) -> t | None -> "<no verdict token>"

(* A port the OS says is free right now: bind 0, read what was assigned, release.

   Not a fixed constant. A fixed port cannot be made safe — two tests in one
   file raced over one, and the same test raced itself under [--loop-count -j].
   Worse, a fixed port was documented as making a LEAKED server fail the run,
   which is its exact inverse: a squatter answers the assertions and they pass
   green against a foreign process.

   There is still a window between the close here and the server's bind, so
   callers pair this with a check that nothing answers before they spawn. *)
let free_port () =
  let sock = Unix.socket Unix.PF_INET Unix.SOCK_STREAM 0 in
  Fun.protect
    ~finally:(fun () -> try Unix.close sock with _ -> ())
    (fun () ->
      Unix.setsockopt sock Unix.SO_REUSEADDR true ;
      Unix.bind sock (Unix.ADDR_INET (Unix.inet_addr_loopback, 0)) ;
      match Unix.getsockname sock with
      | Unix.ADDR_INET (_, p) -> p
      | Unix.ADDR_UNIX _ -> Test.fail "free_port: bound socket is not an inet socket")

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

(* Same, but with the two streams kept APART.

   [run_command] merges stderr into stdout, which is what you want when the
   output is for a human to read in a failure message. It makes one class of
   assertion impossible though: "stdout is exactly one JSON object" cannot be
   checked when a diagnostic line written to stderr lands in the middle of it.
   Tools with a machine-readable stdout are asserted through this instead. *)
let run_command_split ?(env = []) ?cwd prog args =
  let out = Temp.file (Filename.basename prog ^ ".stdout") in
  let err = Temp.file (Filename.basename prog ^ ".stderr") in
  let quoted = List.map Filename.quote (prog :: args) |> String.concat " " in
  let prelude =
    match cwd with None -> "" | Some d -> Printf.sprintf "cd %s && " (Filename.quote d)
  in
  let assignments =
    List.map (fun (k, v) -> Printf.sprintf "%s=%s" k (Filename.quote v)) env
  in
  let code =
    Sys.command
      (Printf.sprintf "{ %s%s %s ; } > %s 2> %s" prelude
         (String.concat " " assignments)
         quoted (Filename.quote out) (Filename.quote err))
  in
  (code, read_file out, read_file err)

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

(* An EXTERNAL SERVICE failed — the npm registry, a network fetch — as opposed
   to a tool being absent.

   Never escalated by ARCH_TEZT_REQUIRE_SERVERS, and that is the point of the
   distinction. CI can reasonably insist a toolchain is installed, because
   installing it is CI's own job; it cannot insist a third-party registry is up.
   Routing a registry outage through [not_exercised] made the strict flag turn
   somebody else's downtime into a red build, which is how a team learns to
   ignore red.

   It has its OWN flag instead, ARCH_TEZT_REQUIRE_NETWORK, because silence here
   is not free: [multilang.ml] is the only cover for the merged polyglot index,
   and with the registry unreachable it ran ZERO assertions and reported
   SUCCESS. A run that decides to skip that must be a decision, not a default —
   so a machine with no network stays green, and CI, which does have one, says
   so and fails if it turns out not to. *)
let external_failure fmt =
  Printf.ksprintf
    (fun reason ->
      if Sys.getenv_opt "ARCH_TEZT_REQUIRE_NETWORK" = Some "1" then
        Test.fail "%s -- and ARCH_TEZT_REQUIRE_NETWORK=1 forbids skipping" reason
      else Log.warn "not exercised (external): %s" reason)
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
   directory. A non-zero exit is NOT fatal, because a server that answers
   nothing still produces a database and the assertions on that empty database
   say far more than an exit code does — but it is logged, which the comment
   here used to claim ("reported rather than fatal") while the code did neither:
   [code] was read only inside the failure message for a missing file, so a
   non-zero exit on a database that WAS produced vanished without trace. *)
let index_project ~name project =
  let db = temp_db name in
  let code, output = run_command (arch_index_cli ()) ["--project"; project; "--output"; db] in
  if not (Sys.file_exists db) then
    Test.fail "arch_index produced no database (exit %d):\n%s" code output ;
  if code <> 0 then
    Log.warn "arch_index exited %d but produced a database; asserting on it anyway:\n%s" code
      output ;
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
  (* Bound before [contains] below shadows the top-level one. *)
  let has_substring = contains

  let contains t ~msg ~haystack needle =
    if not (has_substring ~needle haystack) then
      let h = String.length haystack in
      let shown =
        if h <= 400 then haystack else String.sub haystack 0 400 ^ "\n  [...truncated]"
      in
      note t "%s: %S not found in:\n%s" msg needle shown

  let not_contains t ~msg ~haystack needle =
    if has_substring ~needle haystack then
      note t "%s: %S should not appear, but does" msg needle

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

  (* Same, for a list read that feeds a "must not contain" assertion. Written
     as `match … with Ok l -> l | Error _ -> []` it defaults the failure away:
     the empty list satisfies every negative assertion, so a report that stopped
     emitting the field entirely reads as a clean bill of health. The error is
     recorded, and the caller still gets a list to carry on with. *)
  let list_or_empty t r = match expect t r with Some l -> l | None -> []

  (* The body is run under [Fun.protect]-style capture rather than bare, because
     raising out of it is NORMAL, not exceptional: [query] fails the test on a
     non-zero exit, [Db.int] on an absent row, every [Fixture] constructor on a
     build failure — and all of them are routinely called from inside a batch.

     Bare, `k t` raising skipped the report entirely and threw away every
     failure collected before it, which is the one-failure-per-run outcome this
     module exists to prevent, reached from inside the module itself. The
     exception is now the LAST line of the batch report rather than a
     replacement for it. *)
  let run k =
    let t = {failures = []} in
    let raised = match k t with () -> None | exception e -> Some e in
    let collected = List.rev t.failures in
    let lines =
      List.map (fun f -> "  - " ^ f) collected
      @ (match raised with
        | None -> []
        | Some e -> ["  - (the batch then aborted: " ^ Printexc.to_string e ^ ")"])
    in
    match lines with
    | [] -> ()
    | _ ->
        Test.fail "%d assertion(s) failed:\n%s" (List.length lines)
          (String.concat "\n" lines)
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

  (* A list of strings. An element that is NOT a string is an error, not
     something to skip.

     [filter_map] here returned [Ok []] for a list of objects — a shape the old
     comment even claimed to support — so a report that changed
     ["a"] to [{"file": "a"}] read as "the list is empty". Every caller feeds
     these into absence assertions ("no diff content line became a file"), and
     an empty list satisfies all of them: the breaking change and the guard
     against it disappeared together. *)
  let strings ~what k j =
    match member k j with
    | Some (`List l) ->
        let bad = List.find_opt (function `String _ -> false | _ -> true) l in
        (match bad with
        | Some v ->
            Error
              (Printf.sprintf "%s.%s contains a non-string element (%s)" what k
                 (Yojson.Safe.to_string v))
        | None -> Ok (List.filter_map (function `String s -> Some s | _ -> None) l))
    | other -> Error (Printf.sprintf "%s.%s is not a list of strings (%s)" what k (show other))

  (* The machine-output contract is int/bool/string/null/array/object only. A
     float is the interesting violation: it round-trips through most readers and
     then compares unequal on a different platform, so it has to be rejected at
     the shape level rather than noticed later. Intlit is the same hazard wearing
     Yojson's clothes — an integer too large to have been intended. *)
  let strict_object ~what s =
    match Yojson.Safe.from_string s with
    | exception exn ->
        Error (Printf.sprintf "%s is not parseable JSON (%s):\n%s" what (Printexc.to_string exn) s)
    | `Assoc _ as j ->
        let bad = ref None in
        let rec walk : Yojson.Safe.t -> unit = function
          | `Float f -> if !bad = None then bad := Some (Printf.sprintf "float %g" f)
          | `Intlit v -> if !bad = None then bad := Some (Printf.sprintf "Intlit %s" v)
          | `Assoc fields -> List.iter (fun (_, v) -> walk v) fields
          | `List l -> List.iter walk l
          | _ -> ()
        in
        walk j ;
        (match !bad with
        | Some what_bad -> Error (Printf.sprintf "%s contains a %s: machine output must be int/bool/string/null/array/object only" what what_bad)
        | None -> Ok j)
    | _ -> Error (Printf.sprintf "%s is not a single JSON OBJECT:\n%s" what s)

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
  (* The preamble every OCaml source fixture needs. A constant because three
     files carried their own copy, and a lang-version bump applied to two of
     three is a difference between fixtures that nobody intended. *)
  let dune_project = ("dune-project", "(lang dune 3.0)\n")

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

  (* A database built from SQL alone, with no schema file behind it. Used where
     the SHAPE is the subject — a legacy index with no kind column, a table that
     is not an arch-index at all — and loading the real schema would supply the
     very columns the test is asserting are missing. *)
  let raw ~name sql =
    let db = temp_db name in
    Db.with_db_rw db (fun conn -> Db.exec conn sql) ;
    db

  (* A main-schema index: architecture-schema.sql, then the caller's seed rows. *)
  let main ~name ?seed () =
    let db = temp_db name in
    Db.with_db_rw db (fun conn ->
        Db.exec conn (read_file (schema ())) ;
        Option.iter (Db.exec conn) seed) ;
    db

  (* A project that is also a git repository, because the tool under test reads
     a diff. Identity is set locally rather than relying on the machine having a
     global one, which a CI runner does not. *)
  let git_project ~name ~files k =
    with_project ~name ~files @@ fun root ->
    let code, output =
      run_command ~cwd:root "sh"
        ["-c";
         "git init -q && git config user.email t@t && git config user.name t && git add -A && \
          git commit -qm init"]
    in
    if code <> 0 then Test.fail "git fixture %s failed to initialise:\n%s" name output ;
    k root

  (* Commit whatever is in the working tree of a git fixture. Tests that need a
     diff edit a file and then call this, so the diff under test is a real one
     produced by git rather than a string the test wrote itself. *)
  let git_commit ~cwd msg =
    let code, output =
      run_command ~cwd "sh" ["-c"; Printf.sprintf "git add -A && git commit -qm %s" (Filename.quote msg)]
    in
    if code <> 0 then Test.fail "git commit failed in %s:\n%s" cwd output

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

(* The name a producer actually emitted for a function, found by substring.

   Producers qualify differently — arch-callgraph-go writes `pkg.entry`, the CMT
   walker writes `Mod.entry`, and a generic instantiation may write neither — so
   a test that hard-codes one spelling breaks on the others while proving
   nothing about the property it meant to check. [unlike] separates two names
   where one contains the other (`entry` vs `newEntryNode`).

   Fails rather than returning an option: a test that cannot find its subject
   has learned nothing, and every assertion it would go on to make would pass
   vacuously against an empty name. *)
let discover db ~like ~unlike =
  Db.with_db db (fun conn ->
      let sql =
        match unlike with
        | Some u ->
            Printf.sprintf
              "SELECT name FROM functions WHERE name LIKE '%%%s%%' AND name NOT LIKE '%%%s%%' \
               LIMIT 1"
              like u
        | None -> Printf.sprintf "SELECT name FROM functions WHERE name LIKE '%%%s%%' LIMIT 1" like
      in
      match Db.string_opt conn sql with
      | Some n -> n
      | None -> Test.fail "the producer emitted no function matching %S" like)

(* The two claims every call-graph PRODUCER owes, asserted identically wherever
   one is exercised, so a backend that regresses fails on the property rather
   than on a per-language spelling.

   [kinds_valid] is the load-bearing one: a NULL or unrecognised kind reads as
   literal 'MUST' in Arch_db.kind_sql, so one untagged row forges a must-reach
   path. Asserted over the WHOLE table rather than a sample, because the failure
   is silent. *)
module Assert = struct
  let produced_functions b conn ~label =
    Batch.ge_int b ~msg:(label ^ ": the producer must emit functions")
      (Db.int conn "SELECT count(*) FROM functions") 1

  (* The ⊤ frontier of [root] is the function that MAKES the escaping edge, not
     the root the question was asked about. Both are strings in the same output,
     so the distinction has to be asserted in both directions: the edge's call
     site present, the root absent. Pinned once here because two files needed
     it and the first spelling — `contains "t"` — was satisfied by any output
     containing a lowercase t, including one naming the root as the frontier. *)
  let escapes_frontier b ~out ~root ~call_site =
    Batch.contains b
      ~msg:(Printf.sprintf "escapes %s must report the ⊤ edge at %s" root call_site)
      ~haystack:out call_site ;
    Batch.not_contains b
      ~msg:
        (Printf.sprintf
           "escapes must name the function HOLDING the ⊤ edge, not the root %s it was asked \
            about"
           root)
      ~haystack:out root

  let kinds_valid b conn ~label =
    Batch.eq_int b
      ~msg:(label ^ ": no edge may carry a missing or invalid kind (a NULL kind reads as MUST)")
      (Db.int conn
         "SELECT count(*) FROM calls WHERE kind IS NULL OR kind NOT IN \
          ('MUST','MAY_ENUMERATED','MAY_TOP')")
      0
end

(* Non-empty lines of a tool's output: a row count should count rows, not the
   blank lines a formatter happens to emit. *)
let lines output =
  String.split_on_char '\n' output |> List.filter (fun l -> String.trim l <> "")

let has_prefix ~prefix s =
  String.length s >= String.length prefix && String.sub s 0 (String.length prefix) = prefix
