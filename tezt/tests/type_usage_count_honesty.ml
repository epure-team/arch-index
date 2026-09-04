(******************************************************************************)
(*                                                                            *)
(* Copyright (c) 2026 Epure Team                                              *)
(* All rights reserved.                                                       *)
(*                                                                            *)
(******************************************************************************)

(** A reported row count must not include rows that were refused.

    [insert_type_usage] used to return [unit], and the flush loop in
    [lib/arch_index/arch_index.ml] did [insert_type_usage … ; incr
    n_type_usages] — so the increment happened whether or not the row reached
    the table. [exec_stmt] prints the rejection to stderr and returns normally,
    which means the over-count had no signal on any channel a caller reads:
    [run] returned [n_type_usages] as if it were the number of rows.

    That is not a cosmetic discrepancy, because [n_type_usages] is consumed as a
    row count. A downstream self-consistency check comparing it against a COUNT
    query over [type_usage] fails by exactly the number of refused inserts, and
    it fails with no way to tell an indexing bug from a counting bug — the
    measurement it is meant to trust is the thing that is wrong. It was found
    that way: épure's [test_indexer_accuracy] reported 37662 against 37659 rows,
    and the three missing rows were three refused foreign keys.

    [n_type_usages_resolved] had the same shape with an extra failure mode: it
    was incremented where the type name was resolved to an id, which is a
    different event from writing the row. A usage that resolved and was then
    refused inflated [resolved] but not [total], so it could also break the
    [resolved <= total] bound that a caller may assert.

    This test drives [Arch_index.Db] against a fixture with
    [PRAGMA foreign_keys = ON] and writes two usages: one against a real
    function, one against an id no function has. The assertions are that the
    verdicts differ, that exactly one row is stored, and that the rejection
    tally attributes the refusal to [type_usage] — the last one so a guard that
    answered [false] for a row it actually wrote could not pass. *)

open Arch_tezt

module Db_under_test = Arch_index.Db

(* Verbatim from [lib/arch_index/arch_index.ml]: the column order is what the
   [bind_*] calls inside [insert_type_usage] are indexed against, so inventing
   an ordering here would be testing this file's own SQL. *)
let functions_sql =
  "INSERT OR REPLACE INTO functions (module_id, name, signature, line_start, \
   line_end, exposed, intent, comment_quality_score, has_pre, has_post, \
   has_violators, has_violates, violators_raw, violates_raw, tests_raw, \
   quint_raw, mutation_sites, deref_sites, language, producer_run_id) VALUES \
   (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)"

let type_usage_sql =
  "INSERT INTO type_usage (function_id, type_id, type_name, usage_role, \
   position) VALUES (?, ?, ?, ?, ?)"

let prepare conn sql =
  try Sqlite3.prepare conn sql
  with Sqlite3.Error msg -> Test.fail "malformed fixture SQL (%s): %s" msg sql

let count conn sql =
  Db.rows conn sql |> Db.first_column ~sql |> function
  | None -> Test.fail "no row from: %s" sql
  | Some v -> Db.to_int ~sql v

let insert_usage conn stmt ~function_id ~type_name =
  Db_under_test.insert_type_usage
    conn
    stmt
    ~function_id
    ~type_id:None
    ~type_name
    ~usage_role:"param"
    ~position:(Some 0)

let register () =
  Test.register
    ~__FILE__
    ~title:
      "Arch_index_db.insert_type_usage: a refused row reports false, so it is \
       not counted"
    ~tags:["indexer"; "consistency"; "rejections"; "counts"]
  @@ fun () ->
  let db_path = Fixture.main ~name:"type_usage_count_honesty" () in
  Db_under_test.reset_all () ;
  (* Both verdicts are asserted after the database is closed and re-read: the
     stored rows are the primary evidence and the verdicts are what explain
     them. *)
  let stored = ref None and refused = ref None in
  Db.with_db_rw db_path (fun conn ->
      Db.exec conn "PRAGMA foreign_keys = ON;" ;
      Db.exec
        conn
        "INSERT INTO modules (path, lines, last_analyzed, has_mli) VALUES \
         ('counted.ml', 10, '1970-01-01T00:00:00', 0)" ;
      let module_id =
        count conn "SELECT id FROM modules WHERE path='counted.ml'"
      in
      let stmt_fn = prepare conn functions_sql in
      let stmt_usage = prepare conn type_usage_sql in
      (* A prepared statement left open holds the connection, [Sqlite3.db_close]
         then returns BUSY, and the closer in [tezt/lib/arch_tezt.ml] ignores
         that verdict — so the handle would leak and the assertions below would
         read through a second one. [Fun.protect] so this also happens on the
         [Test.fail] paths. *)
      Fun.protect
        ~finally:(fun () ->
          ignore (Sqlite3.finalize stmt_fn) ;
          ignore (Sqlite3.finalize stmt_usage))
      @@ fun () ->
      let function_id =
        match
          Db_under_test.insert_function
            conn
            stmt_fn
            ~module_id
            ~name:"host"
            ~signature:(Some "int -> int")
            ~line_start:1
            ~line_end:2
            ~exposed:false
            ~intent:None
            ()
        with
        | Some id -> id
        | None -> Test.fail "the fixture's own function insert was rejected"
      in
      (* The row that is written. *)
      stored := Some (insert_usage conn stmt_usage ~function_id ~type_name:"Ok.t") ;
      (* The row that is refused: [function_id] 999999 references no function,
         so the foreign key is the only reason it cannot be written — every
         other column is well-formed. *)
      refused :=
        Some
          (insert_usage
             conn
             stmt_usage
             ~function_id:999999
             ~type_name:"Dangling.t")) ;
  Db.with_db db_path (fun conn ->
      Batch.run (fun b ->
          (* The headline: exactly one row reached the table, so a caller that
             counted both verdicts would over-report by one. *)
          Batch.eq_int
            b
            ~msg:
              "exactly one type_usage row must be stored — the refused one is \
               not in the table, so it must not be counted either"
            (count conn "SELECT COUNT(*) FROM type_usage")
            1 ;
          Batch.check
            b
            ~msg:"a written type_usage row must report true"
            (!stored = Some true) ;
          Batch.check
            b
            ~msg:
              (Printf.sprintf
                 "a refused type_usage row must report false, got %s"
                 (match !refused with
                 | None -> "no verdict at all"
                 | Some v -> string_of_bool v))
            (!refused = Some false) ;
          (* A guard that answered [false] for a row it had actually written
             would satisfy the assertion above while silently under-counting
             live data. The tally proves this [false] came from a real
             rejection, and from the [type_usage] table. *)
          Batch.check
            b
            ~msg:
              (Printf.sprintf
                 "expected exactly one rejected type_usage row, got %s"
                 (String.concat
                    "; "
                    (List.map
                       (fun (k, v) -> Printf.sprintf "(%S, %d)" k v)
                       (Db_under_test.rejections_by_table ()))))
            (Db_under_test.rejections_by_table () = [("type_usage", 1)]))) ;
  Lwt.return_unit
