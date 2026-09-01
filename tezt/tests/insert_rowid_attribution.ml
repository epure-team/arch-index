(******************************************************************************)
(*                                                                            *)
(* Copyright (c) 2026 Epure Team                                              *)
(* All rights reserved.                                                       *)
(*                                                                            *)
(******************************************************************************)

(** A rejected insert must not hand back another function's id.

    [Arch_index_db.exec_stmt] prints a diagnostic and CONTINUES when a row is
    refused, and [Sqlite3.last_insert_rowid] is per-CONNECTION and across all
    tables. So
    [exec_stmt db ~what:"functions" stmt_fn ; last_insert_rowid db] returned an
    id after a rejected insert too — the rowid the refused statement had
    already allocated, which the NEXT successful function insert then takes for
    itself, because a rolled-back statement does not advance the sequence.

    That is what makes the bug invisible. The indexer does not write type
    usages as it walks; it collects them with the [function_id] it was handed
    and flushes them after every module has been read
    ([all_pending_type_usages] in [lib/arch_index/arch_index.ml]). By flush
    time the stale id names a real, different function, so the foreign key on
    [type_usage.function_id] is satisfied: nothing is rejected, nothing is
    counted, and the rejected binding's rows land on an innocent neighbour. The
    per-table rejection tally cannot see it — the [type_usage] insert
    succeeded. Only the attribution is wrong.

    Measured on real runs: the self-index reports 475 rejected [functions]
    rows; an Octez index (10 033 modules, 353 290 functions, 1 437 224 calls)
    reports 9 629 rejected rows, all in [type_usage], with [type_usage]
    resolution at 18.1%.

    The test drives [Arch_index.Db] directly against a fixture with
    [PRAGMA foreign_keys = ON] and replays exactly that order: store a
    function, force the next [functions] insert to be rejected, store one more
    function (which inherits the rowid the rejected one was handed), then flush
    the pending usage under whatever id came back. The assertion is that no
    stored function ends up carrying the rejected binding's type usage. *)

open Arch_tezt

(* [Arch_index_db] is a [private_modules] member of the library (see
   [lib/arch_index/dune]), so [Arch_index.Arch_index_db] does not exist for an
   external consumer such as this test executable. [Arch_index.Db] is the
   narrow re-export; [insert_function] and [insert_type_usage] were added to it
   for this test, alongside the rejection-accounting names the sibling
   [rejection_attribution.ml] uses. *)
module Db_under_test = Arch_index.Db

(* The statements the indexer itself prepares, verbatim from
   [lib/arch_index/arch_index.ml]: the column order is what the [bind_*] calls
   inside [insert_function] and [insert_type_usage] are indexed against, so a
   test that invented its own ordering would be testing its own SQL. *)
let functions_sql =
  "INSERT OR REPLACE INTO functions (module_id, name, signature, line_start, \
   line_end, exposed, intent, comment_quality_score, has_pre, has_post, \
   has_violators, has_violates, violators_raw, violates_raw, tests_raw, \
   quint_raw, mutation_sites, deref_sites) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, \
   ?, ?, ?, ?, ?, ?, ?, ?, ?)"

let type_usage_sql =
  "INSERT INTO type_usage (function_id, type_id, type_name, usage_role, \
   position) VALUES (?, ?, ?, ?, ?)"

let prepare conn sql =
  try Sqlite3.prepare conn sql
  with Sqlite3.Error msg -> Test.fail "malformed fixture SQL (%s): %s" msg sql

let insert_fn conn stmt ~module_id ~name =
  Db_under_test.insert_function
    conn
    stmt
    ~module_id
    ~name
    ~signature:(Some "int -> int")
    ~line_start:1
    ~line_end:2
    ~exposed:false
    ~intent:None
    ()

let count conn sql =
  Db.rows conn sql |> Db.first_column ~sql |> function
  | None -> Test.fail "no row from: %s" sql
  | Some v -> Db.to_int ~sql v

let register () =
  Test.register
    ~__FILE__
    ~title:
      "Arch_index_db.insert_function: a rejected row yields no id, not a \
       neighbour's"
    ~tags:["indexer"; "consistency"; "rejections"; "rowid"]
  @@ fun () ->
  let db_path = Fixture.main ~name:"insert_rowid_attribution" () in
  Db_under_test.reset_rejections () ;
  Db_under_test.statement_failures := 0 ;
  (* What [insert_function] handed back for the rejected row, asserted after
     the database has been closed and re-read: the state of the stored rows is
     the primary evidence, and the returned value is what explains it. *)
  let returned = ref None in
  Db.with_db_rw db_path (fun conn ->
      Db.exec conn "PRAGMA foreign_keys = ON;" ;
      Db.exec
        conn
        "INSERT INTO modules (path, lines, last_analyzed, has_mli) VALUES \
         ('victim.ml', 10, '1970-01-01T00:00:00', 0)" ;
      let module_id =
        count conn "SELECT id FROM modules WHERE path='victim.ml'"
      in
      let stmt_fn = prepare conn functions_sql in
      let stmt_usage = prepare conn type_usage_sql in
      (* A real function, really stored: this is the row [last_insert_rowid]
         holds when the next statement is refused. *)
      (match insert_fn conn stmt_fn ~module_id ~name:"stored_before" with
      | Some _ -> ()
      | None -> Test.fail "the fixture's own function insert was rejected") ;
      (* The rejected binding. [module_id] 999999 references no module row, so
         the foreign key refuses it; every other column is well-formed, so the
         key is the only reason it is refused. *)
      let orphan = insert_fn conn stmt_fn ~module_id:999999 ~name:"orphan" in
      returned := orphan ;
      (* The next function stored takes the rowid the rejected statement was
         handed — a rolled-back insert does not advance the sequence. This is
         what turns a dangling id into a live, wrong one. *)
      (match insert_fn conn stmt_fn ~module_id ~name:"stored_after" with
      | Some _ -> ()
      | None -> Test.fail "the fixture's second function insert was rejected") ;
      (* The flush, as the indexer does it: the usages collected for a binding
         are written after the walk, under whatever id that binding was given.
         With the guard there is no id and nothing is written; without it, this
         row lands on [stored_after]. *)
      match orphan with
      | None -> ()
      | Some function_id ->
          Db_under_test.insert_type_usage
            conn
            stmt_usage
            ~function_id
            ~type_id:None
            ~type_name:"Orphan.t"
            ~usage_role:"param"
            ~position:(Some 0)) ;
  Db.with_db db_path (fun conn ->
      Batch.run (fun b ->
          (* The headline: the rejected binding's type usage must not have been
             filed under a function that is not it. *)
          Batch.eq_int
            b
            ~msg:
              "no stored function may carry the rejected binding's type \
               usage — it must be dropped, not re-attributed"
            (count
               conn
               "SELECT COUNT(*) FROM type_usage tu JOIN functions f ON f.id = \
                tu.function_id")
            0 ;
          (* Nor parked on a dangling id: a rejected function has no rows
             anywhere. *)
          Batch.eq_int
            b
            ~msg:"no type_usage row may survive a rejected functions insert"
            (count conn "SELECT COUNT(*) FROM type_usage")
            0 ;
          (* And the two legitimately stored functions are untouched: the
             guard drops the rejected row's dependents, not everyone's. *)
          Batch.eq_int
            b
            ~msg:"both stored functions must still be there"
            (count conn "SELECT COUNT(*) FROM functions")
            2 ;
          (* The cause, asserted after its effect: the id the rejected insert
             handed back. Kept in the same batch so a regression reports both
             the misattributed row and the id that caused it. *)
          Batch.check
            b
            ~msg:
              (Printf.sprintf
                 "a rejected functions insert must return None, got %s"
                 (match !returned with
                 | None -> "None"
                 | Some id -> Printf.sprintf "Some %d" id))
            (!returned = None) ;
          (* A guard that answered [None] for a row that WAS stored would
             satisfy the assertion above while silently dropping live data. The
             tally proves this [None] came from a real rejection, and from the
             [functions] table. *)
          Batch.check
            b
            ~msg:
              (Printf.sprintf
                 "expected exactly one rejected functions row, got %s"
                 (String.concat
                    "; "
                    (List.map
                       (fun (k, v) -> Printf.sprintf "(%S, %d)" k v)
                       (Db_under_test.rejections_by_table ()))))
            (Db_under_test.rejections_by_table () = [("functions", 1)]))) ;
  Lwt.return_unit
