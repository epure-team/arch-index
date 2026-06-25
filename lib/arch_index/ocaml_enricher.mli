(******************************************************************************)
(*                                                                            *)
(* Copyright (c) 2026 Epure Team                                              *)
(* All rights reserved.                                                       *)
(*                                                                            *)
(******************************************************************************)

(** OCaml CMT-based enrichment. *)

(** [is_available ~project_dir] returns true if CMT files exist in
    _build/default/. *)
val is_available : project_dir:string -> bool

(** [enrich ~project_dir ~db_path] enriches [db_path] with OCaml CMT-derived
    data (modules, types, type_fields tables).
    Returns [Ok ()] if CMT files are absent (silently skips) or on success.
    Returns [Error msg] on failure. *)
val enrich : project_dir:string -> db_path:string -> (unit, string) result
