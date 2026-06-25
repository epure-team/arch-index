(******************************************************************************)
(*                                                                            *)
(* Copyright (c) 2026 Epure Team                                              *)
(* All rights reserved.                                                       *)
(*                                                                            *)
(******************************************************************************)

(** Structured doc-comment parser and quality scorer.

    Parses OCaml doc-comment strings that follow the structured comment
    convention with sections [{pre}], [{post}], [{violators}], [{violates}],
    [{inv}], and [{tests}].  Returns typed section bodies, a 0-100 quality
    score, and a list of parse warnings. *)

(** Body of a single comment section.

    - [Absent]: the section tag was not present in the comment.
    - [Present s]: the section was present with non-empty, non-[(none)] body [s].
    - [Present_none]: the section was present and its body was the literal
      text [(none)], meaning the author explicitly declares the section
      inapplicable. *)
type section_body = Absent | Present of string | Present_none

(** A single entry in a [{violators}] or [{violates}] section.

    Each line of the section is parsed as [qualified_name — reason].
    If the em-dash separator is absent, [reason] is the empty string [""].  *)
type violator_entry = {qualified_name : string; reason : string}

(** A single entry in a [{tests}] section.

    Each line is parsed as [<file>: "<case name>"].
    Lines not matching that format are silently skipped. *)
type test_entry = {
  file : string;  (** Relative test file path, e.g. ["test/test_foo.ml"]. *)
  case_name : string;  (** Quoted test case name, e.g. ["create and list"]. *)
}

(** Typed representation of all recognised sections in a structured doc
    comment.  Sections [{inv}], [{tests}], [{quint}], and [{quint-module}] are
    parsed and stored but contribute 0 points to the quality score. *)
type comment_sections = {
  summary : section_body;
      (** Text before the first section tag.  Worth 15 points. *)
  pre : section_body;  (** [{pre}] precondition section.  Worth 15 points. *)
  post : section_body;  (** [{post}] postcondition section.  Worth 20 points. *)
  violators : section_body;
      (** [{violators}] section body (raw).  Worth 25 points. *)
  violators_entries : violator_entry list;
      (** Parsed entries from [{violators}]. Empty when [violators = Absent]
          or [Present_none]. *)
  violates : section_body;
      (** [{violates}] section body (raw).  Worth 25 points. *)
  violates_entries : violator_entry list;
      (** Parsed entries from [{violates}]. Empty when [violates = Absent]
          or [Present_none]. *)
  inv : section_body;
      (** [{inv}] invariant section.  Worth 0 points (parsed, not scored). *)
  tests : section_body;
      (** [{tests}] test-links section.  Worth 0 points (parsed, not scored). *)
  tests_entries : test_entry list;
      (** Parsed entries from [{tests}].  Empty when [tests = Absent] or
          [Present_none].  Each entry links this function to a named test case. *)
  quint : section_body;
      (** [{quint}] Quint action fragment section.  Worth 0 points (parsed,
          not scored).  The trimmed body is stored as [quint_raw] in the arch
          DB.  Only meaningful in function-level doc comments. *)
  quint_module : section_body;
      (** [{quint-module}] Quint module preamble section.  Worth 0 points
          (parsed, not scored).  The trimmed body is stored as
          [quint_module_raw] in the arch DB.  Only meaningful in module-level
          doc comments (top of [.mli] file). *)
}

(** Result of parsing a doc-comment string. *)
type parse_result = {
  sections : comment_sections;
  score : int;
      (** Quality score in [0..100] based on which scored sections are present. *)
  warnings : string list;
      (** Diagnostics for unrecognised tags, duplicate sections, etc.
          Never silently discarded: every anomaly produces an entry here. *)
}

(** Parse a doc-comment string and return the typed result.

    Scoring rubric (total 100 pts): summary=15, pre=15, post=20,
    violators=25, violates=25. The inv and tests sections contribute 0 pts.

    Error recovery: unrecognised tag names, unclosed braces, and
    duplicate sections are treated as [Absent] for scoring and added to
    [warnings]. The function never raises — all inputs including empty
    strings produce a valid [parse_result] with [score = 0] and empty
    [sections].

    {pre}
    Input may be any string, including the empty string.

    {post}
    Returns a [parse_result] with [score] in [0..100] and [warnings]
    listing every anomaly encountered. Never raises.

    {violators}
    (none)

    {violates}
    (none)
*)
val parse : string -> parse_result

(** [section_present body] returns [true] if [body] counts as present for
    scoring: [Absent] yields [false]; [Present _] and [Present_none] yield
    [true].

    {pre}
    (none)

    {post}
    Returns [false] for [Absent] and [true] for all other constructors.

    {violators}
    (none)

    {violates}
    (none)
*)
val section_present : section_body -> bool
