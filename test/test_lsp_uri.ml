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

(* NOTE on what this pins: [file_uri_of_path] emits UNENCODED URIs, so a path
   containing a space round-trips as "file:///tmp/a b/c.ml" rather than
   percent-encoded. That is pre-existing behaviour, and asserting the round-trip
   over such a path pins it — deliberately, because the two halves must agree
   with each other whatever the encoding policy is. Adding percent-encoding
   later means changing both halves and this case together, which is the
   intended coupling rather than an obstacle.

   Round-trip: whatever we send, we must be able to read back. The strip half
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

(* Only the three-slash form is claimed. [file_uri_of_path] never emits the
   two-slash form, so its handling is documented rather than tested: stripping
   the prefix of "file://tmp/a.ml" yields the relative "tmp/a.ml", which is what
   the .mli promises and not something to pretend otherwise about. An earlier
   version of this case passed the same string twice under a label claiming
   two-slash support the code does not have. *)
let test_strip_handles_the_triple_slash_form () =
  Alcotest.(check string)
    "the file:// prefix is removed, leaving the absolute path"
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

(* The guard is a conjunction, and the foreign-path case below only exercises
   one conjunct: "/elsewhere/x.ml" shares no prefix with the root, so the
   `String.sub … = root` test already fails and the boundary check is never
   reached. Two independent mutations of the guard survived the suite because of
   that. These two cases exercise the other conjuncts.

   The first is the one that matters: without the '/' boundary check,
   project_dir="/home/me/proj" and abs_path="/home/me/project-docs/x.ml" yields
   "ct-docs/x.ml" — a silently corrupted path written to the database, reachable
   whenever the server returns a symbol from a sibling directory sharing the
   root's prefix. Language servers do return out-of-workspace paths. *)
let test_relative_path_requires_a_separator_boundary () =
  Alcotest.(check string)
    "a sibling directory sharing the root's prefix is NOT relativised"
    "/home/me/project-docs/x.ml"
    (U.relative_path
       ~project_dir:"/home/me/proj"
       "/home/me/project-docs/x.ml")

(* And the length guard: an abs_path equal to the root must not index past its
   end. The .mli documents no precondition, so raising here would be a defect in
   a function advertised as total. *)
let test_relative_path_on_the_root_itself_does_not_raise () =
  Alcotest.(check string)
    "abs_path equal to the project dir is returned unchanged"
    "/home/me/proj"
    (U.relative_path ~project_dir:"/home/me/proj" "/home/me/proj")

(* `..` must resolve, or `--project ../sibling` keeps the defect this helper
   exists to remove. *)
let test_dotdot_resolves () =
  Alcotest.(check string)
    "a parent segment is popped, not carried"
    "file:///tmp/sibling/x.ml"
    (U.file_uri_of_path "/tmp/proj/../sibling/x.ml") ;
  Alcotest.(check string)
    "a parent segment at the root has nothing to pop"
    "file:///x.ml"
    (U.file_uri_of_path "/../x.ml") ;
  Alcotest.(check string)
    "and relativisation works through it"
    "x.ml"
    (U.relative_path ~project_dir:"/tmp/proj/../sibling" "/tmp/sibling/x.ml")

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
            "a prefix without a separator boundary is not relativised"
            `Quick
            test_relative_path_requires_a_separator_boundary;
          Alcotest.test_case
            "the root itself does not raise"
            `Quick
            test_relative_path_on_the_root_itself_does_not_raise;
          Alcotest.test_case
            "parent segments resolve"
            `Quick
            test_dotdot_resolves;
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
