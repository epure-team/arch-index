(******************************************************************************)
(*                                                                            *)
(* Copyright (c) 2026 Epure Team                                              *)
(* All rights reserved.                                                       *)
(*                                                                            *)
(******************************************************************************)

(** {b A newer binary reading an older index.} That is the class — not, as this file and
    its PR first said, "the [channel] column that arrived at schema 1.8". A tool compiled
    today names columns and tables its query was written against; an index built by an
    older producer does not have all of them, and Caqti/sqlite answer
    [no such column]/[no such table]. This is not "finds nothing": it surfaced as an
    uncaught {!Arch_tools.Arch_db.Broken}, exit 2, with no actionable diagnostic and
    nothing to tell it apart from a locked or corrupt file.

    [exn_scopes.channel]/[exn_origins.channel] is where the class was FOUND, and five
    guarded sites is the right count {i for that column}. It is not the count for the
    class, and the class is not confined to 1.8: the first unguarded column the general
    backstop catches on the fixture below is [functions.exposed], read by
    [Arch_graph.load] and far older than the error-channels work. Any prose that scopes
    this measure to [channel] or to 1.8 is describing the symptom that led here.

    Three things are pinned:

    - the two scoped guards ([raises] and [escaping-origins], both driven by the
      [channel] column) REFUSE (exit 3) with a message naming what is missing, on a
      fixture that genuinely lacks the column and genuinely reaches the query — checked
      by PRAGMA before running the CLI at all, so this test cannot pass by accident on a
      fixture the guard never sees;
    - the BACKSTOP in {!Arch_tools.Arch_db.ok}: a site with no per-command guard at all
      must convert the raw sqlite error into a {!Arch_tools.Arch_db.Refused} naming the
      missing column {i or table} (both branches, separately), not crash as
      {!Arch_tools.Arch_db.Broken}. Exercised directly against the library function,
      independent of any command-level guard, since the whole point of the backstop is to
      cover sites nobody has guarded yet;
    - the DELIVERY of that message by the four binaries that map a refusal to exit 2
      ([arch-impact], [arch-rules], [arch-coverage], [arch-mutants]) — which for a
      query-time refusal used to be no delivery at all. *)

open Arch_tezt

(* A hand-built database, not the real schema: the SHAPE (a table missing a
   column added later) is the subject, and loading architecture-schema.sql
   would supply the very column this fixture needs to lack. Mirrors
   commit 2c1ba94's architecture-schema.sql (confirmed `grep -c channel` = 0
   there): [exn_scopes]/[exn_origins] with no [channel] column, one function
   pair, one MUST call edge, one exn_scopes row, one exn_origins row,
   `schema_version=1.7`, `callgraph_contract=v1`, `exn_contract=v1`. *)
let pre_channel_sql =
  {|
CREATE TABLE modules(id INTEGER PRIMARY KEY, path TEXT UNIQUE NOT NULL, lines INTEGER NOT NULL DEFAULT 0);
CREATE TABLE functions(id INTEGER PRIMARY KEY, module_id INTEGER NOT NULL, name TEXT NOT NULL,
                       line_start INTEGER, line_end INTEGER);
CREATE TABLE calls(id INTEGER PRIMARY KEY, caller_id INTEGER NOT NULL, callee_id INTEGER,
                   callee_name TEXT NOT NULL, call_site TEXT, kind TEXT);
CREATE TABLE comment_db_meta(key TEXT PRIMARY KEY, value TEXT);
CREATE TABLE exn_scopes(id INTEGER PRIMARY KEY, function_id INTEGER NOT NULL, parent_id INTEGER,
                        form TEXT NOT NULL, line INTEGER NOT NULL, col INTEGER NOT NULL,
                        catch_all BOOLEAN NOT NULL DEFAULT 0);
CREATE TABLE exn_origins(id INTEGER PRIMARY KEY, function_id INTEGER NOT NULL, scope_id INTEGER,
                         form TEXT NOT NULL, exn_path TEXT, escapes BOOLEAN NOT NULL DEFAULT 1,
                         line INTEGER NOT NULL, col INTEGER NOT NULL);
CREATE TABLE call_exn_scopes(call_id INTEGER PRIMARY KEY, scope_id INTEGER NOT NULL);

INSERT INTO modules VALUES (1,'src/a.ml',10);
INSERT INTO functions VALUES (1,1,'f',1,5),(2,1,'g',6,10);
INSERT INTO calls VALUES (1,2,1,'A.f','src/a.ml:7','MUST');
INSERT INTO exn_scopes VALUES (1,1,NULL,'try',2,2,0);
INSERT INTO exn_origins VALUES (1,1,1,'raise','Failure',1,3,4);
INSERT INTO comment_db_meta VALUES
  ('schema_version','1.7'),('callgraph_contract','v1'),('exn_contract','v1');
|}

(* Guard against the class this brief calls out by name: a fixture whose own
   filter hides the thing under test. Fail loudly, before running the CLI at
   all, if either column exists (the test would then prove nothing about a
   missing-column path) or the seed rows needed to REACH the query are
   missing. *)
let assert_fixture_lacks_channel db =
  Db.with_db db (fun conn ->
      let scope_cols = Db.strings conn "SELECT name FROM pragma_table_info('exn_scopes')" in
      let origin_cols = Db.strings conn "SELECT name FROM pragma_table_info('exn_origins')" in
      if List.mem "channel" scope_cols then
        Test.fail "fixture invariant violated: exn_scopes has a channel column after all: %s"
          (String.concat "," scope_cols) ;
      if List.mem "channel" origin_cols then
        Test.fail "fixture invariant violated: exn_origins has a channel column after all: %s"
          (String.concat "," origin_cols) ;
      let n_scopes = Db.int conn "SELECT count(*) FROM exn_scopes" in
      let n_origins = Db.int conn "SELECT count(*) FROM exn_origins" in
      if n_scopes <> 1 then Test.fail "fixture invariant violated: expected 1 exn_scopes row, got %d" n_scopes ;
      if n_origins <> 1 then Test.fail "fixture invariant violated: expected 1 exn_origins row, got %d" n_origins)

let register_raises_refuses_on_pre_channel_index () =
  Test.register ~__FILE__
    ~title:"arch-query raises: refuses (exit 3), does not crash, on an index predating exn_scopes.channel"
    ~tags:["arch_query"; "exn"; "channel"; "schema"; "regression"]
  @@ fun () ->
  let db = Fixture.raw ~name:"pre_channel_raises" pre_channel_sql in
  assert_fixture_lacks_channel db ;
  let code, output = query_raw db ["raises"; "A.f"] in
  Batch.run (fun b ->
      Batch.exit_code b ~msg:"raises on a pre-channel index must REFUSE, not crash" ~expected:3
        (code, output) ;
      (* Behavioural, not cosmetic: this is the SCOPED guard message
         ({!Arch_tools.Arch_exn.predates_channel_col}), distinct from both the generic
         "no exception sites" wording (reached when [exn_contract] itself is absent — a
         REAL never-analysed index, a different cause) and from the generic backstop's
         "this index predates column X" (reached only when no per-command guard exists at
         all). Deleting/weakening this guard falls through to the generic message, which
         does NOT contain this phrase — so unlike a leak-only check, this dies if the
         guard is removed. *)
      Batch.contains b ~msg:"must give the SCOPED predates-channel-column reason, not the \
                             generic \"no exception sites\" one"
        ~haystack:output "predate the error-channels column" ;
      Batch.not_contains b ~msg:"must not claim the producer emitted nothing (it did — only \
                                 the column is missing, MEDIUM-4)"
        ~haystack:output "its producer did not emit them" ;
      Batch.not_contains b ~msg:"must not surface the raw sqlite error" ~haystack:output
        "no such column" ;
      Batch.not_contains b ~msg:"must not raise an uncaught OCaml exception" ~haystack:output
        "Fatal error") ;
  (* The controls: `fan-in`/`callers-of` do not touch exn_scopes/exn_origins at
     all, so the fixture is not simply broken and they must keep answering. *)
  Batch.run (fun b ->
      let out = query db ["fan-in"] in
      Batch.contains b ~msg:"fan-in must still answer on this fixture" ~haystack:out "A.f" ;
      let out = query db ["callers-of"; "A.f"] in
      Batch.contains b ~msg:"callers-of must still answer on this fixture" ~haystack:out "g") ;
  Lwt.return_unit

let register_escaping_origins_refuses_on_pre_channel_index () =
  Test.register ~__FILE__
    ~title:"arch-query escaping-origins: refuses (exit 3), does not crash, on an index predating exn_origins.channel"
    ~tags:["arch_query"; "exn"; "channel"; "schema"; "regression"]
  @@ fun () ->
  let db = Fixture.raw ~name:"pre_channel_escaping_origins" pre_channel_sql in
  assert_fixture_lacks_channel db ;
  let code, output = query_raw db ["escaping-origins"; "--roots"; "src/a.ml:A.g"] in
  Batch.run (fun b ->
      Batch.exit_code b ~msg:"escaping-origins on a pre-channel index must REFUSE, not crash"
        ~expected:3 (code, output) ;
      Batch.contains b ~msg:"the refusal must name the channel column" ~haystack:output "channel" ;
      (* Behavioural, not cosmetic: "escaping-origins needs it" only appears in THIS
         command's own [has_col] guard message (bin/arch_query/arch_query.ml). If that
         guard is deleted, the query proceeds, hits the raw sqlite error, and gets
         reported instead by {!Arch_tools.Arch_db.ok}'s generic backstop — a real
         REFUSED at the same exit code, naming the same column, but without this phrase.
         A leak-only check (below) cannot tell the two apart since neither leaks the raw
         sqlite error; this one can. *)
      Batch.contains b ~msg:"must give the escaping-origins-SCOPED reason, not the generic \
                             backstop's"
        ~haystack:output "escaping-origins needs it" ;
      Batch.not_contains b ~msg:"must not surface the raw sqlite error" ~haystack:output
        "no such column" ;
      Batch.not_contains b ~msg:"must not raise an uncaught OCaml exception" ~haystack:output
        "Fatal error") ;
  Lwt.return_unit

(* The BACKSTOP: {!Arch_tools.Arch_db.ok} itself, called directly with no
   command-level guard in front of it at all — the case this measure exists
   for, since a guard-by-guard fix only ever covers sites someone has already
   found. A table lacking an arbitrary column (nothing to do with `channel`)
   proves the conversion is general, not special-cased to the two sites
   fixed above. *)
let register_ok_backstop_refuses_unguarded_missing_column () =
  Test.register ~__FILE__
    ~title:"Arch_db.ok: converts a raw 'no such column' error into Refused, naming the column, for ANY site with no guard"
    ~tags:["arch_db"; "channel"; "schema"; "regression"; "backstop"]
  @@ fun () ->
  let db =
    Fixture.raw ~name:"ok_backstop_missing_column"
      "CREATE TABLE functions(id INTEGER PRIMARY KEY, module_id INTEGER, name TEXT); \
       CREATE TABLE widgets(id INTEGER PRIMARY KEY, label TEXT);"
  in
  let t = Arch_tools.Arch_db.open_ro db in
  let query_widgets () =
    Arch_tools.Arch_db.rows t ~params_ty:Arch_tools.Arch_db.Ty.unit
      ~shape:Arch_tools.Arch_db.Rows.s
      ~to_cells:(fun a -> [Arch_tools.Arch_db.text_cell a])
      "SELECT nonexistent_col FROM widgets" ()
  in
  Batch.run (fun b ->
      match query_widgets () with
      | (_ : Arch_tools.Arch_db.cell list list) ->
          Batch.note b "expected Arch_db.Refused, got a successful result — the column exists?"
      | exception Arch_tools.Arch_db.Refused msg ->
          (* FIX (review HIGH-1/HIGH-2/HIGH-3): {!Arch_tools.Arch_db.ok} no longer appends
             the raw Caqti/sqlite message to the refusal (that leaked "no such column"
             regardless of what the extraction produced, which is exactly why the OLD
             version of this assertion survived a mutant that swapped the extracted name
             for a constant — the needle was in the haystack independent of the thing
             under test). [msg] here is now ONLY the constructed phrase, so this
             genuinely exercises [bare_name]/[token_after]'s extraction. *)
          Batch.contains b ~msg:"the Refused message must name the missing column"
            ~haystack:msg "nonexistent_col" ;
          Batch.contains b ~msg:"the Refused message must say the index predates it"
            ~haystack:msg "predates" ;
          Batch.not_contains b ~msg:"must not leak the raw sqlite error" ~haystack:msg
            "no such column" ;
          Batch.not_contains b ~msg:"must not carry a trailing sentence period from the \
                                     driver's message onto the extracted name"
            ~haystack:msg "nonexistent_col."
      | exception Arch_tools.Arch_db.Broken msg ->
          Batch.note b "a missing column must raise Refused (exit 3), not Broken (exit 2): %s" msg
      | exception e -> Batch.note b "unexpected exception: %s" (Printexc.to_string e)) ;
  Lwt.return_unit

(* The OTHER half of the backstop. {!Arch_tools.Arch_db.missing_schema_ref} has two
   branches — [no such column:] and [no such table:] — and until this test the second one
   had no coverage anywhere in tezt/ or test/ (a grep matched only its own doc comment).
   The two branches are not the same code path: a table name is extracted with a different
   prefix and, unlike a column, sqlite can qualify it with a SCHEMA rather than an alias,
   so [bare_name] is doing something different on each. A whole table arriving in a later
   schema is also the commoner drift than a column — [exn_scopes], [exn_origins] and
   [decisions] each arrived that way — so this is not a hypothetical branch. *)
let register_ok_backstop_refuses_unguarded_missing_table () =
  Test.register ~__FILE__
    ~title:"Arch_db.ok: converts a raw 'no such table' error into Refused, naming the table, for ANY site with no guard"
    ~tags:["arch_db"; "schema"; "regression"; "backstop"]
  @@ fun () ->
  let db =
    Fixture.raw ~name:"ok_backstop_missing_table"
      "CREATE TABLE functions(id INTEGER PRIMARY KEY, module_id INTEGER, name TEXT); \
       CREATE TABLE widgets(id INTEGER PRIMARY KEY, label TEXT);"
  in
  let t = Arch_tools.Arch_db.open_ro db in
  (* Assert the fixture actually lacks the table, before the CLI/library call — the same
     invariant guard the column tests above carry, for the same reason: a fixture that
     happens to HAVE the table would make this test pass by never reaching the branch. *)
  Db.with_db db (fun conn ->
      let n =
        Db.int conn "SELECT count(*) FROM sqlite_master WHERE name='gizmos'"
      in
      if n <> 0 then Test.fail "fixture invariant violated: table gizmos exists after all") ;
  let query_gizmos () =
    Arch_tools.Arch_db.rows t ~params_ty:Arch_tools.Arch_db.Ty.unit
      ~shape:Arch_tools.Arch_db.Rows.s
      ~to_cells:(fun a -> [Arch_tools.Arch_db.text_cell a])
      "SELECT label FROM gizmos" ()
  in
  Batch.run (fun b ->
      match query_gizmos () with
      | (_ : Arch_tools.Arch_db.cell list list) ->
          Batch.note b "expected Arch_db.Refused, got a successful result — the table exists?"
      | exception Arch_tools.Arch_db.Refused msg ->
          (* The EXTRACTED name, not a constant and not the raw driver text. The
             not_contains below is what stops "no such table: gizmos" from satisfying
             the contains above by accident — with the raw message suppressed, the only
             way "gizmos" can appear is if the table branch really extracted it. *)
          Batch.contains b ~msg:"the Refused message must name the missing TABLE"
            ~haystack:msg "table gizmos" ;
          Batch.contains b ~msg:"the Refused message must say the index predates it"
            ~haystack:msg "predates" ;
          Batch.not_contains b ~msg:"must not leak the raw sqlite error" ~haystack:msg
            "no such table" ;
          Batch.not_contains b ~msg:"must not carry a trailing sentence period from the \
                                     driver's message onto the extracted name"
            ~haystack:msg "gizmos."
      | exception Arch_tools.Arch_db.Broken msg ->
          Batch.note b "a missing table must raise Refused (exit 3), not Broken (exit 2): %s" msg
      | exception e -> Batch.note b "unexpected exception: %s" (Printexc.to_string e)) ;
  Lwt.return_unit

(* The backstop's message has to REACH a user, and in four binaries it did not.

   [arch-impact], [arch-rules], [arch-coverage] and [arch-mutants] each caught
   {!Arch_tools.Arch_db.Refused}/[Broken] around [Arch_db.open_ro] and nowhere else, so a
   refusal raised by any LATER query escaped the process and came out through OCaml's
   uncaught-exception path: [Fatal error: exception Arch_tools.Arch_db.Refused("…")]. The
   diagnostic was in there, wrapped in a crash dump, with no tool prefix.

   {b The exit code cannot be the assertion here.} It is 2 with the handler and 2 without
   it — deliberately, since exit 3 is a contract only [arch-query] and [arch-report] have
   signed (see the per-binary note in lib/arch_tools/arch_db.ml). A test that checked only
   the code would be green either way. What discriminates is the RENDERING: the handler
   prints "[tool]: [message]", the uncaught path prints "Fatal error: exception". Both are
   asserted, in both directions.

   Each tool is driven to a query that runs AFTER [open_ro] succeeds — all four reach
   [Arch_graph.load], which selects [functions.exposed], a column this fixture lacks. That
   is also the point about the class: the escaping column is [exposed], not [channel], and
   it is far older than schema 1.8. The backstop is not a channel measure; it covers any
   column a newer binary reads from an older index. *)
let register_query_time_refusal_is_rendered_not_dumped () =
  Test.register ~__FILE__
    ~title:"arch-impact/rules/coverage/mutants: a query-time Refused is rendered as a diagnostic, not dumped as an uncaught exception"
    ~tags:["arch_db"; "schema"; "regression"; "backstop"; "exit_codes"]
  @@ fun () ->
  let db = Fixture.raw ~name:"query_time_refusal" pre_channel_sql in
  (* The fixture must genuinely lack the column the escaping query reads — otherwise every
     tool below answers normally and the test passes by never reaching the handler. *)
  Db.with_db db (fun conn ->
      let cols = Db.strings conn "SELECT name FROM pragma_table_info('functions')" in
      if List.mem "exposed" cols then
        Test.fail "fixture invariant violated: functions.exposed exists, so no query escapes: %s"
          (String.concat "," cols)) ;
  let lcov = Temp.file "pre_channel.lcov" in
  write_file lcov "TN:\nSF:src/a.ml\nDA:1,1\nend_of_record\n" ;
  let rules = Temp.file "pre_channel_rules.txt" in
  write_file rules "rule \"no raise origins in g\"\n  forbid origin from fn:g form:raise allow-file:/dev/null\n" ;
  let cases =
    [ ("arch-impact", arch_impact (), [db; "--files"; "src/a.ml"]);
      ("arch-rules", arch_rules (), [db; rules]);
      ("arch-coverage", arch_coverage (), [db; lcov]);
      ("arch-mutants", arch_mutants (), ["plan"; db]) ]
  in
  Batch.run (fun b ->
      List.iter
        (fun (name, prog, args) ->
          let code, output = run_command prog args in
          Batch.exit_code b
            ~msg:(Printf.sprintf "%s: a schema-drift refusal aborts at 2 — exit 3 belongs to \
                                  arch-query/arch-report alone" name)
            ~expected:2 (code, output) ;
          Batch.not_contains b
            ~msg:(Printf.sprintf "%s: must not reach OCaml's uncaught-exception path" name)
            ~haystack:output "Fatal error" ;
          Batch.contains b
            ~msg:(Printf.sprintf "%s: the refusal must be printed as this tool's own diagnostic" name)
            ~haystack:output (name ^ ": this index predates column") ;
          Batch.not_contains b
            ~msg:(Printf.sprintf "%s: must not surface the raw sqlite error" name)
            ~haystack:output "no such column")
        cases) ;
  Lwt.return_unit

let register () =
  register_query_time_refusal_is_rendered_not_dumped () ;
  register_raises_refuses_on_pre_channel_index () ;
  register_escaping_origins_refuses_on_pre_channel_index () ;
  register_ok_backstop_refuses_unguarded_missing_column () ;
  register_ok_backstop_refuses_unguarded_missing_table ()
