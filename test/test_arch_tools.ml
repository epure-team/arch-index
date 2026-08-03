(** Unit tests for the shared tool library.

    These pin two things that are easy to get subtly wrong and impossible to notice from a
    passing end-to-end run: how a path with leading [..] normalises (get it wrong and a
    tracefile joins to the wrong indexed file), and which glob shapes [**] is allowed to cross
    (get it wrong and an architecture rule silently stops matching, or starts matching a file
    with a similar name). *)

module P = Arch_tools.Arch_path
module Sel = Arch_tools.Arch_sel

let check_norm (input, expected) =
  Alcotest.(check string) (Printf.sprintf "normalise %S" input) expected (P.normalise input)

let normalise () =
  List.iter check_norm
    [ ("a/b", "a/b");
      ("a/./b", "a/b");
      ("a//b", "a/b");
      ("a/../b", "b");
      ("./a", "a");
      (* A leading [..] has nothing to cancel. Dropping it made [../../a] collide with a file
         genuinely at [a]. *)
      ("../a", "../a");
      ("../../a", "../../a");
      ("../../a/b", "../../a/b");
      (* ...but one that DOES have something to cancel still cancels, including down to a
         remaining [..]. *)
      ("a/../../b", "../b");
      ("a/b/../c", "a/c");
      (* POSIX: [/..] is [/]. An absolute path can never escape the root. *)
      ("/..", "/");
      ("/a/../../b", "/b");
      ("/a/b/../c", "/a/c") ]

let glob () =
  let m pat s = Sel.glob_match pat s in
  (* [**/] must span WHOLE directory components, or none. *)
  Alcotest.(check bool) "**/parser.ml matches at the root" true (m "**/parser.ml" "parser.ml") ;
  Alcotest.(check bool) "**/parser.ml matches nested" true (m "**/parser.ml" "lib/a/parser.ml") ;
  Alcotest.(check bool) "**/parser.ml does NOT match my_parser.ml" false
    (m "**/parser.ml" "lib/my_parser.ml") ;
  Alcotest.(check bool) "* does not cross a separator" false (m "lib/*.ml" "lib/a/b.ml") ;
  Alcotest.(check bool) "* matches within a component" true (m "lib/*.ml" "lib/b.ml") ;
  Alcotest.(check bool) "a literal dot is not a wildcard" false (m "lib/a.ml" "lib/axml")

(* Expected strings captured from `sqlite3 -list` (3.45.1) over a REAL column holding exactly
   these values. The whole point of the renderer is byte-parity with sqlite, and byte-parity is
   not something an end-to-end run over one project's data can demonstrate. *)
let float_text () =
  List.iter
    (fun (f, expected) ->
      Alcotest.(check string)
        (Printf.sprintf "float_to_string %h" f)
        expected
        (Arch_tools.Arch_db.float_to_string f))
    [ (1.5, "1.5");
      (125.0, "125.0");
      (1234567.0, "1234567.0");
      (0.1, "0.1");
      (0.0001, "0.0001");
      (-1.5, "-1.5");
      (123456789012345.0, "123456789012345.0");
      (* Exponent form: sqlite always writes a mantissa with a decimal point. These returned
         "1e+300" / "1e-05" / "3e+22" before. *)
      (1e300, "1.0e+300");
      (1e-5, "1.0e-05");
      (1e-7, "1.0e-07");
      (3.0e22, "3.0e+22");
      (1e15, "1.0e+15");
      (2e15, "2.0e+15");
      (* sqlite's text output is presentation, not round-trip: it prints the %.15g mantissa even
         when that does not read back as the same double. A %.17g fallback broke this one. *)
      (123456789012345678.0, "1.23456789012346e+17");
      (9999999999999998.0, "1.0e+16") ]

let () =
  Alcotest.run "arch_tools"
    [ ("path", [ Alcotest.test_case "normalise" `Quick normalise ]);
      ("selector", [ Alcotest.test_case "glob_match" `Quick glob ]);
      ("format", [ Alcotest.test_case "float_to_string" `Quick float_text ]) ]
