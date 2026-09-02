(******************************************************************************)
(*                                                                            *)
(* Copyright (c) 2026 Epure Team                                              *)
(* All rights reserved.                                                       *)
(*                                                                            *)
(******************************************************************************)

(** The curation ledgers end to end: loading coverage snapshots, reading them
    back, and writing to the gardening ledgers.

    Three properties carry the weight here. A malformed load writes NOTHING —
    not even the rows that preceded the bad line, because a half-applied
    snapshot is worse than no snapshot. Coverage is APPENDED, never replaced, so
    the ledger keeps its history and the read surface is responsible for showing
    only the latest. And gardening_log is append-only with mandatory
    provenance: an entry nobody signed is not an audit trail. *)

open Arch_tezt

let coverage_load ?(stdin = "") db = run_command ~stdin (arch_coverage_load ()) [db]
let curate db args = run_command (arch_curate ()) (db :: args)

let seed =
  {|
INSERT INTO modules(path, lines) VALUES ('lib/a.ml', 10), ('lib/b.ml', 10);
INSERT INTO functions(module_id, name, line_start, line_end) VALUES
  ((SELECT id FROM modules WHERE path='lib/a.ml'), 'f', 1, 5),
  ((SELECT id FROM modules WHERE path='lib/a.ml'), 'dup', 1, 2),
  ((SELECT id FROM modules WHERE path='lib/b.ml'), 'dup', 3, 4);
|}

let main_index () = Fixture.main ~name:"curation" ~seed ()
let flat_index () = Fixture.minimal_flat ~name:"curation_flat"

let count db sql = Db.with_db db (fun conn -> Db.int conn sql)

let register_load () =
  Test.register ~__FILE__ ~title:"curation: a load is all-or-nothing, and appends"
    ~tags:["curation"; "coverage"]
  @@ fun () ->
  let db = main_index () in
  Batch.run (fun b ->
      (* 'f' resolves; 'ghost' matches nothing; 'dup' is ambiguous across two
         modules and must be ignored rather than attributed to either. *)
      let _, out =
        coverage_load
          ~stdin:
            {|{"function":"f","covered_lines":3,"total_lines":10}
{"function":"ghost","covered_lines":1,"total_lines":1}
{"function":"dup","covered_lines":1,"total_lines":1}
|}
          db
      in
      Batch.contains b ~msg:"the loader must account for what it wrote and skipped" ~haystack:out
        "wrote 1, skipped 1" ;
      Batch.contains b ~msg:"an ambiguous name must be ignored, and said so" ~haystack:out
        "ignored 1" ;
      Batch.eq_int b ~msg:"exactly one coverage row after the happy path"
        (count db "SELECT count(*) FROM coverage") 1 ;

      (* All-or-nothing: the good line PRECEDES the malformed one, so a loader
         that wrote as it went would leave it behind. *)
      let before = count db "SELECT count(*) FROM coverage" in
      let outcome =
        coverage_load
          ~stdin:
            {|{"function":"f","covered_lines":1,"total_lines":10}
{"function":"f","covered_lines":9,"total_lines":10,"extra":1}
|}
          db
      in
      Batch.exit_code b ~msg:"arch-coverage-load: an unknown field must abort the load" ~expected:2 outcome ;
      Batch.eq_int b
        ~msg:"an aborted load must leave no row behind, not even ones before the bad line"
        (count db "SELECT count(*) FROM coverage")
        before ;

      let outcome =
        coverage_load ~stdin:{|{"function":"f","covered_lines":11,"total_lines":10}|} db
      in
      Batch.exit_code b ~msg:"covered_lines > total_lines must abort the load" ~expected:2
        outcome ;

      let outcome =
        coverage_load
          ~stdin:
            {|{"function":"f","covered_lines":1,"total_lines":10}
{"function":"f","covered_lines":2,"total_lines":10}
|}
          db
      in
      Batch.exit_code b
        ~msg:"the same function twice in one input must abort (one snapshot per row)" ~expected:2
        outcome ;

      (* Snapshots accumulate. The sleep is load-bearing: snapshot ordering is by
         a second-granularity timestamp, so a second write inside the same second
         would be indistinguishable from the first and the "latest" read below
         could legitimately return either. *)
      Unix.sleep 1 ;
      let _ = coverage_load ~stdin:{|{"function":"f","covered_lines":8,"total_lines":10}|} db in
      Batch.eq_int b ~msg:"a second load must append a snapshot for f, not replace the first"
        (count db
           "SELECT count(*) FROM coverage WHERE function_id=(SELECT id FROM functions WHERE \
            name='f')")
        2 ;

      (* The read surface is what collapses history to the latest row. *)
      let out = query db ["low-coverage"] in
      let rows = List.filter (has_prefix ~prefix:"lib/a.ml|f|") (lines out) in
      Batch.eq_int b ~msg:"low-coverage must show exactly one row for f (latest snapshot only)"
        (List.length rows) 1 ;
      Batch.contains b ~msg:"low-coverage must show f's latest snapshot (8/10), not an older one"
        ~haystack:out "lib/a.ml|f|80.0|8|10" ;

      (* A flat index simply has no coverage table. That is broken input for this
         tool, not an unsound-verdict situation: exit 2, not 3. *)
      let flat = flat_index () in
      let outcome =
        coverage_load ~stdin:{|{"function":"f","covered_lines":1,"total_lines":1}|} flat
      in
      Batch.exit_code b ~msg:"arch-coverage-load on a flat index must fail cleanly" ~expected:2
        outcome ;

      List.iter
        (fun args ->
          Batch.exit_code b
            ~msg:(Printf.sprintf "'%s' on a flat index must REFUSE" (String.concat " " args))
            ~expected:3 (query_raw flat args))
        [["low-coverage"]; ["gardening"; "open"]; ["gardening"; "log"]; ["unsafe-params"]]) ;
  Lwt.return_unit

let register_write () =
  Test.register ~__FILE__ ~title:"curation: provenance is mandatory and the log only grows"
    ~tags:["curation"; "curate"]
  @@ fun () ->
  let db = main_index () in
  Batch.run (fun b ->
      let ok ~msg args = Batch.exit_code b ~msg ~expected:0 (curate db args) in
      let refused ~msg args = Batch.exit_code b ~msg ~expected:2 (curate db args) in
      ok ~msg:"open-task must succeed on a fresh issue"
        ["open-task"; "--issue"; "900"; "--category"; "type-safety"; "--title"; "fix f.instance";
         "--function"; "f"] ;
      Batch.contains b ~msg:"gardening open must list the freshly-opened task"
        ~haystack:(query db ["gardening"; "open"]) "900|type-safety" ;
      refused ~msg:"open-task must refuse re-using an already-tracked github_issue"
        ["open-task"; "--issue"; "900"; "--category"; "x"; "--title"; "y"] ;
      refused ~msg:"open-task must refuse when BOTH --module and --function are given"
        ["open-task"; "--issue"; "901"; "--category"; "x"; "--title"; "y"; "--module"; "lib/a.ml";
         "--function"; "f"] ;

      ok ~msg:"add-unsafe-param must succeed for a fresh (function,param) pair"
        ["add-unsafe-param"; "--function"; "f"; "--param"; "instance"; "--current"; "string";
         "--target"; "Instance.t"; "--issue"; "900"] ;
      Batch.contains b ~msg:"unsafe-params must list the freshly-recorded param as unfixed"
        ~haystack:(query db ["unsafe-params"]) "instance|string|Instance.t|900|0" ;
      refused ~msg:"add-unsafe-param must refuse re-recording the same (function,param)"
        ["add-unsafe-param"; "--function"; "f"; "--param"; "instance"; "--current"; "string"] ;
      refused ~msg:"mark-fixed must refuse a param that was never recorded"
        ["mark-fixed"; "--function"; "f"; "--param"; "nope"] ;
      ok ~msg:"mark-fixed must succeed on a recorded param"
        ["mark-fixed"; "--function"; "f"; "--param"; "instance"] ;
      Batch.contains b ~msg:"unsafe-params fixed must list instance after mark-fixed"
        ~haystack:(query db ["unsafe-params"; "fixed"]) "instance" ;
      Batch.not_contains b ~msg:"unsafe-params unfixed must no longer list instance"
        ~haystack:(query db ["unsafe-params"; "unfixed"]) "instance" ;

      (* Provenance is a requirement, not a convention: an entry nobody signed
         and that points at no PR cannot be audited later. *)
      refused ~msg:"log without --contributor must be refused"
        ["log"; "--category"; "type-safety"; "--description"; "no contributor"; "--pr"; "1"] ;
      refused ~msg:"log without --pr must be refused"
        ["log"; "--contributor"; "alice"; "--category"; "type-safety"; "--description"; "no pr"] ;

      let before = count db "SELECT count(*) FROM gardening_log" in
      ok ~msg:"a fully-provenanced log entry must succeed"
        ["log"; "--contributor"; "alice"; "--category"; "type-safety"; "--description";
         "fixed f.instance"; "--pr"; "55"; "--issue"; "900"] ;
      Batch.eq_int b ~msg:"log must append exactly one row"
        (count db "SELECT count(*) FROM gardening_log")
        (before + 1) ;
      Batch.contains b ~msg:"gardening log must show the entry with its provenance"
        ~haystack:(query db ["gardening"; "log"]) "alice|type-safety|fixed f.instance|55|900" ;

      (* Append-only, checked against the DISPATCHER and not only against the
         usage text.

         The usage scan below is necessary but nowhere near sufficient: it only
         proves the tool does not ADVERTISE a destructive verb. A review added
         an undocumented `purge` case that ran `DELETE FROM gardening_log` and
         this test passed — the audit ledger could be wiped while the suite
         reported provenance intact. What actually holds the property is the row
         count: no invocation may reduce it. *)
      let _, usage = run_command (arch_curate ()) [] in
      (* Without this the four scans below are satisfied by an empty string. *)
      Batch.check b
        ~msg:"arch-curate with no arguments must print its usage (else the scans below are vacuous)"
        (String.length (String.trim usage) > 0) ;
      List.iter
        (fun verb ->
          Batch.not_contains b
            ~msg:
              (Printf.sprintf "arch-curate must not expose a %s- subcommand against gardening_log"
                 verb)
            ~haystack:usage (verb ^ "-"))
        ["edit"; "delete"; "remove"; "update"] ;
      (* And the dispatcher itself: a subcommand that exists without being
         documented is exactly the case the usage scan cannot see. *)
      let log_rows () = count db "SELECT count(*) FROM gardening_log" in
      let rows_before_probe = log_rows () in
      List.iter
        (fun verb ->
          let code, _ = curate db [verb] in
          Batch.check b
            ~msg:
              (Printf.sprintf
                 "arch-curate must not accept a '%s' subcommand — it exited 0, so the                   dispatcher has a verb the usage does not mention"
                 verb)
            (code <> 0) ;
          Batch.eq_int b
            ~msg:
              (Printf.sprintf
                 "gardening_log is append-only: '%s' must not remove rows from it" verb)
            (log_rows ()) rows_before_probe)
        ["purge"; "clear"; "reset"; "wipe"; "truncate"; "delete-log"; "edit-log";
         "remove-log"; "update-log"; "rm"] ;

      let after = count db "SELECT count(*) FROM gardening_log" in
      ok ~msg:"a second log entry must succeed"
        ["log"; "--contributor"; "bob"; "--category"; "coverage"; "--description";
         "raised coverage on f"; "--pr"; "56"] ;
      Batch.eq_int b ~msg:"a second log call must add a row, not replace the first"
        (count db "SELECT count(*) FROM gardening_log")
        (after + 1) ;
      let log = query db ["gardening"; "log"] in
      Batch.contains b ~msg:"the first entry must survive the second" ~haystack:log "alice" ;
      Batch.contains b ~msg:"the second entry must be present" ~haystack:log "bob" ;

      (* Feature-detect on an index with no ledger tables. *)
      let flat = flat_index () in
      List.iter
        (fun (msg, args) -> Batch.exit_code b ~msg ~expected:3 (curate flat args))
        [
          ( "arch-curate open-task on a flat index must REFUSE (no gardening_tasks table)",
            ["open-task"; "--issue"; "1"; "--category"; "x"; "--title"; "y"] );
          ( "arch-curate log on a flat index must REFUSE (no gardening_log table)",
            ["log"; "--contributor"; "alice"; "--category"; "x"; "--description"; "y"; "--pr"; "1"]
          );
        ]) ;
  Lwt.return_unit

let register_load_module_disambiguation () =
  Test.register ~__FILE__
    ~title:"curation: an optional module field disambiguates a same-named function (#35)"
    ~tags:["curation"; "coverage"; "disambiguation"]
  @@ fun () ->
  let db = main_index () in
  Batch.run (fun b ->
      (* 'dup' is ambiguous across lib/a.ml and lib/b.ml — same fixture as
         register_load's ignored-name case. Naming the module must resolve it
         to exactly that module's row instead of falling into "ignored". A
         durable fix (a stable qualified identity shared by every loader, not
         scoped resolution one loader at a time) is tracked as roadmap item
         1.6 — this is the minimal, per-loader fix for #35. *)
      let _, out =
        coverage_load
          ~stdin:{|{"function":"dup","module":"lib/a.ml","covered_lines":2,"total_lines":2}|}
          db
      in
      Batch.contains b ~msg:"a module-qualified name must resolve, not be ignored" ~haystack:out
        "wrote 1, skipped 0 (not in index), ignored 0" ;
      Batch.eq_int b ~msg:"exactly one coverage row after the module-qualified load"
        (count db "SELECT count(*) FROM coverage") 1 ;
      let dup_a_id =
        Db.with_db db (fun conn ->
            Db.int conn
              "SELECT f.id FROM functions f JOIN modules m ON f.module_id=m.id WHERE f.name='dup' \
               AND m.path='lib/a.ml'")
      in
      Batch.eq_int b
        ~msg:"the coverage row must be attributed to lib/a.ml's dup, not b.ml's or neither"
        (count db (Printf.sprintf "SELECT count(*) FROM coverage WHERE function_id=%d" dup_a_id))
        1 ;

      (* A module naming a function that does not exist there is SKIPPED (not
         in the index under that module), never guessed at from another
         module. *)
      let _, out =
        coverage_load
          ~stdin:{|{"function":"dup","module":"lib/c.ml","covered_lines":1,"total_lines":1}|}
          db
      in
      Batch.contains b ~msg:"a module that doesn't hold this function name must be skipped"
        ~haystack:out "wrote 0, skipped 1") ;
  Lwt.return_unit

let register_gardening_open_shows_in_progress () =
  Test.register ~__FILE__
    ~title:"curation: gardening open must not drop in_progress tasks (#34)"
    ~tags:["curation"; "gardening"]
  @@ fun () ->
  let db =
    Fixture.main ~name:"gardening-status"
      ~seed:
        {|
INSERT INTO gardening_tasks(github_issue, category, title, status) VALUES
  (100, 'split-file', 'still open', 'open'),
  (101, 'type-safety', 'being worked', 'in_progress'),
  (102, 'coverage', 'already done', 'done');
INSERT INTO gardening_tasks(github_issue, category, title, status) VALUES
  (103, 'type-safety', 'never set', NULL);
|}
      ()
  in
  Batch.run (fun b ->
      let out = query db ["gardening"; "open"] in
      Batch.contains b ~msg:"an 'open' task must appear" ~haystack:out "still open" ;
      Batch.contains b
        ~msg:
          "an 'in_progress' task must NOT vanish — it has left 'open' but has not yet reached \
           gardening_log, so dropping it here means it appears nowhere"
        ~haystack:out "being worked" ;
      Batch.not_contains b ~msg:"a 'done' task must not appear in the open view" ~haystack:out
        "already done" ;
      (* status is already in the header/select list — assert it is actually
         surfaced, not just present in the SQL. *)
      Batch.contains b ~msg:"the status column must be visible in the output" ~haystack:out
        "in_progress" ;
      (* status has a DEFAULT but no NOT NULL — a row with status left NULL
         (never set by any writer, but not forbidden by the schema) must read
         as the documented default rather than satisfying `<>'done'` as false
         and vanishing exactly like the bug this command already fixes once
         (round-1 review MEDIUM finding). *)
      Batch.contains b ~msg:"a NULL status must read as the default (open), not vanish"
        ~haystack:out "never set") ;
  Lwt.return_unit

let register_load_ambiguous_module_mix () =
  Test.register ~__FILE__
    ~title:"curation: a bare and a module-qualified record for one name are rejected together"
    ~tags:["curation"; "coverage"; "disambiguation"]
  @@ fun () ->
  let db = main_index () in
  Batch.run (fun b ->
      (* 'dup' bare and 'dup' scoped to lib/a.ml in the SAME input may name the
         same function — accepting both would let them resolve to one
         function_id and collide on the coverage table's own UNIQUE
         constraint in phase 2, with a diagnosis ("a snapshot already
         exists... run again in a moment") that can never be acted on, since
         the true cause is this input, not a prior run (round-1 review MEDIUM
         finding). Caught here, before either row is written. *)
      let before = count db "SELECT count(*) FROM coverage" in
      let outcome =
        coverage_load
          ~stdin:
            {|{"function":"dup","covered_lines":1,"total_lines":2}
{"function":"dup","module":"lib/a.ml","covered_lines":2,"total_lines":2}
|}
          db
      in
      Batch.exit_code b
        ~msg:"a bare record and a module-qualified record for one name must abort the load"
        ~expected:2 outcome ;
      let _, out = outcome in
      Batch.contains b ~msg:"the refusal must name the ambiguous function" ~haystack:out "dup" ;
      Batch.eq_int b ~msg:"an aborted ambiguous-mix load must leave no row behind"
        (count db "SELECT count(*) FROM coverage")
        before ;

      (* The order must not matter: scoped-then-bare is the same ambiguity as
         bare-then-scoped. *)
      let outcome =
        coverage_load
          ~stdin:
            {|{"function":"dup","module":"lib/b.ml","covered_lines":1,"total_lines":1}
{"function":"dup","covered_lines":1,"total_lines":2}
|}
          db
      in
      Batch.exit_code b ~msg:"scoped-then-bare must abort the load too, same as bare-then-scoped"
        ~expected:2 outcome ;

      (* Two DIFFERENT modules for the same name remain legitimate — that is
         the whole point of the "module" field — and must NOT be rejected as
         ambiguous. *)
      let outcome =
        coverage_load
          ~stdin:
            {|{"function":"dup","module":"lib/a.ml","covered_lines":2,"total_lines":2}
{"function":"dup","module":"lib/b.ml","covered_lines":1,"total_lines":1}
|}
          db
      in
      Batch.exit_code b ~msg:"two distinct scoped records for one name are not ambiguous"
        ~expected:0 outcome ;
      Batch.eq_int b ~msg:"both scoped records for distinct modules must be written"
        (count db "SELECT count(*) FROM coverage")
        (before + 2)) ;
  Lwt.return_unit
