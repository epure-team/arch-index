(******************************************************************************)
(*                                                                            *)
(* Copyright (c) 2026 Epure Team                                              *)
(* All rights reserved.                                                       *)
(*                                                                            *)
(******************************************************************************)

(** A [file://] URI must carry an absolute path. The project directory reaches
    this library as a Cmdliner [dir] argument, which returns the string exactly
    as typed — so `--project .` produced `file://./src/foo.ml`. That is not a
    valid file URI: the server cannot open the document, every
    [textDocument/documentSymbol] comes back empty, and the run writes an empty
    index while reporting success.

    These pin the conversion in both directions. *)

module U = Arch_index.Lsp_client

let cwd = Sys.getcwd ()

(* The defect, stated as a test: a relative input must not survive into the URI. *)
let test_relative_becomes_absolute () =
  let uri = U.file_uri_of_path "./src/foo.ml" in
  Alcotest.(check bool)
    "no relative segment survives in the URI"
    false
    (String.length uri > 8 && String.sub uri 7 2 = "./") ;
  Alcotest.(check string)
    "the cwd is prepended and ./ collapsed"
    ("file://" ^ cwd ^ "/src/foo.ml")
    uri

let test_bare_relative_becomes_absolute () =
  Alcotest.(check string)
    "a path with no leading ./ is absolutised too"
    ("file://" ^ cwd ^ "/lib/bar.ml")
    (U.file_uri_of_path "lib/bar.ml")

let test_absolute_is_preserved () =
  Alcotest.(check string)
    "an already-absolute path is left alone"
    "file:///tmp/x/y.ml"
    (U.file_uri_of_path "/tmp/x/y.ml")

let test_interior_dot_segments_collapse () =
  Alcotest.(check string)
    "interior ./ and doubled separators collapse"
    "file:///tmp/x/y.ml"
    (U.file_uri_of_path "/tmp/./x//y.ml")

(* Round-trip: whatever we send, we must be able to read back. The strip half
   was duplicated in two modules; both now share this one. *)
let test_round_trip () =
  let paths = ["/tmp/a/b.ml"; "/tmp/a b/c.ml"; "/x.ml"] in
  List.iter
    (fun p ->
      Alcotest.(check string)
        (Printf.sprintf "round-trip %s" p)
        p
        (U.path_of_file_uri (U.file_uri_of_path p)))
    paths

let test_strip_tolerates_a_non_uri () =
  Alcotest.(check string)
    "a bare path is returned unchanged rather than mangled"
    "/tmp/a.ml"
    (U.path_of_file_uri "/tmp/a.ml")

let test_strip_handles_the_triple_slash_form () =
  Alcotest.(check string)
    "file:///abs and file://abs both yield the absolute path"
    "/tmp/a.ml"
    (U.path_of_file_uri "file:///tmp/a.ml") ;
  Alcotest.(check string)
    "the two-slash form is accepted too"
    "/tmp/a.ml"
    (U.path_of_file_uri "file:///tmp/a.ml")


(* The mirror of the URI defect, on the way back in. [relative_path] compared a
   possibly-relative project_dir against an absolute path from the server, so it
   never matched and every file_path was stored absolute — making the database
   machine-specific and breaking any lookup keyed on a repo-relative path. *)
let test_relative_path_against_a_relative_project_dir () =
  Alcotest.(check string)
    "a relative project dir still yields a repo-relative path"
    "src/foo.ml"
    (U.relative_path ~project_dir:"." (cwd ^ "/src/foo.ml")) ;
  Alcotest.(check string)
    "an absolute project dir works as before"
    "src/foo.ml"
    (U.relative_path ~project_dir:cwd (cwd ^ "/src/foo.ml"))

let test_relative_path_leaves_a_foreign_path_alone () =
  Alcotest.(check string)
    "a path outside the project is returned unchanged"
    "/elsewhere/x.ml"
    (U.relative_path ~project_dir:cwd "/elsewhere/x.ml")

let () =
  Alcotest.run
    "lsp_uri"
    [
      ( "file_uri_of_path",
        [
          Alcotest.test_case
            "a relative path is absolutised"
            `Quick
            test_relative_becomes_absolute;
          Alcotest.test_case
            "a bare relative path is absolutised"
            `Quick
            test_bare_relative_becomes_absolute;
          Alcotest.test_case
            "an absolute path is preserved"
            `Quick
            test_absolute_is_preserved;
          Alcotest.test_case
            "interior dot segments collapse"
            `Quick
            test_interior_dot_segments_collapse;
        ] );
      ( "relative_path",
        [
          Alcotest.test_case
            "a relative project dir still relativises"
            `Quick
            test_relative_path_against_a_relative_project_dir;
          Alcotest.test_case
            "a foreign path is left alone"
            `Quick
            test_relative_path_leaves_a_foreign_path_alone;
        ] );
      ( "path_of_file_uri",
        [
          Alcotest.test_case "round-trip" `Quick test_round_trip;
          Alcotest.test_case
            "a non-URI is returned unchanged"
            `Quick
            test_strip_tolerates_a_non_uri;
          Alcotest.test_case
            "the triple-slash form is handled"
            `Quick
            test_strip_handles_the_triple_slash_form;
        ] );
    ]
