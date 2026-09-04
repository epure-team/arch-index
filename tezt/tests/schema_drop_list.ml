(******************************************************************************)
(*                                                                            *)
(* Copyright (c) 2026 Epure Team                                              *)
(* All rights reserved.                                                       *)
(*                                                                            *)
(******************************************************************************)

(** [Arch_index_support.schema_tables_to_drop] is the list of tables
    [Arch_index.run] DROPs before recreating [architecture-schema.sql]. A
    producer-written table missing from it is not a cosmetic omission: the
    indexer only ever INSERTs, so re-indexing an existing database APPENDS a
    second copy of every row on top of the first — and because [functions.id]
    and [calls.id] are reused across runs, the surviving rows point at ids
    that no longer name what they were recorded for. Depending on the table
    that is either a duplicate-count bug or, for the exception/error-channel
    link tables, an UNSOUND one: a scope row closing a call site it never
    covered silently deletes a raise from an answer.

    The list has now silently gone stale THREE times running — [producer_runs]
    (roadmap 1.2), the seven exception/error-channel tables (error-channels
    review round 1), and [dead_code_sites] (round 2) — each time found by a
    reviewer or by a corrupted database two features later, never by a test.
    This test closes the class: it derives "the tables the producer writes"
    mechanically from the source and fails when one of them is neither in the
    drop list nor in an EXPLICIT, justified allowlist.

    Deriving rather than restating is the whole point. A hand-maintained
    second copy of the list would go stale in exactly the same way; scanning
    [lib/arch_index/*.ml] for [INSERT INTO <table>] cannot, because adding a
    new producer INSERT is what makes the test go red. *)

open Arch_tezt

(* Tables the producer writes but must NOT appear in [schema_tables_to_drop],
   each with the reason it manages its own lifecycle. An entry here is a
   claim that gets checked below (it must really be producer-written, and it
   must really be absent from the drop list), so the allowlist cannot rot
   into a silent skip of a table someone later added to the list anyway. *)
let self_managed =
  [
    ( "analysis_coverage",
      "coverage_matrix.ml issues its own `DELETE FROM analysis_coverage` \
       immediately before repopulating it, so it is already idempotent \
       across re-indexes" );
    ( "comment_db_meta",
      "holds state written by tools OTHER than the indexer, which dropping it \
       would destroy. NOT because INSERT OR REPLACE makes it self-managing: \
       that was the stated reason here, and it is exactly the reasoning that \
       hid a CRITICAL. INSERT OR REPLACE keeps a key CURRENT at the end of a \
       run that REACHES the write; it says nothing about a run that dies \
       first, which leaves the PREVIOUS run's value answering for work that \
       never happened. The keys where that distinction is load-bearing are \
       Arch_index_support.completion_marker_keys, and Arch_index.run deletes \
       them explicitly — twice, before the schema is demolished and after it \
       is rebuilt. Any new key whose PRESENCE means something must go in that \
       list; this table being un-dropped does not cover it" );
  ]

let read_file path =
  let ic = open_in_bin path in
  Fun.protect
    ~finally:(fun () -> close_in ic)
    (fun () -> really_input_string ic (in_channel_length ic))

let is_ident_char c =
  (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') || c = '_'

(* Every identifier in [s] that immediately follows an occurrence of [kw]. *)
let identifiers_after ~kw s =
  let klen = String.length kw and slen = String.length s in
  let acc = ref [] in
  let i = ref 0 in
  while !i + klen <= slen do
    if String.sub s !i klen = kw then begin
      let j = ref (!i + klen) in
      let start = !j in
      while !j < slen && is_ident_char s.[!j] do
        incr j
      done ;
      if !j > start then acc := String.sub s start (!j - start) :: !acc ;
      i := !j
    end
    else incr i
  done ;
  List.sort_uniq String.compare !acc

let register () =
  Test.register ~__FILE__
    ~title:
      "Arch_index_support.schema_tables_to_drop covers every producer-written table"
    ~tags:["indexer"; "schema"; "consistency"; "reindex"]
  @@ fun () ->
  let root = repo_root () in
  (* 1. The tables [architecture-schema.sql] actually declares. *)
  let schema_tables =
    identifiers_after ~kw:"CREATE TABLE IF NOT EXISTS "
      (read_file (Filename.concat root "architecture-schema.sql"))
  in
  (* 2. The tables the producer INSERTs into, over its whole source. Scanning
        for "INTO " and intersecting with (1) keeps the scanner trivial: the
        only SQL keyword followed by a table name here is INSERT [OR …] INTO,
        and anything that is not a declared table (inline-test scratch tables
        such as `t`, say) drops out at the intersection. *)
  let producer_dir = Filename.concat root "lib/arch_index" in
  let sources =
    Sys.readdir producer_dir |> Array.to_list
    |> List.filter (fun f -> Filename.check_suffix f ".ml")
    |> List.sort String.compare
  in
  let inserted =
    List.concat_map
      (fun f -> identifiers_after ~kw:"INTO " (read_file (Filename.concat producer_dir f)))
      sources
    |> List.sort_uniq String.compare
  in
  let producer_written = List.filter (fun t -> List.mem t schema_tables) inserted in
  let drop_list = Arch_index.Arch_index_support.schema_tables_to_drop in
  Batch.run (fun b ->
  (* Guard the derivation itself: if the scan silently stopped finding
     anything (a refactor moved the SQL, the file layout changed), every
     assertion below would pass vacuously. *)
  Batch.check b
    ~msg:
      (Printf.sprintf
         "the source scan must find the producer's writes at all (found %d tables across %d \
          files in %s)"
         (List.length producer_written) (List.length sources) producer_dir)
    (List.length producer_written >= 15) ;
  Batch.check b
    ~msg:
      (Printf.sprintf "architecture-schema.sql must declare tables (found %d)"
         (List.length schema_tables))
    (List.length schema_tables >= 20) ;
  (* THE RULE: producer-written ⊆ drop list ∪ self-managed. *)
  let missing =
    List.filter
      (fun t -> (not (List.mem t drop_list)) && not (List.mem_assoc t self_managed))
      producer_written
  in
  Batch.check b
    ~msg:
      (Printf.sprintf
         "every producer-written table must be in Arch_index_support.schema_tables_to_drop (or \
          justified in this test's [self_managed] allowlist); missing: [%s] — re-indexing an \
          existing database would append a second copy of each of these, with rows pointing at \
          reused function/call ids"
         (String.concat "; " missing))
    (missing = []) ;
  (* The allowlist is a claim, not an escape hatch: both halves are checked. *)
  List.iter
    (fun (t, why) ->
      Batch.check b
        ~msg:
          (Printf.sprintf
             "[self_managed] entry %S must actually be producer-written — if the producer no \
              longer writes it, delete the entry rather than leaving a stale waiver (reason on \
              record: %s)"
             t why)
        (List.mem t producer_written) ;
      Batch.check b
        ~msg:
          (Printf.sprintf
             "[self_managed] entry %S must NOT also be in schema_tables_to_drop — one of the two \
              is wrong, and a waiver that duplicates the list hides which"
             t)
        (not (List.mem t drop_list)))
    self_managed ;
  (* And the list must not name tables the schema does not have: a rename that
     updates the schema but not the list leaves a DROP that silently does
     nothing, which is the same failure with the arrow reversed. *)
  let unknown = List.filter (fun t -> not (List.mem t schema_tables)) drop_list in
  Batch.check b
    ~msg:
      (Printf.sprintf
         "schema_tables_to_drop must only name tables architecture-schema.sql declares; unknown: \
          [%s]"
         (String.concat "; " unknown))
    (unknown = [])) ;
  Lwt.return_unit
