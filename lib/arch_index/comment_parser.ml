(******************************************************************************)
(*                                                                            *)
(* Copyright (c) 2026 Epure Team                                              *)
(* All rights reserved.                                                       *)
(*                                                                            *)
(******************************************************************************)

(** Parse @pre/@post/@violators/@violates/@tests/@quint tags from comment text.
    Distinct from arch_index_comment_parser.ml which uses {tag} OCaml syntax.
    This module handles both JSDoc (@tag) and OCaml ({tag}) syntax. *)

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

(** Known section tags (without delimiters). *)
let known_tags = ["pre"; "post"; "violators"; "violates"; "tests"; "quint"]

(** [make_body s] converts a raw body string to [present_or_none].
    "none"/"(none)" → [Present_none].  Use only for violators/violates. *)
let make_body s =
  let trimmed = String.trim s in
  if trimmed = "" then Absent
  else if
    trimmed = "(none)" || trimmed = "none" || trimmed = "None"
    || trimmed = "(None)"
  then Present_none
  else Present trimmed

(** [make_body_simple s] converts a raw body string to [present_or_none]
    without [Present_none] semantics — any non-empty text is [Present text].
    Use for pre/post/tests/quint where "none" is valid content. *)
let make_body_simple s =
  let trimmed = String.trim s in
  if trimmed = "" then Absent else Present trimmed

(** [find_jsdoc_tags s] finds all @tag positions in [s].
    Returns [(tag_start, body_start, tag_name)] sorted by position. *)
let find_jsdoc_tags s =
  let len = String.length s in
  let positions = ref [] in
  let i = ref 0 in
  while !i < len do
    if s.[!i] = '@' then begin
      let j = ref (!i + 1) in
      while !j < len && s.[!j] <> ' ' && s.[!j] <> '\n' && s.[!j] <> '\t' do
        incr j
      done ;
      if !j > !i + 1 then begin
        let tag = String.sub s (!i + 1) (!j - !i - 1) in
        if List.mem tag known_tags then positions := (!i, !j, tag) :: !positions
      end ;
      i := !j
    end
    else incr i
  done ;
  List.rev !positions

(** [find_ocaml_tags s] finds all {tag} positions in [s]. *)
let find_ocaml_tags s =
  let len = String.length s in
  let positions = ref [] in
  let i = ref 0 in
  while !i < len do
    if s.[!i] = '{' then begin
      let j = ref (!i + 1) in
      while !j < len && s.[!j] <> '}' && s.[!j] <> '{' && s.[!j] <> '\n' do
        incr j
      done ;
      if !j < len && s.[!j] = '}' && !j > !i + 1 then begin
        let tag = String.sub s (!i + 1) (!j - !i - 1) in
        if List.mem tag known_tags then
          positions := (!i, !j + 1, tag) :: !positions ;
        i := !j + 1
      end
      else incr i
    end
    else incr i
  done ;
  List.rev !positions

(** [parse_with_positions s positions] extracts sections from tag positions. *)
let parse_with_positions s positions =
  let n = List.length positions in
  let tbl = Hashtbl.create 8 in
  List.iteri
    (fun i (tag_start, body_start, tag) ->
      let body_end =
        if i + 1 < n then
          let next_start, _, _ = List.nth positions (i + 1) in
          next_start
        else String.length s
      in
      let body = String.sub s body_start (body_end - body_start) in
      if not (Hashtbl.mem tbl tag) then Hashtbl.add tbl tag body ;
      ignore tag_start)
    positions ;
  tbl

let score pc =
  if
    pc.summary = None && pc.pre = Absent && pc.post = Absent
    && pc.violators = Absent && pc.violates = Absent && pc.tests = Absent
    && pc.quint = Absent
  then None
  else begin
    let pts = ref 0 in
    (match pc.summary with Some _ -> pts := !pts + 15 | None -> ()) ;
    (match pc.pre with
    | Present _ -> pts := !pts + 15
    | Present_none | Absent -> ()) ;
    (match pc.post with
    | Present _ -> pts := !pts + 20
    | Present_none | Absent -> ()) ;
    (match pc.violators with
    | Present _ -> pts := !pts + 20
    | Present_none -> pts := !pts + 12
    | Absent -> ()) ;
    (match pc.violates with
    | Present _ -> pts := !pts + 20
    | Present_none -> pts := !pts + 12
    | Absent -> ()) ;
    (match pc.tests with
    | Present _ -> pts := !pts + 5
    | Present_none | Absent -> ()) ;
    (match pc.quint with
    | Present _ -> pts := !pts + 5
    | Present_none | Absent -> ()) ;
    Some !pts
  end

let parse raw_comment =
  if String.trim raw_comment = "" then
    {
      summary = None;
      pre = Absent;
      post = Absent;
      violators = Absent;
      violates = Absent;
      tests = Absent;
      quint = Absent;
      score = None;
    }
  else begin
    (* Try both syntaxes: prefer whichever has more matches *)
    let jsdoc_positions = find_jsdoc_tags raw_comment in
    let ocaml_positions = find_ocaml_tags raw_comment in
    let positions, first_tag_pos =
      if List.length ocaml_positions >= List.length jsdoc_positions then
        let first =
          match ocaml_positions with (pos, _, _) :: _ -> pos | [] -> -1
        in
        (ocaml_positions, first)
      else
        let first =
          match jsdoc_positions with (pos, _, _) :: _ -> pos | [] -> -1
        in
        (jsdoc_positions, first)
    in
    let tbl = parse_with_positions raw_comment positions in
    let get tag =
      match Hashtbl.find_opt tbl tag with
      | None -> Absent
      | Some text -> make_body_simple text
    in
    let get_none tag =
      match Hashtbl.find_opt tbl tag with
      | None -> Absent
      | Some text -> make_body text
    in
    let summary =
      let text =
        if first_tag_pos > 0 then
          String.trim (String.sub raw_comment 0 first_tag_pos)
        else if positions = [] then String.trim raw_comment
        else ""
      in
      if text = "" then None else Some text
    in
    let parsed =
      {
        summary;
        pre = get "pre";
        post = get "post";
        violators = get_none "violators";
        violates = get_none "violates";
        tests = get "tests";
        quint = get "quint";
        score = None;
      }
    in
    let s = score parsed in
    {parsed with score = s}
  end

(** em-dash UTF-8 bytes (U+2014): 0xE2 0x80 0x94. *)
let em_dash = "\xe2\x80\x94"

let find_substring haystack needle start =
  let hlen = String.length haystack in
  let nlen = String.length needle in
  if nlen = 0 then start
  else begin
    let i = ref start in
    let found = ref (-1) in
    while !i <= hlen - nlen && !found = -1 do
      if String.sub haystack !i nlen = needle then found := !i else incr i
    done ;
    !found
  end

let parse_violators_json raw =
  let trimmed = String.trim raw in
  if
    trimmed = "(none)" || trimmed = "none" || trimmed = "None"
    || trimmed = "(None)"
  then None
  else begin
    let entries = ref [] in
    List.iter
      (fun line ->
        let line = String.trim line in
        if line <> "" && line <> "(none)" then begin
          let pos = find_substring line em_dash 0 in
          if pos > 0 then begin
            let name = String.trim (String.sub line 0 pos) in
            let sep_len = String.length em_dash in
            let reason =
              String.trim
                (String.sub
                   line
                   (pos + sep_len)
                   (String.length line - pos - sep_len))
            in
            if name <> "" then
              entries :=
                `Assoc [("name", `String name); ("reason", `String reason)]
                :: !entries
          end
          else begin
            (* Try " - " separator *)
            match String.split_on_char '-' line with
            | name :: rest when String.trim name <> "" ->
                let reason = String.trim (String.concat "-" rest) in
                entries :=
                  `Assoc
                    [
                      ("name", `String (String.trim name));
                      ("reason", `String reason);
                    ]
                  :: !entries
            | _ -> ()
          end
        end)
      (String.split_on_char '\n' trimmed) ;
    match List.rev !entries with
    | [] -> None
    | lst -> Some (Yojson.Safe.to_string (`List lst))
  end
