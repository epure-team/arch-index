(******************************************************************************)
(*                                                                            *)
(* Copyright (c) 2026 Epure Team                                              *)
(* All rights reserved.                                                       *)
(*                                                                            *)
(******************************************************************************)

(** Consumers that SELECT a column added at schema 1.8 (or any later schema)
    without asking whether it exists. On an older index this is not "finds
    nothing" — Caqti/sqlite raise [no such column]/[no such table], which
    surfaced as an uncaught {!Arch_tools.Arch_db.Broken}: exit 2, no
    actionable diagnostic, indistinguishable from a locked or corrupt file.

    Two things are pinned here:

    - the two known crash sites ([raises] and [escaping-origins], both
      driven by [exn_scopes.channel]/[exn_origins.channel], an error-channels
      column added at schema 1.8) now REFUSE (exit 3) with a message naming what is missing,
      on a fixture that genuinely lacks the column and genuinely reaches
      the query — checked by PRAGMA before running the CLI at all, so this
      test cannot pass by accident on a fixture the guard never sees;
    - the BACKSTOP in {!Arch_tools.Arch_db.ok}: even a site with no
      per-command guard at all must convert the raw sqlite error into a
      {!Arch_tools.Arch_db.Refused} naming the missing column, not crash
      as {!Arch_tools.Arch_db.Broken}. Exercised directly against the
      library function, independent of any command-level guard, since the
      whole point of the backstop is to cover sites nobody has guarded
      yet. *)

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

let register () =
  register_raises_refuses_on_pre_channel_index () ;
  register_escaping_origins_refuses_on_pre_channel_index () ;
  register_ok_backstop_refuses_unguarded_missing_column ()
