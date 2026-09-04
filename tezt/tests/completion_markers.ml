(******************************************************************************)
(*                                                                            *)
(* Copyright (c) 2026 Epure Team                                              *)
(* All rights reserved.                                                       *)
(*                                                                            *)
(******************************************************************************)

(** Completion markers — every [comment_db_meta] key whose PRESENCE claims that
    an analysis ran must be classified, and must not survive a re-index.

    The bug this closes was invisible for a reason worth restating: the
    [self_managed] allowlist in {!module:Schema_drop_list} justified leaving
    [comment_db_meta] un-dropped by "INSERT OR REPLACE, so a re-index
    overwrites each key". True for a run that REACHES the write. A producer
    killed mid-analysis never does, so the PREVIOUS run's marker stayed on disk
    and answered for work that never happened.

    [Schema_drop_list] proves that every producer-written TABLE is dropped or
    explicitly allowlisted. This is the same proof one level down, for the KEYS
    inside the one table that is deliberately not dropped — because that table
    being un-dropped is exactly what makes its keys able to outlive their
    evidence. A fourth marker added at a producer site and nowhere else would
    reintroduce the CRITICAL in silence; here, it fails. *)

open Arch_tezt

(* Keys a successful run writes whose presence carries NO completion claim.
   Each needs a reason, and the reason must be about the key's MEANING, not
   about how it is written — "INSERT OR REPLACE" is a statement about writes,
   and the failure this file exists for happens when there is no write at all. *)
let not_load_bearing =
  [
    ("schema_version", "describes the database's STRUCTURE, which is architecture-schema.sql \
                        regardless of how much got indexed into it; it is stamped \
                        unconditionally and means nothing about analysis completeness");
    ("error_config_digest", "describes the CONFIG, fully known before any analysis runs");
    ("error_config_source", "as error_config_digest — a provenance string for the config");
    ("error_config_unmatched", "as error_config_digest — a validation result about the config");
    ("error_summaries", "declared summaries copied from the config, not a record of work done");
  ]

let fixture_files =
  [
    Fixture.dune_project;
    ( "dune",
      "(library\n\
      \ (name cm_fixture)\n\
      \ (wrapped false)\n\
      \ (modules cm_a)\n\
      \ (flags (:standard -w -8-11-21-26-27-32-33-37-39)))\n" );
    ( "cm_a.ml",
      {|exception Boom
let raiser n = if n > 0 then raise Boom else n
let guarded n = try raiser n with Boom -> 0
|} );
  ]

let keys db =
  Db.with_db db (fun conn ->
      Db.string_opt conn "SELECT group_concat(key, ' ') FROM comment_db_meta")
  |> Option.value ~default:""
  |> String.split_on_char ' '
  |> List.filter (fun s -> s <> "")
  |> List.sort_uniq String.compare

let register_classified () =
  Test.register ~__FILE__
    ~title:"completion markers: every meta key a run writes is classified"
    ~tags:["cmt"; "meta"; "markers"; "consistency"]
  @@ fun () ->
  with_fixture ~name:"cm_classified" ~files:fixture_files @@ fun fixture ->
  let db = Arch_tezt.temp_db "cm_classified" in
  let code, output = Arch_tezt.index_raw_into ~db fixture in
  if code <> 0 then Test.fail "index failed (exit %d):\n%s" code output ;
  let written = keys db in
  let markers = Arch_index.Arch_index_support.completion_marker_keys in
  Batch.run (fun b ->
      (* Guard the derivation: if the run stopped writing meta altogether, every
         assertion below would pass vacuously — the same vacuum Schema_drop_list
         guards against with its own minimum. *)
      Batch.check b
        ~msg:
          (Printf.sprintf "a successful run must write meta keys at all (found %d: %s)"
             (List.length written) (String.concat ", " written))
        (List.length written >= 5) ;
      (* The three markers are earned by this fixture: it indexes a non-empty
         universe and declares error channels, so all three are written. If this
         stops holding, the re-index assertion below would pass for the wrong
         reason. *)
      List.iter
        (fun k ->
          Batch.check b
            ~msg:(Printf.sprintf "this fixture earns the marker %s" k)
            (List.mem k written))
        markers ;
      (* THE RULE: written ⊆ completion markers ∪ declared non-load-bearing. *)
      let unclassified =
        List.filter
          (fun k -> (not (List.mem k markers)) && not (List.mem_assoc k not_load_bearing))
          written
      in
      Batch.check b
        ~msg:
          (Printf.sprintf
             "every meta key must be a declared completion marker \
              (Arch_index_support.completion_marker_keys) or declared non-load-bearing in \
              this file. Unclassified: %s"
             (match unclassified with [] -> "(none)" | l -> String.concat ", " l))
        (unclassified = [])) ;
  Lwt.return_unit

let register_no_survival () =
  Test.register ~__FILE__
    ~title:"completion markers: none survives a re-index that indexes nothing"
    ~tags:["cmt"; "meta"; "markers"; "reindex"]
  @@ fun () ->
  with_fixture ~name:"cm_survival" ~files:fixture_files @@ fun fixture ->
  let db = Arch_tezt.temp_db "cm_survival" in
  let code1, out1 = Arch_tezt.index_raw_into ~db fixture in
  if code1 <> 0 then Test.fail "first index failed (exit %d):\n%s" code1 out1 ;
  let markers = Arch_index.Arch_index_support.completion_marker_keys in
  let present () = List.filter (fun k -> List.mem k (keys db)) markers in
  if List.length (present ()) <> List.length markers then
    Test.fail "run 1 did not write every marker; the test's premise is broken" ;
  (* A valid but EMPTY build directory. Run 2 gets past the drop/recreate step
     and indexes zero functions, so it re-earns nothing — whatever is present
     afterwards can only have come from run 1.

     [error_contract] is the reason this asserts on the marker LIST rather than
     on two hand-picked keys: it is rewritten unconditionally after the commit,
     so it IS present again here, legitimately. The assertion is therefore
     scoped to the keys that are gated on a non-empty universe, and the
     scoping is stated rather than left for a reader to infer from a passing
     test. *)
  let empty = Temp.dir "cm_survival_empty" in
  let code2, out2 = Arch_tezt.index_raw_into ~db {fixture with build_dir = empty} in
  Batch.run (fun b ->
      Batch.eq_int b ~msg:"re-index over an empty build dir exits 0" code2 0 ;
      if code2 <> 0 then Batch.note b "second index output:\n%s" out2 ;
      Batch.eq_int b ~msg:"run 2 indexed nothing"
        (Db.with_db db (fun conn -> Db.int conn "SELECT count(*) FROM functions"))
        0 ;
      let gated = List.filter (fun k -> k <> "error_contract") markers in
      List.iter
        (fun k ->
          Batch.check b
            ~msg:(Printf.sprintf "%s does not survive from the previous run" k)
            (not (List.mem k (keys db))))
        gated) ;
  Lwt.return_unit

let register () =
  register_classified () ;
  register_no_survival ()
