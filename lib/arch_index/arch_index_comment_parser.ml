(******************************************************************************)
(*                                                                            *)
(* Copyright (c) 2026 Epure Team                                              *)
(* All rights reserved.                                                       *)
(*                                                                            *)
(******************************************************************************)

(** Structured doc-comment parser and quality scorer. *)

(* -------------------------------------------------------------------------- *)
(* Public types                                                               *)
(* -------------------------------------------------------------------------- *)

type section_body = Absent | Present of string | Present_none

type violator_entry = {qualified_name : string; reason : string}

(** A single {tests} link: a file path and a quoted test case name. *)
type test_entry = {
  file : string;  (** Relative path to the test file, e.g. "test/test_foo.ml" *)
  case_name : string;  (** Quoted test case name, e.g. "create and list" *)
}

type comment_sections = {
  summary : section_body;
  pre : section_body;
  post : section_body;
  violators : section_body;
  violators_entries : violator_entry list;
  violates : section_body;
  violates_entries : violator_entry list;
  inv : section_body;
  tests : section_body;
  tests_entries : test_entry list;
  quint : section_body;
      (** [{quint}] section body — raw Quint action fragment for this function.
          Parsed but not scored; stored as [quint_raw] in the arch DB. *)
  quint_module : section_body;
      (** [{quint-module}] section body — Quint module preamble (EXTENDS,
          VARIABLES, Init).  Present only in module-level doc comments;
          stored as [quint_module_raw] in the arch DB. *)
}

type parse_result = {
  sections : comment_sections;
  score : int;
  warnings : string list;
}

(* -------------------------------------------------------------------------- *)
(* Internal helpers                                                           *)
(* -------------------------------------------------------------------------- *)

(** Known section tag names. *)
let known_tags =
  [
    "pre";
    "post";
    "violators";
    "violates";
    "inv";
    "tests";
    "quint";
    "quint-module";
  ]

(** Find the position of needle in haystack starting at [start].
    Returns [-1] if not found. *)
let find_substring haystack needle start =
  let hlen = String.length haystack in
  let nlen = String.length needle in
  if nlen = 0 then start
  else
    let i = ref start in
    let found = ref (-1) in
    while !i <= hlen - nlen && !found = -1 do
      if String.sub haystack !i nlen = needle then found := !i else incr i
    done ;
    !found

(** em-dash UTF-8 bytes (U+2014): 0xE2 0x80 0x94. *)
let em_dash = "\xe2\x80\x94"

(** Split a string on the first occurrence of [em_dash].
    Returns [None] if the separator is absent. *)
let split_on_em_dash s =
  let pos = find_substring s em_dash 0 in
  if pos = -1 then None
  else
    let sep_len = String.length em_dash in
    let before = String.sub s 0 pos in
    let after =
      String.sub s (pos + sep_len) (String.length s - pos - sep_len)
    in
    Some (before, after)

(** Scan [s] for [{word}] patterns.
    Returns a list of [(tag_start, after_tag, tag_name)] sorted by position. *)
let find_tag_positions s =
  let len = String.length s in
  let positions = ref [] in
  let i = ref 0 in
  while !i < len do
    if s.[!i] = '{' then begin
      let j = ref (!i + 1) in
      (* Read identifier characters (no braces, no newlines) *)
      while !j < len && s.[!j] <> '}' && s.[!j] <> '{' && s.[!j] <> '\n' do
        incr j
      done ;
      if !j < len && s.[!j] = '}' && !j > !i + 1 then begin
        let tag = String.sub s (!i + 1) (!j - !i - 1) in
        positions := (!i, !j + 1, tag) :: !positions ;
        i := !j + 1
      end
      else incr i
    end
    else incr i
  done ;
  List.rev !positions

(** Convert a raw section body string to a [section_body].
    Empty or whitespace-only text → [Absent].
    Literal [(none)] → [Present_none].
    Anything else → [Present trimmed_text]. *)
let make_body s =
  let trimmed = String.trim s in
  if trimmed = "" then Absent
  else if trimmed = "(none)" then Present_none
  else Present trimmed

(** Parse a violators or violates section body text into entries.
    An entry starts with "name — reason" on one line.  Continuation lines
    (lines that do not contain an em-dash) are appended to the previous
    entry's reason, allowing multi-line reason text.
    Lines that are empty or "(none)" are skipped. *)
let parse_violator_entries body_text =
  (* Accumulate entries; carry the last entry to append continuations. *)
  let acc = ref [] in
  List.iter
    (fun line ->
      let line = String.trim line in
      if line = "" || line = "(none)" then ()
      else
        match split_on_em_dash line with
        | Some (name, reason) ->
            let name = String.trim name in
            let reason = String.trim reason in
            if name <> "" && name.[0] <> '(' then
              acc := {qualified_name = name; reason} :: !acc
        | None -> (
            (* Continuation: append to previous entry's reason *)
            match !acc with
            | prev :: rest ->
                acc :=
                  {prev with reason = String.concat " " [prev.reason; line]}
                  :: rest
            | [] -> () (* orphan continuation line — skip *)))
    (String.split_on_char '\n' body_text) ;
  List.rev !acc

(** Extract entries from a section body.  [Present_none] yields no entries. *)
let entries_of_body = function
  | Absent -> []
  | Present_none -> []
  | Present text -> parse_violator_entries text

(** Parse a {tests} section body into individual test link entries.
    Expected line format: [<file>: "<case name>"]
    Lines not matching this format are silently skipped. *)
let parse_test_entries body_text =
  let acc = ref [] in
  List.iter
    (fun line ->
      let line = String.trim line in
      if line = "" || line = "(none)" then ()
      else
        (* Find the colon separating file from case name *)
        match String.index_opt line ':' with
        | None -> ()
        | Some colon_pos ->
            let file = String.trim (String.sub line 0 colon_pos) in
            let rest =
              String.trim
                (String.sub
                   line
                   (colon_pos + 1)
                   (String.length line - colon_pos - 1))
            in
            (* Extract quoted case name: "..." *)
            if String.length rest >= 2 && rest.[0] = '"' then begin
              let closing = String.rindex_opt rest '"' in
              match closing with
              | Some ci when ci > 0 ->
                  let case_name = String.sub rest 1 (ci - 1) in
                  if file <> "" && case_name <> "" then
                    acc := {file; case_name} :: !acc
              | _ -> ()
            end)
    (String.split_on_char '\n' body_text) ;
  List.rev !acc

(** Extract test entries from a section body. *)
let test_entries_of_body = function
  | Absent -> []
  | Present_none -> []
  | Present text -> parse_test_entries text

(** [true] if a [section_body] counts as "present" for scoring purposes. *)
let section_present = function
  | Absent -> false
  | Present _ | Present_none -> true

(* -------------------------------------------------------------------------- *)
(* Main parse function                                                        *)
(* -------------------------------------------------------------------------- *)

let parse doc_string =
  let warnings = ref [] in
  let warn msg = warnings := msg :: !warnings in

  (* Find all {tag} positions *)
  let all_positions = find_tag_positions doc_string in

  (* Separate known from unknown tags *)
  let known_positions, unknown_positions =
    List.partition (fun (_, _, tag) -> List.mem tag known_tags) all_positions
  in

  (* Warn about unknown tags *)
  List.iter
    (fun (_, _, tag) -> warn (Printf.sprintf "Unknown tag: {%s}" tag))
    unknown_positions ;

  (* Build sections map: tag_name -> body_text
     Track duplicates and warn about them. *)
  let sections_map = Hashtbl.create 8 in
  let n_known = List.length known_positions in

  List.iteri
    (fun i (tag_start, after_tag, tag) ->
      (* Body ends at the next tag's opening brace, or end of string *)
      let body_end =
        if i + 1 < n_known then
          let next_start, _, _ = List.nth known_positions (i + 1) in
          next_start
        else String.length doc_string
      in
      let body = String.sub doc_string after_tag (body_end - after_tag) in
      if Hashtbl.mem sections_map tag then
        warn
          (Printf.sprintf
             "Duplicate section: {%s} — using first occurrence"
             tag)
      else Hashtbl.add sections_map tag body ;
      ignore tag_start)
    known_positions ;

  (* Extract summary: text before the first known tag *)
  let summary_text =
    match known_positions with
    | [] -> doc_string
    | (first_pos, _, _) :: _ -> String.sub doc_string 0 first_pos
  in

  let get_body tag =
    match Hashtbl.find_opt sections_map tag with
    | None -> Absent
    | Some text -> make_body text
  in

  let violators = get_body "violators" in
  let violates = get_body "violates" in
  let tests = get_body "tests" in

  let sections =
    {
      summary = make_body summary_text;
      pre = get_body "pre";
      post = get_body "post";
      violators;
      violators_entries = entries_of_body violators;
      violates;
      violates_entries = entries_of_body violates;
      inv = get_body "inv";
      tests;
      tests_entries = test_entries_of_body tests;
      quint = get_body "quint";
      quint_module = get_body "quint-module";
    }
  in

  (* Violation sections: Present_none (none) scores half (12/25).
     Only real named entries earn full credit — prevents gaming via (none). *)
  let score_violation_section = function
    | Present_none -> 12
    | Present _ -> 25
    | Absent -> 0
  in
  let score =
    (if section_present sections.summary then 15 else 0)
    + (if section_present sections.pre then 15 else 0)
    + (if section_present sections.post then 20 else 0)
    + score_violation_section sections.violators
    + score_violation_section sections.violates
  in

  {sections; score; warnings = List.rev !warnings}
