(******************************************************************************)
(*                                                                            *)
(* Copyright (c) 2026 Epure Team                                              *)
(* All rights reserved.                                                       *)
(*                                                                            *)
(******************************************************************************)

(** Cross-commit OCaml function body extraction and move verification.

    Pure functions — no subprocesses.  Callers are responsible for obtaining
    source text (e.g. via [git show ref:path]) and diff text
    (e.g. via [git diff COMMIT^ COMMIT]). *)

(* -------------------------------------------------------------------------- *)
(* OCaml source extractor                                                     *)
(* -------------------------------------------------------------------------- *)

(** [starts_with s prefix] — true when [s] begins with [prefix]. *)
let starts_with s prefix =
  let n = String.length prefix in
  String.length s >= n && String.sub s 0 n = prefix

(** True when [line] is a top-level let-binding opening for [fn_name].

    Matches [let fn_name], [let rec fn_name] at column 0, followed by
    a space, [(], [=], or [:] (or end-of-line for zero-arg values). *)
let is_fn_start line fn_name =
  let after_opt =
    if starts_with line ("let rec " ^ fn_name) then
      Some (String.length ("let rec " ^ fn_name))
    else if starts_with line ("let " ^ fn_name) then
      Some (String.length ("let " ^ fn_name))
    else None
  in
  match after_opt with
  | None -> false
  | Some pos ->
      pos = String.length line
      ||
      let c = line.[pos] in
      c = ' ' || c = '(' || c = '=' || c = ':'

(** True when [line] starts a new top-level OCaml definition at column 0.
    Used to locate the end of the preceding function body. *)
let is_top_level_def line =
  starts_with line "let " || starts_with line "and " || starts_with line "type "
  || starts_with line "module " || starts_with line "open "
  || starts_with line "include "
  || starts_with line "exception "
  || starts_with line "(* ==" || starts_with line "(* --"
  || starts_with line "(**" || starts_with line "(***"

(** Normalise a list of source lines: strip per-line whitespace, drop blanks,
    rejoin.  Identical to the normalisation used by {!Arch_index_compare}. *)
let normalise lines =
  lines |> List.map String.trim
  |> List.filter (fun s -> s <> "")
  |> String.concat "\n"

(** Extract the body of [fn_name] from an OCaml [source] string.

    Searches for [let [rec] fn_name] at column 0 and collects subsequent
    lines until the next top-level definition or end of file.  Returns
    [None] when the function is not found in [source].

    The returned string is normalised (whitespace stripped, blank lines
    removed) so it can be compared across different indentation styles. *)
let extract_fn_body source fn_name =
  let lines = String.split_on_char '\n' source in
  let arr = Array.of_list lines in
  let n = Array.length arr in
  let start_idx = ref (-1) in
  Array.iteri
    (fun i line ->
      if !start_idx = -1 && is_fn_start line fn_name then start_idx := i)
    arr ;
  if !start_idx = -1 then None
  else begin
    let end_idx = ref n in
    for i = !start_idx + 1 to n - 1 do
      if !end_idx = n && is_top_level_def arr.(i) then end_idx := i
    done ;
    let body_lines =
      Array.to_list (Array.sub arr !start_idx (!end_idx - !start_idx))
    in
    Some (normalise body_lines)
  end

(* -------------------------------------------------------------------------- *)
(* Diff parser                                                                *)
(* -------------------------------------------------------------------------- *)

(** A function whose definition was removed from one file and added to another
    within a single unified diff. *)
type move = {fn_name : string; from_file : string; to_file : string}

(** Parse the first identifier token from [rest] (the text after [let ] or
    [let rec ] in a diff line).  Returns [None] for anonymous bindings
    ([()] or [_]). *)
let parse_fn_name rest =
  let rest =
    if starts_with rest "rec " then String.sub rest 4 (String.length rest - 4)
    else rest
  in
  let i = ref 0 in
  while
    !i < String.length rest
    && rest.[!i] <> ' '
    && rest.[!i] <> '('
    && rest.[!i] <> '='
    && rest.[!i] <> ':'
    && rest.[!i] <> '\r'
  do
    incr i
  done ;
  let name = String.sub rest 0 !i in
  if name = "" || name = "_" then None else Some name

(** Strip [prefix] from [s], returning [Some remainder] or [None]. *)
let strip_prefix s prefix =
  let n = String.length prefix in
  if String.length s >= n && String.sub s 0 n = prefix then
    Some (String.sub s n (String.length s - n))
  else None

(** Parse a unified diff (output of e.g. [git diff COMMIT^ COMMIT -- '*.ml'])
    and return every function that was removed from one [.ml]/[.mli] file and
    added to a different one.

    Only considers top-level [let] / [let rec] bindings at column 0 (i.e.
    diff lines starting with [-let ] or [+let ]). *)
let parse_diff_moves diff_text =
  let lines = String.split_on_char '\n' diff_text in
  let current_a = ref "" in
  let current_b = ref "" in
  let removed : (string, string list) Hashtbl.t = Hashtbl.create 16 in
  let added : (string, string list) Hashtbl.t = Hashtbl.create 16 in
  let add tbl fn file =
    let lst = Option.value ~default:[] (Hashtbl.find_opt tbl fn) in
    Hashtbl.replace tbl fn (file :: lst)
  in
  List.iter
    (fun line ->
      (match strip_prefix line "--- " with
      | Some path ->
          current_a := Option.value ~default:path (strip_prefix path "a/")
      | None -> ()) ;
      (match strip_prefix line "+++ " with
      | Some path ->
          current_b := Option.value ~default:path (strip_prefix path "b/")
      | None -> ()) ;
      (match strip_prefix line "-let " with
      | Some rest when !current_a <> "/dev/null" -> (
          match parse_fn_name rest with
          | Some fn -> add removed fn !current_a
          | None -> ())
      | _ -> ()) ;
      match strip_prefix line "+let " with
      | Some rest when !current_b <> "/dev/null" -> (
          match parse_fn_name rest with
          | Some fn -> add added fn !current_b
          | None -> ())
      | _ -> ())
    lines ;
  let moves = ref [] in
  Hashtbl.iter
    (fun fn from_files ->
      match Hashtbl.find_opt added fn with
      | None -> ()
      | Some to_files ->
          List.iter
            (fun from_file ->
              List.iter
                (fun to_file ->
                  if from_file <> to_file then
                    moves := {fn_name = fn; from_file; to_file} :: !moves)
                to_files)
            from_files)
    removed ;
  List.sort_uniq (fun a b -> String.compare a.fn_name b.fn_name) !moves
