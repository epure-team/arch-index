(******************************************************************************)
(*                                                                            *)
(* Copyright (c) 2026 Epure Team                                              *)
(* All rights reserved.                                                       *)
(*                                                                            *)
(******************************************************************************)

(** Symbol extraction from LSP server. *)

(** A function row ready for DB insertion. *)
type fn_row = {
  name : string;
  file_path : string;  (** relative to project root *)
  line_start : int;
  line_end : int;
  exported : bool;
  signature : string option;
  summary : string option;
}

(** [extract_symbols client ~project_dir] uses workspace/symbol and
    textDocument/documentSymbol to enumerate functions/methods/constructors.
    Returns a list of fn_rows. *)
val extract_symbols : Lsp_client.t -> project_dir:string -> fn_row list
