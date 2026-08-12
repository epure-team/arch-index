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
      let code, _ =
        coverage_load
          ~stdin:
            {|{"function":"f","covered_lines":1,"total_lines":10}
{"function":"f","covered_lines":9,"total_lines":10,"extra":1}
|}
          db
      in
      Batch.eq_int b ~msg:"an unknown field must abort the load" code 2 ;
      Batch.eq_int b
        ~msg:"an aborted load must leave no row behind, not even ones before the bad line"
        (count db "SELECT count(*) FROM coverage")
        before ;

      let code, _ =
        coverage_load ~stdin:{|{"function":"f","covered_lines":11,"total_lines":10}|} db
      in
      Batch.eq_int b ~msg:"covered_lines > total_lines must abort the load" code 2 ;

      let code, _ =
        coverage_load
          ~stdin:
            {|{"function":"f","covered_lines":1,"total_lines":10}
{"function":"f","covered_lines":2,"total_lines":10}
|}
          db
      in
      Batch.eq_int b ~msg:"the same function twice in one input must abort (one snapshot per row)"
        code 2 ;

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
      let code, _ =
        coverage_load ~stdin:{|{"function":"f","covered_lines":1,"total_lines":1}|} flat
      in
      Batch.eq_int b ~msg:"arch-coverage-load on a flat index must fail cleanly" code 2 ;

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

      (* Append-only is enforced by there being no verb to do otherwise. *)
      let _, usage = run_command (arch_curate ()) [] in
      List.iter
        (fun verb ->
          Batch.not_contains b
            ~msg:
              (Printf.sprintf "arch-curate must not expose a %s- subcommand against gardening_log"
                 verb)
            ~haystack:usage (verb ^ "-"))
        ["edit"; "delete"; "remove"; "update"] ;

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
