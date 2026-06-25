(******************************************************************************)
(*                                                                            *)
(* Copyright (c) 2026 Epure Team                                              *)
(* All rights reserved.                                                       *)
(*                                                                            *)
(******************************************************************************)

(** Extract raw doc comment blocks from source files by line number. *)

(** [read_lines file_path] reads all lines of a file into an array.
    Returns [None] on any error. *)
let read_lines file_path =
  try
    let ic = open_in file_path in
    Fun.protect
      ~finally:(fun () -> close_in ic)
      (fun () ->
        let lines = ref [] in
        (try
           while true do
             lines := input_line ic :: !lines
           done
         with End_of_file -> ()) ;
        Some (Array.of_list (List.rev !lines)))
  with _ -> None

(** [trim_comment_delimiters raw] strips common comment delimiters and leading
    whitespace/asterisks from a multi-line comment block. *)
let trim_comment_delimiters raw =
  (* Remove opening/closing delimiters *)
  let s = String.trim raw in
  (* Strip OCaml (** ...*) and (* ... *) *)
  let s =
    if String.length s >= 4 && String.sub s 0 3 = "(**" then
      String.sub s 3 (String.length s - 3)
    else if String.length s >= 2 && String.sub s 0 2 = "(*" then
      String.sub s 2 (String.length s - 2)
    else s
  in
  let s =
    let len = String.length s in
    if len >= 2 && String.sub s (len - 2) 2 = "*)" then String.sub s 0 (len - 2)
    else s
  in
  (* Strip TypeScript /** ... */ *)
  let s =
    if String.length s >= 3 && String.sub s 0 3 = "/**" then
      String.sub s 3 (String.length s - 3)
    else if String.length s >= 2 && String.sub s 0 2 = "/*" then
      String.sub s 2 (String.length s - 2)
    else s
  in
  let s =
    let len = String.length s in
    if len >= 2 && String.sub s (len - 2) 2 = "*/" then String.sub s 0 (len - 2)
    else s
  in
  (* Strip leading * from each line (JSDoc style) *)
  let lines = String.split_on_char '\n' s in
  let lines =
    List.map
      (fun line ->
        let t = String.trim line in
        if String.length t > 0 && t.[0] = '*' then
          String.trim (String.sub t 1 (String.length t - 1))
        else t)
      lines
  in
  String.trim (String.concat "\n" lines)

(** [find_ocaml_comment lines end_idx] scans backward from [end_idx - 1]
    looking for an OCaml doc-comment block. Returns the raw comment or None. *)
let find_ocaml_comment lines end_idx =
  (* Look backward from end_idx - 1, up to 20 lines *)
  let start_search = max 0 (end_idx - 1) in
  let limit = max 0 (end_idx - 20) in
  (* Scan backward to find the close marker *)
  let close_pos = ref (-1) in
  let i = ref start_search in
  while !i >= limit && !close_pos = -1 do
    let line = String.trim lines.(!i) in
    if
      String.length line >= 2
      && String.sub line (String.length line - 2) 2 = "*)"
    then close_pos := !i
    else if line = "" then ()
    else close_pos := -2 (* non-comment, non-blank line — stop *) ;
    decr i
  done ;
  if !close_pos < 0 then None
  else begin
    (* Scan backward to find the comment open marker *)
    let close = !close_pos in
    let open_pos = ref (-1) in
    let j = ref close in
    while !j >= limit && !open_pos = -1 do
      let line = lines.(!j) in
      (* Check if line contains an OCaml comment open marker *)
      let idx = ref 0 in
      let len = String.length line in
      while !idx < len - 1 && !open_pos = -1 do
        if line.[!idx] = '(' && line.[!idx + 1] = '*' then open_pos := !j ;
        incr idx
      done ;
      decr j
    done ;
    if !open_pos = -1 then None
    else begin
      let block_lines =
        Array.sub lines !open_pos (close - !open_pos + 1)
        |> Array.to_list |> String.concat "\n"
      in
      Some (trim_comment_delimiters block_lines)
    end
  end

(** [find_rust_comment lines end_idx] scans backward for /// line comments. *)
let find_rust_comment lines end_idx =
  let start_search = max 0 (end_idx - 1) in
  let limit = max 0 (end_idx - 20) in
  let comment_lines = ref [] in
  let i = ref start_search in
  while !i >= limit do
    let line = String.trim lines.(!i) in
    if String.length line >= 3 && String.sub line 0 3 = "///" then begin
      let text = String.trim (String.sub line 3 (String.length line - 3)) in
      comment_lines := text :: !comment_lines ;
      decr i
    end
    else if line = "" then decr i
    else i := -1 (* stop *)
  done ;
  match !comment_lines with
  | [] -> None
  | lines -> Some (String.concat "\n" lines)

let extract_comment ~file_path ~line_start =
  match read_lines file_path with
  | None -> None
  | Some lines ->
      if Array.length lines = 0 || line_start <= 0 then None
      else begin
        let end_idx = min (line_start - 1) (Array.length lines - 1) in
        (* Detect file type from extension *)
        let ext = Filename.extension file_path in
        match ext with
        | ".rs" -> find_rust_comment lines end_idx
        | ".ml" | ".mli" -> find_ocaml_comment lines end_idx
        | _ -> (
            (* Try OCaml-style first, then Rust-style *)
            match find_ocaml_comment lines end_idx with
            | Some _ as r -> r
            | None -> find_rust_comment lines end_idx)
      end
