(******************************************************************************)
(*                                                                            *)
(* Copyright (c) 2026 Epure Team                                              *)
(* All rights reserved.                                                       *)
(*                                                                            *)
(******************************************************************************)

(** Extract raw doc comment blocks from source files by line number. *)

(** [extract_comment ~file_path ~line_start] reads the source file and returns
    the raw text of the block comment immediately preceding [line_start].
    Returns [None] if no comment block found or file unreadable. *)
val extract_comment : file_path:string -> line_start:int -> string option
