open Alcotest

(* Tests for the public Comment_parser module.
   Internal helpers are covered by inline tests in comment_parser.ml.
   Arch_index_comment_parser internals are covered by inline tests in
   arch_index_comment_parser.ml — it is not part of the public API. *)

module CP = Arch_index.Comment_parser

let present_or_none_eq a b =
  match (a, b) with
  | CP.Absent, CP.Absent -> true
  | CP.Present_none, CP.Present_none -> true
  | CP.Present x, CP.Present y -> x = y
  | _ -> false

let present_or_none =
  testable
    (fun fmt v ->
      match v with
      | CP.Absent -> Format.fprintf fmt "Absent"
      | CP.Present_none -> Format.fprintf fmt "Present_none"
      | CP.Present s -> Format.fprintf fmt "Present(%S)" s)
    present_or_none_eq

(* Empty / whitespace-only → everything absent *)
let test_empty () =
  let r = CP.parse "" in
  check (option string) "summary" None r.summary ;
  check present_or_none "pre" CP.Absent r.pre ;
  check present_or_none "post" CP.Absent r.post ;
  check present_or_none "violators" CP.Absent r.violators ;
  check (option int) "score" None r.score

(* JSDoc @tag syntax *)
let test_jsdoc_full () =
  let raw =
    "Does a thing.\n@pre input is valid\n@post result is stable\n@violators\nFoo \xe2\x80\x94 breaks contract"
  in
  let r = CP.parse raw in
  check bool "summary present" true (r.summary <> None) ;
  check present_or_none "pre" (CP.Present "input is valid") r.pre ;
  check present_or_none "post" (CP.Present "result is stable") r.post ;
  check bool "violators present" true
    (match r.violators with CP.Present _ -> true | _ -> false) ;
  check bool "score > 0" true
    (match r.score with Some s -> s > 0 | None -> false)

(* OCaml {tag} syntax — same semantics *)
let test_ocaml_syntax () =
  let raw = "Does a thing.\n{pre}\ninput is valid\n{post}\nresult is stable" in
  let r = CP.parse raw in
  check bool "summary present" true (r.summary <> None) ;
  check present_or_none "pre" (CP.Present "input is valid") r.pre ;
  check present_or_none "post" (CP.Present "result is stable") r.post

(* violators: "none" → Present_none (half credit) *)
let test_violators_present_none () =
  let raw = "@pre ok\n@violators\nnone" in
  let r = CP.parse raw in
  check present_or_none "violators Present_none" CP.Present_none r.violators

(* Full score: all sections present *)
let test_score_maximum () =
  let raw =
    "Summary text.\n@pre guard\n@post result\n@violators\nFoo \xe2\x80\x94 reason\n@violates\nBar \xe2\x80\x94 reason\n@tests\ntest/foo.ml\n@quint\naction()"
  in
  let r = CP.parse raw in
  match r.score with
  | Some s -> check bool "score is 100" true (s = 100)
  | None -> fail "expected a score"

(* Summary extraction: text before first tag *)
let test_summary_extraction () =
  let raw = "This is the summary.\n@pre guard" in
  let r = CP.parse raw in
  check bool "summary contains text" true
    (match r.summary with
    | Some s -> String.length s > 0
    | None -> false)

(* Score: Present_none violators gives 12, Present gives 20 *)
let test_score_present_none_vs_present () =
  let with_none =
    CP.parse "@pre ok\n@violators\nnone"
    |> fun r -> r.score
  in
  let with_present =
    CP.parse ("@pre ok\n@violators\nFoo \xe2\x80\x94 reason")
    |> fun r -> r.score
  in
  check bool "present_none < present" true
    (match (with_none, with_present) with
    | Some a, Some b -> a < b
    | _ -> false)

(* parse_violators_json: "(none)" → None *)
let test_violators_json_none () =
  check (option string) "none → None" None (CP.parse_violators_json "none") ;
  check (option string) "(none) → None" None (CP.parse_violators_json "(none)")

(* parse_violators_json: entry with em-dash *)
let test_violators_json_entry () =
  let em = "\xe2\x80\x94" in
  let result = CP.parse_violators_json ("Mod.f" ^ em ^ " breaks invariant") in
  check bool "entry produced" true (result <> None) ;
  (* result should be valid JSON *)
  match result with
  | None -> fail "expected JSON"
  | Some json ->
      check bool "is a JSON array" true
        (String.length json > 0 && json.[0] = '[')

(* parse_violators_json: multiple entries *)
let test_violators_json_multiple () =
  let em = "\xe2\x80\x94" in
  let raw =
    Printf.sprintf "Mod.f %s reason1\nMod.g %s reason2" em em
  in
  let result = CP.parse_violators_json raw in
  check bool "multiple entries" true (result <> None)

let () =
  run "arch-index parsers"
    [
      ( "Comment_parser",
        [
          test_case "empty comment" `Quick test_empty;
          test_case "JSDoc @tag syntax: full" `Quick test_jsdoc_full;
          test_case "OCaml {tag} syntax" `Quick test_ocaml_syntax;
          test_case "violators: Present_none" `Quick test_violators_present_none;
          test_case "score: maximum 100" `Quick test_score_maximum;
          test_case "summary extraction" `Quick test_summary_extraction;
          test_case "score: Present_none < Present" `Quick test_score_present_none_vs_present;
          test_case "parse_violators_json: none → None" `Quick test_violators_json_none;
          test_case "parse_violators_json: entry" `Quick test_violators_json_entry;
          test_case "parse_violators_json: multiple" `Quick test_violators_json_multiple;
        ] );
    ]
