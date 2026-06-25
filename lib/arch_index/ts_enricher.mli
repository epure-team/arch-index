(******************************************************************************)
(*                                                                            *)
(* Copyright (c) 2026 Epure Team                                              *)
(* All rights reserved.                                                       *)
(*                                                                            *)
(******************************************************************************)

(** TypeScript enrichment (falls back gracefully if Node unavailable). *)

(** [is_available ()] returns true if [node] is on PATH.
    Uses PATH walking — no subprocess is spawned. *)
val is_available : unit -> bool

(** [enrich ~project_dir ~db_path] attempts TypeScript enrichment.
    Returns [Ok ()] on success or graceful skip (Node unavailable or
    ts-morph shim not yet embedded).  Never returns [Error] for a
    missing runtime. *)
val enrich :
  sw:Eio.Switch.t ->
  env:Eio_unix.Stdenv.base ->
  project_dir:string ->
  db_path:string ->
  (unit, string) result
