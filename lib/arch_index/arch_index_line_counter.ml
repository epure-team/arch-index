(******************************************************************************)
(*                                                                            *)
(* Copyright (c) 2026 Epure Team                                              *)
(* All rights reserved.                                                       *)
(*                                                                            *)
(******************************************************************************)

(** Count non-comment, non-blank lines in an OCaml source file.
    Handles nested comments and string literals, including quoted strings. *)

(** Lexer state carried through the scan. Immutable and threaded as a parameter,
    so every condition below is a stable expression an analyser can reason about
    — unlike the previous [ref]-based state machine, where `!i < len` was opaque
    to arch-index's own decision analysis. Tail calls compile to jumps, so this
    costs nothing at runtime. *)
type scan_state = {
  depth : int;  (** comment nesting depth *)
  in_string : bool;
  quoted : string option;  (** delimiter of an open {id|…|id} literal *)
}

let initial_state = {depth = 0; in_string = false; quoted = None}

let is_ident_char c =
  (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z')
  || (c >= '0' && c <= '9')
  || c = '_'

(** [scan_line st line] returns the state after [line] and whether it held code. *)
let scan_line st line =
  let len = String.length line in
  let rec ident_end j = if j < len && is_ident_char line.[j] then ident_end (j + 1) else j in
  let rec go st i has_code =
    if i >= len then (st, has_code)
    else
      match st.quoted with
      | Some delim ->
          (* inside {id|…|id} — look for the closing |id} *)
          let dl = String.length delim in
          if
            i + dl < len
            && line.[i] = '|'
            && String.sub line (i + 1) dl = delim
            && i + dl + 1 < len
            && line.[i + dl + 1] = '}'
          then go {st with quoted = None} (i + dl + 2) has_code
          else go st (i + 1) has_code
      | None ->
          if st.in_string then
            if line.[i] = '\\' && i + 1 < len then go st (i + 2) has_code
            else if line.[i] = '"' then go {st with in_string = false} (i + 1) has_code
            else go st (i + 1) has_code
          else if st.depth > 0 then
            if i + 1 < len && line.[i] = '*' && line.[i + 1] = ')' then
              go {st with depth = st.depth - 1} (i + 2) has_code
            else if i + 1 < len && line.[i] = '(' && line.[i + 1] = '*' then
              go {st with depth = st.depth + 1} (i + 2) has_code
            else go st (i + 1) has_code
          else if line.[i] = '"' then go {st with in_string = true} (i + 1) true
          else if line.[i] = '{' && i + 1 < len && line.[i + 1] = '|' then
            go {st with quoted = Some ""} (i + 2) true
          else if line.[i] = '{' then
            let j = ident_end (i + 1) in
            if j < len && line.[j] = '|' && j > i + 1 then
              go {st with quoted = Some (String.sub line (i + 1) (j - i - 1))} (j + 1) true
            else go st (i + 1) true
          else if i + 1 < len && line.[i] = '(' && line.[i + 1] = '*' then
            go {st with depth = st.depth + 1} (i + 2) has_code
          else
            let c = line.[i] in
            go st (i + 1) (has_code || (c <> ' ' && c <> '\t' && c <> '\r'))
  in
  go st 0 false

(** Count non-comment, non-blank lines in an OCaml source file.
    Handles nested comments and string literals, including quoted strings. *)
let run_count_code_lines path =
  let ic = open_in path in
  Fun.protect
    ~finally:(fun () -> close_in ic)
    (fun () ->
      let rec lines st acc =
        match input_line ic with
        | line ->
            let st, has_code = scan_line st line in
            lines st (if has_code then acc + 1 else acc)
        | exception End_of_file -> acc
      in
      lines initial_state 0)
