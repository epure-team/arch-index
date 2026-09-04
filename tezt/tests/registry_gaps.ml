(******************************************************************************)
(*                                                                            *)
(* Copyright (c) 2026 Epure Team                                              *)
(* All rights reserved.                                                       *)
(*                                                                            *)
(******************************************************************************)

(** [Arch_index.compute_registry_gaps], tested directly (round-6 review).

    Roadmap 1.6's R3 detector — [arch_index.ml]'s registry-gap warning — shipped
    with ZERO coverage. Nothing in the tree referenced [registry_gaps] or
    [registered_paths]; forcing [registry_gaps] to [[]] left the full 142-test
    suite green. A diagnostic that exists specifically to catch a silent
    completeness failure was itself unverified in exactly that way.

    It cannot be exercised through a real dune fixture: [arch_index.ml]'s own
    comment argues the registry is COMPLETE BY CONSTRUCTION with respect to the
    [modules] table (one [insert_module] call site, and the DB is dropped and
    recreated every run), so no ordinary project can produce a genuine gap. The
    seam this test needs is therefore fault injection at the function's own
    boundary: {!Arch_index.compute_registry_gaps} takes its inputs as plain
    values rather than reading {!Arch_index_cmt}'s global tables, so a
    synthetic "registry" that disagrees with a synthetic "stored modules" list
    can be handed to it directly, without indexing anything. *)

open Arch_tezt

let register () =
  Test.register ~__FILE__
    ~title:"registry-gaps: the R3 detector reports exactly the unregistered paths"
    ~tags:["unit"; "registry_gaps"]
  @@ fun () ->
  Batch.run (fun b ->
      let paths_of_unit table unit_name =
        Option.value ~default:[] (List.assoc_opt unit_name table)
      in
      (* THE FAULT: [orphan/mod.ml] is a stored module path, but no unit in the
         registry claims it — exactly the shape a future refactor that adds an
         [insert_module] call site without a matching [record_unit] call would
         produce. This is what the detector exists to catch. *)
      let gaps =
        Arch_index.compute_registry_gaps
          ~stored_module_paths:["liba/api.ml"; "orphan/mod.ml"]
          ~known_unit_names:["Liba__Api"]
          ~paths_of_unit:(paths_of_unit [("Liba__Api", ["liba/api.ml"])])
      in
      Batch.check b
        ~msg:
          (Printf.sprintf
             "an unregistered stored path must be reported as a gap, got [%s]"
             (String.concat "; " gaps))
        (gaps = ["orphan/mod.ml"]) ;
      (* NOT A GAP, MEDIUM-5's honesty-note extension: a unit name registered
         with TWO OR MORE paths (the (wrapped false) collision shape scenario C
         pins) still marks BOTH of its paths present in [registered_paths] —
         every element of [paths_of_unit unit_name] is registered regardless of
         how many there are. So this detector reports zero here even though the
         unit's own resolution is ambiguous; that is by design (a different
         failure mode, not this detector's job — see the resolver's own
         [ids_of_reading] and its "ambiguous" verdict), and pinning it here
         keeps the honesty note from silently going stale. *)
      let no_gap_multi_path =
        Arch_index.compute_registry_gaps ~stored_module_paths:["wa/api.ml"; "wb/api.ml"]
          ~known_unit_names:["Api"]
          ~paths_of_unit:(paths_of_unit [("Api", ["wa/api.ml"; "wb/api.ml"])])
      in
      Batch.check b
        ~msg:
          (Printf.sprintf
             "a unit registered with TWO paths must not be reported as a gap for either \
              path, got [%s]"
             (String.concat "; " no_gap_multi_path))
        (no_gap_multi_path = []) ;
      (* The all-clear case: every stored path is registered by some unit. *)
      let no_gap =
        Arch_index.compute_registry_gaps
          ~stored_module_paths:["liba/api.ml"; "libb/api.ml"]
          ~known_unit_names:["Liba__Api"; "Libb__Api"]
          ~paths_of_unit:
            (paths_of_unit
               [("Liba__Api", ["liba/api.ml"]); ("Libb__Api", ["libb/api.ml"])])
      in
      Batch.check b
        ~msg:
          (Printf.sprintf "no stored path should be flagged when every one is registered, got [%s]"
             (String.concat "; " no_gap))
        (no_gap = []) ;
      (* The empty-registry edge: nothing stored, nothing registered — no
         false positive from an empty list treated specially by [List.filter]. *)
      let empty =
        Arch_index.compute_registry_gaps ~stored_module_paths:[] ~known_unit_names:[]
          ~paths_of_unit:(paths_of_unit [])
      in
      Batch.check b ~msg:"an empty project reports no gaps" (empty = [])) ;
  Lwt.return_unit
