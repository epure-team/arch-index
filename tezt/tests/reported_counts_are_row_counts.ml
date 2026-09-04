(******************************************************************************)
(*                                                                            *)
(* Copyright (c) 2026 Epure Team                                              *)
(* All rights reserved.                                                       *)
(*                                                                            *)
(******************************************************************************)

(** Every number the producer reports must equal the number of rows it wrote.

    [Arch_index.run] returns eleven counts, and its summary block prints them.
    Callers read them as row counts: épure's [test_indexer_accuracy] compares
    them directly against COUNT queries over the same tables. Six of them used
    to be kept by [incr] instead of measured — the producer counted the inserts
    it BELIEVED it had caused. [Arch_index_db.exec_stmt] writes a rejection to
    stderr and returns normally, so a refused row still advanced the tally, and
    the reported total came out ahead of the table with no per-counter signal
    anywhere. It was found downstream, by exactly that comparison: 37662
    reported against 37659 stored, three refused foreign keys.

    Two of them were worse than off-by-the-rejections. [n_calls_resolved] and
    [n_type_usages_resolved] were incremented where the callee/type name
    RESOLVED, which is a different event from writing the row: a row that
    resolved and was then refused inflated [resolved] without inflating the
    total, so [resolved <= total] — a bound a caller may reasonably assert —
    could be violated outright.

    {2 Why this test exists rather than a unit test on an insert helper}

    The defect lives in [run]'s flush loops, not in any insert function. A test
    that pins an insert helper's return value leaves those loops unguarded: the
    increment can be moved back outside the success branch, or restored to the
    original unconditional shape, and nothing in the suite falls. So this test
    drives the whole producer and compares its printed summary against the
    database it just wrote — the same comparison the downstream consumer makes,
    made here, where it can fail before shipping.

    {2 Why a trigger}

    A run with no rejections satisfies the invariant under BOTH the honest and
    the dishonest implementation, so a corpus that rejects nothing measures
    nothing. Neither real corpus rejects on demand: the arch-index self-index
    reports zero rejections, [modules] only refuses on its UNIQUE path, and
    [functions] is INSERT OR REPLACE. So, as in
    [tezt/tests/dropped_node_dependents.ml], the refusal is injected where the
    database decides it — the real [architecture-schema.sql] plus
    [BEFORE INSERT ... RAISE(ABORT)] triggers naming the rows to refuse.
    Everything upstream of the refusal is the production path, unmodified and
    unaware.

    The rejection tally is asserted to be non-empty before anything else, so
    this test cannot silently degrade into the vacuous version of itself if a
    future schema change stops the triggers from firing. *)

open Arch_tezt

(* [b.ml] owns the definitions, [cg.ml] uses them across a module boundary so
   the calls and type usages under test are the RESOLVED kind — a rejected row
   that resolved is what separates the two failure modes, and a fixture whose
   rows all resolve to nothing would only exercise the milder one.

   [cg.ml] also names things this corpus does NOT contain — [String.length] and
   [module Alias_absent = Buffer] — so that each of the three [resolved] counts
   is STRICTLY below its total. Without them the fixture stored 1 call of 1 and
   0 deps of 0, and on such a corpus "COUNT(*) WHERE <fk> IS NOT NULL" and
   "COUNT(*)" are the same number: dropping the WHERE clause from either
   resolved query left this test green. The gap is asserted below, not assumed,
   for the same reason the rejection tally is. *)
let fixture_files =
  [
    Fixture.dune_project;
    ("dune", "(library (name corpus) (modules b cg))\n");
    ( "b.ml",
      {|type refused_ty = {ra : int}
type kept_ty = {ka : int}

let refused_target (x : int) : int = x
let kept_target (x : int) : int = x
|} );
    ( "cg.ml",
      {|open B

module Alias_kept = B
module Alias_absent = Buffer

let uses_refused (v : B.refused_ty) : int = B.refused_target v.ra
let uses_kept (v : B.kept_ty) : int = B.kept_target v.ka
let uses_absent (s : string) : int = String.length s
let _ = ignore
|} );
  ]

(* One trigger per table this test claims to cover. [RAISE(ABORT)] is what a
   foreign-key violation looks like to [exec_stmt]: the step fails, the row is
   not written, the run continues. *)
let triggers =
  {|
CREATE TRIGGER reject_one_call BEFORE INSERT ON calls
  WHEN NEW.callee_name LIKE '%refused_target%'
  BEGIN SELECT RAISE(ABORT, 'refused by test trigger'); END;

CREATE TRIGGER reject_one_type_usage BEFORE INSERT ON type_usage
  WHEN NEW.type_name LIKE '%refused_ty%'
  BEGIN SELECT RAISE(ABORT, 'refused by test trigger'); END;

CREATE TRIGGER reject_one_dep BEFORE INSERT ON module_deps
  WHEN NEW.dep_kind = 'open'
  BEGIN SELECT RAISE(ABORT, 'refused by test trigger'); END;
|}

let schema_with_triggers ~name =
  let path = Temp.file (name ^ "-schema.sql") in
  write_file path (read_file (schema ()) ^ "\n" ^ triggers ^ "\n") ;
  path

(* The producer's summary block, verbatim from [Arch_index.run]:

     Done! Indexed:
       23 modules
       804 functions
       57 types (200 record fields, 76 variant constructors)
       5170 calls (1465 resolved)
       16 module deps (15 resolved)
       1565 type usages (33 resolved)

   Parsed rather than taken from [run]'s record because the printed line is the
   surface a human and a CI log actually read; a record that was right while
   the print was wrong would still be a lie in the only place anyone looks. *)
(* Only the block between "Done! Indexed:" and "Database:" is searched. The
   per-stage progress lines above it say the same words ("Inserted 0 module
   deps (0 resolved to known modules)" contains " modules"), and matching one
   of those would silently read a different number than the one under test. *)
let summary_block output =
  let lines = String.split_on_char '\n' output in
  let rec after = function
    | [] ->
        Test.fail
          "the producer printed no \"Done! Indexed:\" summary — either it \
           failed before the summary or the output format changed:\n\
           %s"
          output
    | l :: rest when contains ~needle:"Done! Indexed:" l -> rest
    | _ :: rest -> after rest
  in
  let rec until = function
    | [] -> []
    | l :: _ when contains ~needle:"Database:" l -> []
    | l :: rest -> l :: until rest
  in
  until (after lines)

let find_line ~block ~output ~needle =
  match List.filter (fun l -> contains ~needle l) block with
  | [l] -> l
  | [] ->
      Test.fail
        "no %S line in the producer's summary — the output format changed and \
         this test is no longer reading it:\n\
         %s"
        needle
        output
  | several ->
      (* Ambiguity is not resolved by picking one: the number this test then
         asserts on would be whichever line happened to come first. *)
      Test.fail
        "%S matches %d lines of the producer's summary, so it does not name \
         one count: %s"
        needle
        (List.length several)
        (String.concat " | " several)

(* The leading integers of a summary line, in order. "5170 calls (1465
   resolved)" yields [5170; 1465]. *)
let ints_of_line line =
  let buf = Buffer.create 8 in
  let out = ref [] in
  let flush () =
    if Buffer.length buf > 0 then (
      out := int_of_string (Buffer.contents buf) :: !out ;
      Buffer.clear buf)
  in
  String.iter
    (fun c -> if c >= '0' && c <= '9' then Buffer.add_char buf c else flush ())
    line ;
  flush () ;
  List.rev !out

let reported ~block ~output ~needle ~arity =
  let line = find_line ~block ~output ~needle in
  let ints = ints_of_line line in
  if List.length ints <> arity then
    Test.fail
      "expected %d number(s) on the %S line, got %d in %S"
      arity
      needle
      (List.length ints)
      line ;
  ints

let register () =
  Test.register
    ~__FILE__
    ~title:
      "indexer: every reported count equals the number of rows stored, even \
       when rows are refused"
    ~tags:["indexer"; "consistency"; "rejections"; "counts"]
  @@ fun () ->
  with_fixture ~name:"reported_counts_are_row_counts" ~files:fixture_files
  @@ fun fixture ->
  let schema_path = schema_with_triggers ~name:"reported_counts" in
  let db = temp_db fixture.name in
  let code, output =
    run_command
      (callgraph_ocaml ())
      [
        "--build-dir";
        fixture.build_dir;
        "--db-path";
        db;
        "--schema-path";
        schema_path;
      ]
  in
  (* The completeness gate exits 1 whenever a row was rejected. Asserted, not
     assumed: an exit 0 here would mean the triggers never fired and every
     assertion below would be comparing two zeros. *)
  if code <> 1 then
    Test.fail
      "expected exit 1 from the completeness gate (rows WERE refused), got \
       %d:\n\
       %s"
      code
      output ;
  let block = summary_block output in
  let n = function [x] -> x | _ -> assert false in
  let pair = function [a; b] -> (a, b) | _ -> assert false in
  let reported = reported ~block ~output in
  let r_modules = n (reported ~needle:" modules" ~arity:1) in
  let r_functions = n (reported ~needle:" functions" ~arity:1) in
  let r_types, r_fields, r_ctors =
    match reported ~needle:" types (" ~arity:3 with
    | [a; b; c] -> (a, b, c)
    | _ -> assert false
  in
  let r_calls, r_calls_resolved = pair (reported ~needle:" calls (" ~arity:2) in
  let r_deps, r_deps_resolved =
    pair (reported ~needle:" module deps (" ~arity:2)
  in
  let r_usages, r_usages_resolved =
    pair (reported ~needle:" type usages (" ~arity:2)
  in
  Db.with_db db @@ fun conn ->
  let stored sql = Db.int conn (Printf.sprintf "SELECT COUNT(*) FROM %s" sql) in
  Batch.run (fun b ->
      (* The control, first: this fixture must actually have rows refused, or
         reported-equals-stored holds trivially and proves nothing. Each of the
         three tables must have lost at least one row — a trigger that stopped
         matching would otherwise silently remove a third of the coverage. *)
      List.iter
        (fun (table, needle) ->
          Batch.check
            b
            ~msg:
              (Printf.sprintf
                 "the fixture must refuse at least one %s row, or this test \
                  cannot tell an honest counter from a dishonest one; \
                  producer output:\n\
                  %s"
                 table
                 output)
            (contains ~needle output))
        [
          ("calls", "calls: 1 row(s) rejected");
          ("type_usage", "type_usage: 1 row(s) rejected");
          ("module_deps", "module_deps: 1 row(s) rejected");
        ] ;
      (* The second control. Each [resolved] count must be STRICTLY below its
         total, or "rows whose foreign key resolved" and "rows" are the same
         number on this corpus and the equalities below stop distinguishing
         them: a producer that dropped the WHERE clause would agree with the
         table it names. Asserted against the STORED numbers, so it constrains
         the fixture rather than the producer — a fixture edit that removes the
         unresolvable call or the out-of-corpus alias fails here, loudly, and
         does not silently hollow out the assertions that follow. *)
      List.iter
        (fun (label, resolved_sql, total_sql) ->
          let resolved = stored resolved_sql and total = stored total_sql in
          Batch.check
            b
            ~msg:
              (Printf.sprintf
                 "the fixture must store at least one UNRESOLVED %s row, or \
                  the resolved query and the unfiltered query are the same \
                  number here and this test cannot tell them apart; stored %d \
                  resolved of %d total"
                 label
                 resolved
                 total)
            (resolved < total))
        [
          ("calls", "calls WHERE callee_id IS NOT NULL", "calls");
          ( "module_deps",
            "module_deps WHERE target_module IS NOT NULL",
            "module_deps" );
          ("type_usage", "type_usage WHERE type_id IS NOT NULL", "type_usage");
        ] ;
      (* The invariant. Every reported number against the table it names. *)
      List.iter
        (fun (label, reported, actual) ->
          Batch.eq_int
            b
            ~msg:
              (Printf.sprintf
                 "%s: the producer reported %d but stored %d — a reported \
                  count must be a row count, not a tally of attempted inserts"
                 label
                 reported
                 actual)
            reported
            actual)
        [
          ("modules", r_modules, stored "modules");
          ("functions", r_functions, stored "functions");
          ("types", r_types, stored "types");
          ("type_fields", r_fields, stored "type_fields");
          ("type_constructors", r_ctors, stored "type_constructors");
          ("calls", r_calls, stored "calls");
          ( "calls (resolved)",
            r_calls_resolved,
            stored "calls WHERE callee_id IS NOT NULL" );
          ("module_deps", r_deps, stored "module_deps");
          ( "module_deps (resolved)",
            r_deps_resolved,
            stored "module_deps WHERE target_module IS NOT NULL" );
          ("type_usage", r_usages, stored "type_usage");
          ( "type_usage (resolved)",
            r_usages_resolved,
            stored "type_usage WHERE type_id IS NOT NULL" );
        ] ;
      (* [resolved <= total] for all three pairs. Implied by the equalities
         above given that each resolved query filters the same table, but
         asserted in its own right because it is the bound a caller states,
         and because it is the one a resolution-time counter breaks first. *)
      List.iter
        (fun (label, resolved, total) ->
          Batch.check
            b
            ~msg:
              (Printf.sprintf
                 "%s: reported %d resolved out of %d total — resolved counts a \
                  subset of the rows and can never exceed the total"
                 label
                 resolved
                 total)
            (resolved <= total))
        [
          ("calls", r_calls_resolved, r_calls);
          ("module_deps", r_deps_resolved, r_deps);
          ("type_usage", r_usages_resolved, r_usages);
        ]) ;
  Lwt.return_unit
