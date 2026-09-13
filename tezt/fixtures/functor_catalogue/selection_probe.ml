exception Assertion_failure of string

let assertion fmt = Printf.ksprintf (fun message -> raise (Assertion_failure message)) fmt

let run () =
  let input = ["z.cmt"; "./same.cmt"; "z.cmt"; "link/same.cmt"; "./same.cmt"] in
  let selected = Arch_index__Arch_index_functors.selected_inputs input in
  let expected = ["./same.cmt"; "link/same.cmt"; "z.cmt"] in
  if selected <> expected then
    assertion "exact-string selection mismatch" ;
  Yojson.Safe.to_channel stdout
    (`Assoc [("ok", `Bool true); ("premise", `String "exact-string-selection");
             ("input", `List (List.map (fun value -> `String value) input));
             ("selected", `List (List.map (fun value -> `String value) selected))])

let () =
  try run () with
  | Assertion_failure message -> prerr_endline ("selection_probe assertion: " ^ message) ; exit 1
  | Failure message -> prerr_endline ("selection_probe setup: unexpected runtime failure: " ^ message) ; exit 2
  | exn -> prerr_endline ("selection_probe setup: " ^ Printexc.to_string exn) ; exit 2
