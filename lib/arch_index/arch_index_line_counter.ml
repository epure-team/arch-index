(******************************************************************************)
(*                                                                            *)
(* Copyright (c) 2026 Epure Team                                              *)
(* All rights reserved.                                                       *)
(*                                                                            *)
(******************************************************************************)

(** Count non-comment, non-blank lines in an OCaml source file.
    Handles nested comments and string literals, including quoted strings. *)
let run_count_code_lines path =
  let ic = open_in path in
  Fun.protect
    ~finally:(fun () -> close_in ic)
    (fun () ->
      let code_lines = ref 0 in
      let in_comment = ref 0 in
      (* nesting depth *)
      let in_string = ref false in
      let in_quoted_string = ref None in
      (* None or Some delimiter *)
      let line_has_code = ref false in
      try
        while true do
          let line = input_line ic in
          line_has_code := false ;
          let len = String.length line in
          let i = ref 0 in
          while !i < len do
            match !in_quoted_string with
            | Some delim ->
                (* Inside quoted string {id|...|id} - look for |id} *)
                let delim_len = String.length delim in
                if
                  !i + delim_len < len
                  && line.[!i] = '|'
                  && String.sub line (!i + 1) delim_len = delim
                  && !i + delim_len + 1 < len
                  && line.[!i + delim_len + 1] = '}'
                then (
                  in_quoted_string := None ;
                  i := !i + delim_len + 2)
                else incr i
            | None ->
                if !in_string then
                  if
                    (* Inside regular string - look for end quote or escape *)
                    line.[!i] = '\\' && !i + 1 < len
                  then i := !i + 2 (* skip escaped char *)
                  else if line.[!i] = '"' then (
                    in_string := false ;
                    incr i)
                  else incr i
                else if !in_comment > 0 then
                  if
                    (* Inside comment - look for end or nested start *)
                    !i + 1 < len && line.[!i] = '*' && line.[!i + 1] = ')'
                  then (
                    decr in_comment ;
                    i := !i + 2)
                  else if !i + 1 < len && line.[!i] = '(' && line.[!i + 1] = '*'
                  then (
                    incr in_comment ;
                    i := !i + 2)
                  else incr i
                else if line.[!i] = '"' then (
                  (* Start of regular string *)
                  in_string := true ;
                  line_has_code := true ;
                  incr i)
                else if line.[!i] = '{' && !i + 1 < len && line.[!i + 1] = '|'
                then (
                  (* Start of quoted string {|...|} *)
                  in_quoted_string := Some "" ;
                  line_has_code := true ;
                  i := !i + 2)
                else if line.[!i] = '{' then (
                  (* Check for {id|...|id} where id is alphanumeric *)
                  let j = ref (!i + 1) in
                  while
                    !j < len
                    &&
                    let c = line.[!j] in
                    (c >= 'a' && c <= 'z')
                    || (c >= 'A' && c <= 'Z')
                    || (c >= '0' && c <= '9')
                    || c = '_'
                  do
                    incr j
                  done ;
                  if !j < len && line.[!j] = '|' && !j > !i + 1 then (
                    (* Found opening of quoted string with delimiter *)
                    let delim = String.sub line (!i + 1) (!j - !i - 1) in
                    in_quoted_string := Some delim ;
                    line_has_code := true ;
                    i := !j + 1)
                  else (
                    line_has_code := true ;
                    incr i))
                else if !i + 1 < len && line.[!i] = '(' && line.[!i + 1] = '*'
                then (
                  (* Start of comment *)
                  incr in_comment ;
                  i := !i + 2)
                else
                  (* Outside comment and string - check if this is code *)
                  let c = line.[!i] in
                  if c <> ' ' && c <> '\t' && c <> '\r' then
                    line_has_code := true ;
                  incr i
          done ;
          if !line_has_code then incr code_lines
        done ;
        !code_lines
      with End_of_file -> !code_lines)
