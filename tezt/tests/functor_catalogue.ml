(******************************************************************************)
(*                                                                            *)
(* Copyright (c) 2026 Epure Team                                              *)
(* All rights reserved.                                                       *)
(*                                                                            *)
(******************************************************************************)

open Arch_tezt

let fixture_files =
  [
    Fixture.dune_project;
    ("dune", "(library\n (name functor_catalogue_fixture)\n (wrapped false)\n (modules fixture))\n");
    ( "fixture.ml",
      {ocaml|module type S = sig val n : int end
module F (X : S) = struct let n = X.n end
module X = struct let n = 1 end
module M = F (X)
|ocaml} );
  ]

let composition_files =
  [ Fixture.dune_project;
    ("dune", "(library\n (name functor_composition_fixture)\n (wrapped false)\n (modules composition))\n");
    ("composition.ml", {ocaml|module type S = sig val n : int end
module A = struct let n = 1 end
module B = struct let n = 2 end
module F (X : S) = struct let n = X.n end
module G (X : S) (Y : S) = struct let n = X.n + Y.n end
module U () = struct let n = 0 end
module Chain = G(A)(B)
module Nested = F(F(A))
module Anonymous = F(struct let n = 3 end)
module Unit = U()
module Inline = (functor (X : S) -> X)(A)
module Typeof = (A : module type of F(A))
|ocaml}) ]

let register_ordinary_application () =
  Test.register ~__FILE__
    ~title:"functor catalogue: indexes one ordinary application"
    ~tags:["cmt"; "functor"; "catalogue"]
  @@ fun () ->
  with_fixture ~name:"functor_catalogue_ordinary" ~files:fixture_files @@ fun fixture ->
  let db_path = index fixture in
  Db.with_db db_path (fun db ->
      Check.(
        (Db.int db
           "SELECT count(*) FROM sqlite_master WHERE type='table' AND \
            name='functor_applications'"
        = 1)
          int
          ~error_msg:"fixture compiled and indexed, but functor_applications table count is %L, expected %R") ;
      Check.((Db.int db "SELECT count(*) FROM functor_applications" = 1) int
        ~error_msg:"ordinary fixture should store exactly %R application, got %L") ;
      Check.((Db.string_opt db "SELECT application_kind FROM functor_applications" = Some "apply")
        (option string) ~error_msg:"application_kind expected %R, got %L") ;
      Check.((Db.int db "SELECT ordinal FROM functor_applications" = 1) int
        ~error_msg:"ordinary application ordinal expected %R, got %L") ;
      let head = Option.value ~default:"" (Db.string_opt db "SELECT head FROM functor_applications") in
      let argument = Option.value ~default:"" (Db.string_opt db "SELECT argument FROM functor_applications") in
      Check.((Arch_tezt.contains ~needle:{|"kind":"path"|} head = true) bool
        ~error_msg:"head path descriptor absent: %L") ;
      Check.((Arch_tezt.contains ~needle:{|"source":"F"|} head = true) bool
        ~error_msg:"head source spelling absent: %L") ;
      Check.((Arch_tezt.contains ~needle:{|"source":"X"|} argument = true) bool
        ~error_msg:"argument source spelling absent: %L") ;
      Check.((Db.string_opt db "SELECT diagnostics FROM functor_applications" = Some "[]")
        (option string) ~error_msg:"ordinary application diagnostics expected %R, got %L") ;
      Check.((Db.string_opt db "SELECT value FROM comment_db_meta WHERE key='functor_catalogue_contract'" = Some "v1")
        (option string) ~error_msg:"catalogue marker expected %R, got %L") ;
      (* Exact graph snapshot: the application inventories composition but creates no
         instantiated definitions or call edges. *)
      Check.((Db.int db "SELECT count(*) FROM calls" = 0) int
        ~error_msg:"catalogue changed graph call rows: expected %R, got %L") ;
      Check.((Db.int db "SELECT count(*) FROM functions WHERE name LIKE 'M.%'" = 0) int
        ~error_msg:"application incorrectly cloned %L definitions, expected %R") ;
      Lwt.return_unit)

let register_selection_identity () =
  Test.register ~__FILE__ ~title:"functor catalogue: selection deduplicates exact strings only"
    ~tags:["functor"; "catalogue"; "selection"]
  @@ fun () ->
  let selected = Arch_index__Arch_index_functors.selected_inputs
      ["z.cmt"; "a.cmt"; "z.cmt"; "./a.cmt"; "link.cmt"] in
  Check.((selected = ["./a.cmt"; "a.cmt"; "link.cmt"; "z.cmt"])
    (list string) ~error_msg:"exact-string selection expected %R, got %L") ;
  Lwt.return_unit

let register_native_probes () =
  Test.register ~__FILE__ ~title:"functor catalogue: native artifact and lifecycle premises hold"
    ~tags:["functor"; "catalogue"; "probe"]
  @@ fun () ->
  let probe name = locate ~env_var:("ARCH_FUNCTOR_" ^ String.uppercase_ascii name)
      ("tezt/fixtures/functor_catalogue/" ^ name ^ ".exe") in
  let seed = locate ~env_var:"ARCH_FUNCTOR_CATALOGUE_CMT"
      "tezt/fixtures/functor_catalogue/.catalogue.objs/byte/catalogue.cmt" in
  let code, census = run_command (probe "typedtree_probe") ["census"; "--input"; seed] in
  Check.((code = 0) int ~error_msg:"typedtree census exit expected %R, got %L") ;
  Check.((Arch_tezt.contains ~needle:{|"apply":18|} census = true) bool
    ~error_msg:"typedtree census premise absent: %L") ;
  List.iter (fun name ->
      let code, output = run_command (probe name) [] in
      Check.((code = 0) int ~error_msg:(name ^ " probe exit expected %R, got %L")) ;
      Check.((Arch_tezt.contains ~needle:{|"ok":true|} output = true) bool
        ~error_msg:(name ^ " probe premise absent: %L")))
    ["storage_probe"; "lifecycle_probe"; "selection_probe"] ;
  Lwt.return_unit

let register_query () =
  Test.register ~__FILE__ ~title:"functor catalogue: query renders a validated snapshot"
    ~tags:["query"; "functor"; "catalogue"]
  @@ fun () ->
  with_fixture ~name:"functor_catalogue_query" ~files:fixture_files @@ fun fixture ->
  let db = index fixture in
  let code, output = run_command ~env:[("ARCH_QUERY_FORMAT", "json")] (arch_query ())
      [db; "functor-applications"; "1"] in
  Check.((code = 0) int ~error_msg:"query exit expected %R, got %L") ;
  Check.((Arch_tezt.contains ~needle:{|"contract":"v1"|} output = true) bool
    ~error_msg:"query summary contract absent: %L") ;
  Check.((Arch_tezt.contains ~needle:{|"total":1|} output = true) bool
    ~error_msg:"query total absent: %L") ;
  let status_code, status = run_command ~env:[("ARCH_QUERY_FORMAT", "json")] (arch_query ())
      [db; "analysis-status"] in
  Check.((status_code = 0) int ~error_msg:"analysis-status exit expected %R, got %L") ;
  Check.((Arch_tezt.contains
            ~needle:{|"analysis":"functor_catalogue","availability":"COMPUTED","contract":"v1"|}
            status = true) bool
    ~error_msg:"analysis-status must distinguish collected catalogue evidence: %L") ;
  let status_bad_code, _ = run_command (arch_query ()) [db; "analysis-status"; "unexpected"] in
  Check.((status_bad_code = 2) int
    ~error_msg:"analysis-status arguments must be refused with %R, got %L") ;
  let bad_code, _ = run_command (arch_query ()) ["/definitely/not/opened.db"; "functor-applications"; "0x10"] in
  Check.((bad_code = 2) int ~error_msg:"invalid limit must fail before DB open with %R, got %L") ;
  Lwt.return_unit

let register_composition () =
  Test.register ~__FILE__ ~title:"functor catalogue: preserves preorder and operand shapes"
    ~tags:["cmt"; "functor"; "catalogue"; "preorder"]
  @@ fun () ->
  with_fixture ~name:"functor_catalogue_composition" ~files:composition_files @@ fun fixture ->
  let db = index fixture in
  Db.with_db db (fun conn ->
      Check.((Db.int conn "SELECT count(*) FROM functor_applications" = 8) int
        ~error_msg:"composition fixture expected %R immediate applications, got %L") ;
      Check.((Db.int conn "SELECT count(*) FROM functor_applications WHERE ordinal < 1 OR ordinal > 8" = 0) int
        ~error_msg:"application ordinals outside contiguous 1..8: %L, expected %R") ;
      Check.((Db.int conn "SELECT count(*) FROM functor_applications WHERE application_kind='apply_unit'" = 1) int
        ~error_msg:"unit application count expected %R, got %L") ;
      Check.((Db.int conn "SELECT count(*) FROM functor_applications WHERE diagnostics LIKE '%anonymous_argument%'" = 1) int
        ~error_msg:"anonymous structure diagnostic count expected %R, got %L") ;
      Check.((Db.int conn "SELECT count(*) FROM functor_applications WHERE diagnostics LIKE '%opaque_functor_head%'" = 1) int
        ~error_msg:"inline functor-head diagnostic count expected %R, got %L") ;
      Check.((Db.int conn "SELECT count(*) FROM functor_applications WHERE head LIKE '%application%'" = 1) int
        ~error_msg:"chained/nested head reference count expected %R, got %L") ;
      Lwt.return_unit)

let register_failed_selection () =
  Test.register ~__FILE__ ~title:"functor catalogue: one unreadable input prevents eligibility"
    ~tags:["cmt"; "functor"; "catalogue"; "lifecycle"]
  @@ fun () ->
  with_fixture ~name:"functor_catalogue_partial" ~files:fixture_files @@ fun fixture ->
  write_file (Filename.concat fixture.build_dir "broken.cmt") "not a cmt" ;
  let db = index fixture in
  Db.with_db db (fun conn ->
      Check.((Db.int conn "SELECT count(*) FROM functor_catalogue_inputs" = 2) int
        ~error_msg:"every selected input expected an outcome (%R), got %L") ;
      Check.((Db.int conn "SELECT count(*) FROM functor_catalogue_inputs WHERE outcome='unreadable'" = 1) int
        ~error_msg:"unreadable outcome count expected %R, got %L") ;
      Check.((Db.int conn "SELECT count(*) FROM functor_applications" = 1) int
        ~error_msg:"successful input graph/catalogue facts must survive sibling failure: expected %R, got %L") ;
      Check.((Db.string_opt conn "SELECT value FROM comment_db_meta WHERE key='functor_catalogue_contract'" = None)
        (option string) ~error_msg:"partial selection must have marker %R, got %L") ;
      Lwt.return_unit)

let register_checkers () =
  List.iter (fun mode ->
      Test.register ~__FILE__
        ~title:("functor catalogue independent checker: " ^ mode)
        ~tags:["functor"; "catalogue"; "independent_checker"]
      @@ fun () ->
      let checker = Filename.concat (repo_root ()) "scripts/check-functor-catalogue.js" in
      let code, stdout, stderr = run_command_split "node" [checker; mode] in
      if code <> 0 then
        Test.fail "catalogue checker %s exit %d (1=assertion, >=2=execution)\n%s\n%s"
          mode code stdout stderr ;
      Lwt.return_unit)
    ["inventory"; "lifecycle"; "query"; "compatibility"]

let register () =
  register_ordinary_application () ;
  register_selection_identity () ;
  register_native_probes () ;
  register_composition () ;
  register_failed_selection () ;
  register_query () ;
  register_checkers ()
