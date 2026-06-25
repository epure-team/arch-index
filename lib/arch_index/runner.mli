(******************************************************************************)
(*                                                                            *)
(* Copyright (c) 2026 Epure Team                                              *)
(* All rights reserved.                                                       *)
(*                                                                            *)
(******************************************************************************)

(** Main orchestrator for the LSP-based arch_index extraction pipeline. *)

(** [run ~sw ~env ~project_dir ~language ~output ?no_enrich ?verbose ()]
    orchestrates the full LSP extraction pipeline:
    1. Detect language if "auto"
    2. Lookup LSP server in Language_registry
    3. Start LSP client
    4. Extract symbols (Lsp_extractor)
    5. Extract call graph (Call_graph_extractor)
    6. Extract doc comments (Doc_extractor + Comment_parser)
    7. Optionally enrich (Ocaml_enricher or Ts_enricher)
    8. Write SQLite DB atomically (temp file + rename)

    Returns [Ok ()] or [Error msg].
    On timeout (configurable via EPURE_ARCH_INDEX_TIMEOUT_S, default 30s):
    returns partial results.
    On missing LSP binary: returns empty symbol set.
    On enricher failure: logs warning, continues with LSP-only data. *)
val run :
  sw:Eio.Switch.t ->
  env:Eio_unix.Stdenv.base ->
  project_dir:string ->
  language:string ->
  output:string ->
  ?no_enrich:bool ->
  ?verbose:bool ->
  unit ->
  (unit, string) result
