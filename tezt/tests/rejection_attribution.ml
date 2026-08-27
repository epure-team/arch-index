(******************************************************************************)
(*                                                                            *)
(* Copyright (c) 2026 Epure Team                                              *)
(* All rights reserved.                                                       *)
(*                                                                            *)
(******************************************************************************)

(** [Arch_index_db.exec_stmt] tags every rejected row with the destination
    table it was headed for, via a REQUIRED [~what] argument, and
    [Arch_index_db.rejections_by_table] rolls that up into a per-table
    breakdown. Both are exercised only through whole-pipeline runs today
    (real [.cmt] files, a real build directory), which means a bug that
    mislabels or drops the per-table attribution — [incr_rejection what]
    silently becoming [incr_rejection "modules"], say — has no test that
    would catch it: the pipeline still runs, the scalar
    [n_statement_failures] still comes out right, and only the breakdown is
    wrong.

    This test drives [Arch_index.Db.exec_stmt] directly against a
    hand-built SQLite fixture with [PRAGMA foreign_keys = ON], forcing
    rejections in two different tables with two different counts, and
    checks that the breakdown attributes each rejection to the table it was
    actually destined for — not to some other table, not all lumped into
    one, and not silently dropped. *)

open Arch_tezt

(* [Arch_index_db] carries a [private_modules] marker in [lib/arch_index/dune]:
   it is compiled into the library but not part of its public interface, so
   [Arch_index.Arch_index_db] does not exist for an external consumer such as
   this test executable. [Arch_index.Db] is a minimal re-export added
   alongside this test (see [lib/arch_index/arch_index.ml]/[.mli]) that
   exposes exactly the four names this test needs: [exec_stmt],
   [statement_failures], [rejections_by_table], [reset_rejections]. *)
module Db_under_test = Arch_index.Db

(* [rejections_by_table] is backed by a single Hashtbl.t living at the
   [Arch_index_db] module level — process-global state, not per-test state.
   [main.ml] registers every test to run in one [Tezt.Test.run ()] call, and
   nothing else in this suite touches [Arch_index_db] in-process (every other
   test drives the pipeline out-of-process, through the built executables in
   tezt/tests/dune's [(deps ...)]), so nothing else can leave a stale count
   behind for this test to trip over, or vice versa. [reset_rejections] is
   still called at the start rather than relying on that being permanently
   true — a before/after diff would silently keep working if a future
   in-process user showed up moments before this test ran; a reset makes the
   fixture's baseline zero, and the assertions below are exact counts rather
   than deltas, which is the stronger and more direct check of the two. *)

let force_rejection conn ~table ~sql =
  let stmt =
    try Sqlite3.prepare conn sql
    with Sqlite3.Error msg -> Test.fail "malformed fixture SQL (%s): %s" msg sql
  in
  Db_under_test.exec_stmt conn ~what:table stmt ;
  ignore (Sqlite3.finalize stmt)

let register () =
  Test.register ~__FILE__
    ~title:"Arch_index_db.rejections_by_table: per-table attribution of rejected rows"
    ~tags:["indexer"; "consistency"; "rejections"]
  @@ fun () ->
  let db_path = Fixture.main ~name:"rejection_attribution" () in
  Db_under_test.reset_rejections () ;
  Db_under_test.statement_failures := 0 ;
  Db.with_db_rw db_path (fun conn ->
      Db.exec conn "PRAGMA foreign_keys = ON;" ;
      (* Two rejections destined for [type_usage]: no [functions] row with
         id 999999 exists, so the FK on [function_id] fails both times.
         [type_usage] is deliberately the table under test here rather than
         an arbitrary one: it is the table the Octez measurement in this
         commit's message found to own all 629 rejections, and the one
         issue #29 is about. Every other column is well-formed, so the FK
         is the only reason these rows are refused. *)
      force_rejection conn ~table:"type_usage"
        ~sql:
          "INSERT INTO type_usage(function_id, type_name, usage_role) VALUES \
           (999999, 'Ghost.t', 'param')" ;
      force_rejection conn ~table:"type_usage"
        ~sql:
          "INSERT INTO type_usage(function_id, type_name, usage_role) VALUES \
           (999999, 'Ghost.u', 'return')" ;
      (* Three rejections destined for [dead_code_sites] — a different table,
         a different count, so a mislabelling bug that swaps the two or folds
         them together cannot pass by coincidence. *)
      force_rejection conn ~table:"dead_code_sites"
        ~sql:
          "INSERT INTO dead_code_sites(function_id, call_site, callee_name) VALUES \
           (999999, 'nowhere.ml:3', 'ghost_a')" ;
      force_rejection conn ~table:"dead_code_sites"
        ~sql:
          "INSERT INTO dead_code_sites(function_id, call_site, callee_name) VALUES \
           (999999, 'nowhere.ml:4', 'ghost_b')" ;
      force_rejection conn ~table:"dead_code_sites"
        ~sql:
          "INSERT INTO dead_code_sites(function_id, call_site, callee_name) VALUES \
           (999999, 'nowhere.ml:5', 'ghost_c')") ;
  let counts = Db_under_test.rejections_by_table () in
  Batch.run (fun b ->
      Batch.check b
        ~msg:
          (Printf.sprintf
             "expected [(\"dead_code_sites\", 3); (\"type_usage\", 2)], got %s"
             (String.concat "; "
                (List.map (fun (k, v) -> Printf.sprintf "(%S, %d)" k v) counts)))
        (counts = [("dead_code_sites", 3); ("type_usage", 2)]) ;
      (* The breakdown must be complete, not partial: every rejected row is
         accounted for by SOME table, so the counts must sum to the scalar
         [statement_failures] reports for this run. *)
      let sum = List.fold_left (fun acc (_, n) -> acc + n) 0 counts in
      Batch.eq_int b ~msg:"breakdown total must equal statement_failures" sum
        !Db_under_test.statement_failures ;
      (* Sorted by table name — asserted independently of the literal above,
         so a future change to the fixture's table choices still exercises
         the ordering contract. *)
      let sorted = List.sort (fun (a, _) (b, _) -> String.compare a b) counts in
      Batch.check b
        ~msg:(Printf.sprintf "rejections_by_table must be sorted by table name, got %s"
                (String.concat "; " (List.map fst counts)))
        (counts = sorted)) ;
  Lwt.return_unit
