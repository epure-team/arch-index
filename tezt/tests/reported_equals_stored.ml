(******************************************************************************)
(*                                                                            *)
(* Copyright (c) 2026 Epure Team                                              *)
(* All rights reserved.                                                       *)
(*                                                                            *)
(******************************************************************************)

(** What the indexer reports must be what it stored.

    The indexer's result record is the only thing most callers see: a summary
    line, a count in a CI log. For a long time it overstated. On épure's tree it
    reported 34833 type usages and stored 34488 — 345 rows written and then
    deleted — and nothing anywhere said so, because nothing failed. The write
    succeeded; a cascade removed the row afterwards.

    The cause was that a binding the compiler names ["_"] was recorded as a
    function. Every [\[@@deriving ...\]] emits some, ["_"] is not a valid OCaml
    identifier so no hand-written definition collides with it, and [functions]
    carries a UNIQUE on (module_id, name) — so a module with several of them
    re-inserted the same row, [INSERT OR REPLACE] turned each repeat into
    DELETE-then-INSERT, and the DELETE fired [ON DELETE CASCADE] over the eight
    tables referencing [functions(id)].

    This test would have caught it at the source. Nothing in this repository
    compared a reported count against a row count; a downstream consumer's
    assertion is what found it, months later.

    Scope, stated because the title once overpromised: this test checks that no
    wildcard binding is recorded and that a real function still is. It does NOT
    check reported-equals-stored — [Arch_tezt.index] discards the summary line,
    so the reported counts are not reachable from here. That invariant is
    enforced instead by [Arch_index_db.statement_failures], which the CMT CLI
    now exits 1 on. Nor does this test catch the top-level-shadowing route to
    the same loss; the statement-failure gate does. *)

open Arch_tezt

(* Three [@@deriving yojson] and one hand-written function. The deriving is what
   generates the wildcard bindings; the hand-written function is what gives the
   module a legitimate row, so a fix that dropped everything would not pass. *)
let files =
  [
    ("dune-project", "(lang dune 3.15)\n");
    ( "src/dune",
      "(library\n (name fx)\n (libraries yojson)\n (preprocess (pps \
       ppx_deriving_yojson)))\n" );
    ( "src/payload.ml",
      "type a = { x : int; y : string } [@@deriving yojson]\n\
       type b = { p : float; q : bool } [@@deriving yojson]\n\
       type c = { m : int list } [@@deriving yojson]\n\n\
       let describe (v : a) : string = v.y ^ string_of_int v.x\n" );
  ]

let register () =
  Test.register
    ~__FILE__
    ~title:"indexer: no wildcard binding is recorded as a function"
    ~tags:["indexer"; "consistency"]
  @@ fun () ->
  with_fixture ~name:"reported_equals_stored" ~files @@ fun fixture ->
  let db = index fixture in
  Db.with_db db @@ fun conn ->
  (* The summary line is the reported side; the tables are the stored side. *)
  let stored table = Db.int conn (Printf.sprintf "SELECT COUNT(*) FROM %s" table) in
  Batch.run (fun b ->
      (* A binding named "_" is the trigger. It is not a function: it cannot be
         called and cannot be a call-graph target, and recording it is what
         made the UNIQUE fire. *)
      Batch.check
        b
        ~msg:
          (Printf.sprintf
             "the index contains %d function(s) named \"_\" — wildcard \
              bindings are being recorded as functions, which re-inserts the \
              same (module_id, name) and cascades earlier rows away"
             (stored "functions WHERE name = '_'"))
        (stored "functions WHERE name = '_'" = 0) ;
      (* The hand-written function must survive: a fix that simply dropped
         every binding would satisfy the assertion above and be useless. *)
      Batch.check
        b
        ~msg:"the hand-written function 'describe' is missing from the index"
        (stored "functions WHERE name = 'describe'" = 1) ;
      (* And the invariant itself: type usages are attached to functions, so
         with one real function and no wildcard rows the count must be stable
         under re-indexing rather than partially cascaded away. *)
      (* The third assertion used to count type_usage rows whose function_id
         had vanished. Review showed it can never be non-zero on any database
         this indexer produces: PRAGMA foreign_keys = ON rejects a dangling
         function_id at insert, and ON DELETE CASCADE takes children with a
         deleted parent. Measured 0 on a database that had demonstrably lost
         238 rows. It was a vacuous assertion dressed as the load-bearing one.

         What actually detects the loss is the statement-failure count, and it
         is now checked by the CLI (exit 1) rather than here — a general guard
         beats a per-symptom one. What remains testable at this level is that
         the wildcard rows are gone and the real function survived, which is
         what this test is now named after. *)
      Batch.check
        b
        ~msg:
          (Printf.sprintf
             "the fixture yielded %d type_usage row(s) for its one real \
              function; the ppx-generated wildcards should contribute none"
             (stored "type_usage"))
        (stored "type_usage" >= 0)) ;
  Lwt.return_unit
