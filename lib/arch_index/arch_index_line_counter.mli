(******************************************************************************)
(*                                                                            *)
(* Copyright (c) 2026 Epure Team                                              *)
(* All rights reserved.                                                       *)
(*                                                                            *)
(******************************************************************************)

(** Count non-comment, non-blank lines in an OCaml source file.

    {pre}
    The file path must point to a readable OCaml source file.

    {post}
    Returns the integer count of code lines (excluding comments and blank lines).

    {violators}
    (none)

    {violates}
    (none) *)
val run_count_code_lines : string -> int
