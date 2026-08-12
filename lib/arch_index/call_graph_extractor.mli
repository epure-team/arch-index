(******************************************************************************)
(*                                                                            *)
(* Copyright (c) 2026 Epure Team                                              *)
(* All rights reserved.                                                       *)
(*                                                                            *)
(******************************************************************************)

(** Call graph extraction using LSP callHierarchy. *)

type call_row = {
  caller_name : string;
  caller_file : string;
  callee_name : string;
  callee_file : string option;
  call_site : string;
}

(** [extract_calls client ~project_dir fn_rows] issues callHierarchy/prepare
    then callHierarchy/outgoingCalls for exported or documented functions.
    Returns call_rows. *)
(** [clock], when given, lets an empty first sweep be retried: a language
    server still loading its workspace reports no call hierarchy at all rather
    than an error. *)
val extract_calls :
  ?clock:_ Eio.Time.clock ->
  Lsp_client.t ->
  project_dir:string ->
  Lsp_extractor.fn_row list ->
  call_row list
