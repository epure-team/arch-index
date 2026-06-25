(******************************************************************************)
(*                                                                            *)
(* Copyright (c) 2026 Epure Team                                              *)
(* All rights reserved.                                                       *)
(*                                                                            *)
(******************************************************************************)

(** Parse @pre/@post/@violators/@violates/@tests/@quint tags from comment text.
    Handles both JSDoc (@tag) and OCaml ({tag}) syntax. *)

type present_or_none = Present of string | Present_none | Absent

type parsed_comment = {
  summary : string option;
  pre : present_or_none;
  post : present_or_none;
  violators : present_or_none;
  violates : present_or_none;
  tests : present_or_none;
  quint : present_or_none;
  score : int option;
}

type violator_entry = {name : string; reason : string}

(** [parse raw_comment] parses a raw doc comment string (stripped of
    delimiters). Returns a [parsed_comment] with scoring. *)
val parse : string -> parsed_comment

(** [score pc] computes the documentation quality score.
    Returns [None] if the comment has no sections at all.
    Scoring rubric:
    - summary: 15 pts
    - pre: 15 pts (Present only)
    - post: 20 pts (Present only)
    - violators: 20 pts (Present), 12 (Present_none)
    - violates: 20 pts (Present), 12 (Present_none)
    - tests: 5 pts
    - quint: 5 pts
    Total: 100 when all sections filled. *)
val score : parsed_comment -> int option

(** [parse_violators_json raw] parses a violators/violates text into JSON.
    E.g. "FooBar — reason text" → [{"name":"FooBar","reason":"reason text"}]
    "none" or "(none)" → None (Present_none). *)
val parse_violators_json : string -> string option
