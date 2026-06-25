(******************************************************************************)
(*                                                                            *)
(* Copyright (c) 2026 Epure Team                                              *)
(* All rights reserved.                                                       *)
(*                                                                            *)
(******************************************************************************)

(** Cross-commit OCaml function body extraction and move verification.

    Pure functions — no subprocesses.  Callers supply source text and diff
    text (obtained e.g. via [git show] and [git diff]). *)

(** Extract the body of [fn_name] from an OCaml [source] string.

    Finds [let [rec] fn_name] at column 0 and collects lines until the next
    top-level definition.  Returns [None] when not found.

    The result is normalised (per-line whitespace stripped, blank lines
    removed) for reliable comparison across different formatting.

    {pre}
    (none)

    {post}
    Returns [Some body] with the normalized function body text, or [None] if the function is not found.

    {violators}
    (none)

    {violates}
    (none) *)
val extract_fn_body : string -> string -> string option

(** A function whose definition was removed from one file and added to another
    within a single unified diff. *)
type move = {fn_name : string; from_file : string; to_file : string}

(** Parse a unified diff and return every function that was removed from one
    [.ml] or [.mli] file and added to a different one.

    Only top-level [let]/[let rec] bindings at column 0 are considered.
    The result is sorted by [fn_name] and deduplicated.

    {pre}
    (none)

    {post}
    Returns a sorted, deduplicated list of [move] records describing functions relocated between files.

    {violators}
    (none)

    {violates}
    (none) *)
val parse_diff_moves : string -> move list
