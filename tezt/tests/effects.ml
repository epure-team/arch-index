(******************************************************************************)
(*                                                                            *)
(* Copyright (c) 2026 Epure Team                                              *)
(* All rights reserved.                                                       *)
(*                                                                            *)
(******************************************************************************)

(** The effects layer, end to end, on three producers.

    The same four questions are asked of each language, because the point of the
    layer is that they answer identically regardless of where the facts came
    from: which functions mutate a given value kind, which kinds a function's
    closure reaches, which functions are pure, and which are dead.

    Rust is a hand-crafted NDJSON stub on purpose — the MIR extractor does not
    exist yet, so what is under test there is the CONTRACT the eventual producer
    must satisfy, not a producer. Marking it `candidate` rather than `sound` is
    part of that contract. *)

open Arch_tezt

let arch_effects_ocaml () =
  locate ~env_var:"ARCH_EFFECTS_OCAML" "bin/arch_effects_ocaml/arch_effects_ocaml.exe"

let effects_load () =
  locate ~env_var:"ARCH_EFFECTS_LOAD" "bin/arch_effects_load/main.exe"

let migration () = locate ~env_var:"ARCH_EFFECTS_MIGRATION" "effects-schema-migration.sql"

let apply_migration db =
  Db.with_db_rw db (fun conn -> Db.exec conn (read_file (migration ())))

let ocaml_files =
  [
    ("dune-project", "(lang dune 3.0)\n");
    ("dune", "(library (name efxtest) (modules efxtest))\n");
    ("efxtest.ml", {|(* Effects fixture for selftest-effects.sh
   Mutations:
     counter_ref : ref — HeapRef (module-level)
     record_mutator : mutable field — FieldAccess
     array_mutator : array element — ArrayElem
     hashtbl_mutator : Hashtbl.replace — HashTbl
     bytes_mutator : Bytes.set — BytesBuf
     pure_fn : no mutations
     island_fn : never called
*)

type box = { mutable value: int }

let counter_ref = ref 0

let record_mutator (b : box) = b.value <- 42

let array_mutator (a : int array) = a.(0) <- 99

let hashtbl_mutator (h : (string, int) Hashtbl.t) =
  Hashtbl.replace h "key" 1

let bytes_mutator (b : bytes) = Bytes.set b 0 'X'

let pure_fn (x : int) (y : int) : int = x + y

let island_fn () : int = 7

let exported_entry (b : box) (a : int array) (h : (string, int) Hashtbl.t) =
  record_mutator b;
  array_mutator a;
  hashtbl_mutator h
|});
  ]

let register_ocaml () =
  Test.register ~__FILE__ ~title:"effects: the OCaml CMT extractor answers all four questions"
    ~tags:["effects"; "cmt"]
  @@ fun () ->
  with_fixture ~name:"effects_ocaml" ~files:ocaml_files @@ fun fixture ->
  let db = index fixture in
  apply_migration db ;
  let code, ndjson, err = run_command_split (arch_effects_ocaml ()) ["--build-dir"; fixture.build_dir] in
  if code <> 0 then Test.fail "arch_effects_ocaml failed (exit %d):\n%s" code err ;
  let code, out = run_command ~stdin:ndjson (effects_load ()) [db] in
  if code <> 0 then Test.fail "loading the OCaml effects failed (exit %d):\n%s" code out ;
  Batch.run (fun b ->
      Batch.contains b ~msg:"hashtbl_mutator must be a HashTbl mutator"
        ~haystack:(query db ["mutators-of"; "HashTbl"]) "hashtbl_mutator" ;
      Batch.contains b ~msg:"record_mutator must be a FieldAccess mutator"
        ~haystack:(query db ["mutators-of"; "FieldAccess"]) "record_mutator" ;

      (* effects-of walks the CLOSURE: exported_entry mutates nothing itself. *)
      let entry = discover db ~like:"exported_entry" ~unlike:None in
      let eff = query db ["effects-of"; entry] in
      List.iter
        (fun kind ->
          Batch.contains b
            ~msg:(Printf.sprintf "effects-of %s must reach %s through its callees" entry kind)
            ~haystack:eff kind)
        ["FieldAccess"; "HashTbl"] ;

      Batch.contains b ~msg:"a function with no effects must be listed pure"
        ~haystack:(query db ["pure-fns"]) "pure_fn" ;
      Batch.contains b ~msg:"a function nothing calls must be reported dead"
        ~haystack:(query db ["dead-code"]) "island_fn") ;
  Lwt.return_unit

let go_files =
  [("go.mod", "module efxtest\ngo 1.21\n"); ("main.go", {|package main

import "fmt"

// mutates a map → HashTbl
func mapMutator(m map[string]int) { m["key"] = 42 }

// mutates a struct field → FieldAccess
type Box struct{ Value int }
func fieldMutator(b *Box) { b.Value = 99 }

// mutates an array → ArrayElem
func arrayMutator(a []int) { a[0] = 7 }

// pure function (no mutations)
func pureFn(x, y int) int { return x + y }

// I/O side effect
func ioFn() { fmt.Println("hello") }

// island: never called
func islandFn() int { return 0 }

// entry point: calls map/field/array mutators
func entry(m map[string]int, b *Box, a []int) {
  mapMutator(m)
  fieldMutator(b)
  arrayMutator(a)
}

func main() { entry(nil, nil, nil) }
|})]

let register_go () =
  Test.register ~__FILE__ ~title:"effects: the Go SSA extractor answers the same four"
    ~tags:["effects"; "go"]
  @@ fun () ->
  if not (runnable "go" ["version"]) then not_exercised "Go: the go toolchain is not runnable"
  else
    with_project ~name:"effects_go" ~files:go_files (fun project ->
        let build_go ~dir ~out =
          let code, output = run_command ~cwd:dir "go" ["build"; "-o"; out; "."] in
          if code <> 0 then Test.fail "building %s failed (exit %d):\n%s" dir code output ;
          out
        in
        let tmp = Temp.dir "effects_go_bin" in
        let cg = build_go ~dir:(callgraph_go_src ()) ~out:(Filename.concat tmp "arch-callgraph-go") in
        let eff =
          build_go
            ~dir:(Filename.concat (callgraph_go_src ()) "effects")
            ~out:(Filename.concat tmp "arch-effects-go")
        in
        let pattern = Filename.concat project "..." in
        let code, ndjson, err = run_command_split cg [pattern] in
        if code <> 0 then Test.fail "arch-callgraph-go failed (exit %d):\n%s" code err ;
        let db = temp_db "effects_go" in
        if Sys.file_exists db then Sys.remove db ;
        let code, out = run_command ~stdin:ndjson (arch_load ()) [db] in
        if code <> 0 then Test.fail "arch-load rejected the Go stream (exit %d):\n%s" code out ;
        apply_migration db ;
        let code, eff_ndjson, err = run_command_split eff [pattern] in
        if code <> 0 then Test.fail "arch-effects-go failed (exit %d):\n%s" code err ;
        let code, out = run_command ~stdin:eff_ndjson (effects_load ()) [db] in
        if code <> 0 then Test.fail "loading the Go effects failed (exit %d):\n%s" code out ;
        Batch.run (fun b ->
            (* Each pair asserts BOTH directions. Positives alone are satisfied
               by a query that ignores its KIND argument and returns every
               mutator — proved by mutating the `value_kind = ?` predicate to
               `value_kind = ? OR 1`, which left the file green. Since each
               fixture function mutates exactly one kind, the other three kinds
               must NOT list it, and that is what pins the argument. *)
            let mutator_kinds =
              [
                ("HashTbl", "mapMutator");
                ("FieldAccess", "fieldMutator");
                ("ArrayElem", "arrayMutator");
                ("IoSideEffect", "ioFn");
              ]
            in
            List.iter
              (fun (kind, fn) ->
                let out = query db ["mutators-of"; kind] in
                Batch.contains b
                  ~msg:(Printf.sprintf "%s must be a %s mutator" fn kind)
                  ~haystack:out fn ;
                (* Exclusions on the DIRECT rows only. The Go SSA extractor
                   reports transitive candidates across the whole stdlib, so
                   "mutators-of X does not mention Y" is false for almost every
                   pair and says nothing about the kind argument. The direct
                   rows are the extractor's own claim, and they are exclusive
                   here — except ioFn, which genuinely writes an array element
                   (fmt.Println takes a []any), so it is excluded from the
                   exclusions rather than asserted away. *)
                let direct = List.filter (contains ~needle:"|direct|") (lines out) in
                List.iter
                  (fun (other_kind, other_fn) ->
                    if other_kind <> kind && other_fn <> "ioFn" then
                      Batch.check b
                        ~msg:
                          (Printf.sprintf
                             "mutators-of %s must not report %s as a DIRECT mutator — it \
                              mutates %s, and the query must honour its kind argument"
                             kind other_fn other_kind)
                        (not (List.exists (contains ~needle:other_fn) direct)))
                  mutator_kinds)
              mutator_kinds ;
            let entry = discover db ~like:"entry" ~unlike:(Some "main") in
            let eff_out = query db ["effects-of"; entry] in
            List.iter
              (fun kind ->
                Batch.contains b
                  ~msg:(Printf.sprintf "effects-of %s must reach %s" entry kind)
                  ~haystack:eff_out kind)
              ["HashTbl"; "FieldAccess"; "ArrayElem"] ;
            (* Both directions, against an EXPLICIT root.

               The default is `--roots exported`, and every function in this Go
               fixture is lowercase — unexported — so the default root set is
               empty and every function comes back dead. The positive assertion
               alone passed on exactly that, i.e. for the opposite of the stated
               reason. Naming the root makes the report discriminate, and the
               negatives below are what prove it: a `dead-code` that lists code
               reachable from its own root is worse than none. *)
            (let root = "efxtest.entry" in
             let dead = query db ["dead-code"; "--roots"; root] in
             Batch.contains b ~msg:"islandFn must be reported dead" ~haystack:dead "islandFn" ;
             List.iter
               (fun live ->
                 Batch.not_contains b
                   ~msg:
                     (Printf.sprintf "dead-code --roots %s must not list %s, which it reaches"
                        root live)
                   ~haystack:dead live)
               ["mapMutator"; "fieldMutator"; "arrayMutator"] ;
             (* And a root that matches nothing must REFUSE, not report the
                whole index as dead — the failure mode the flag's silence
                produced for as long as it went unparsed. *)
             Batch.exit_code b
               ~msg:"dead-code with an unmatched root must exit 2, not declare everything dead"
               ~expected:2
               (query_raw db ["dead-code"; "--roots"; "efxtest.no_such_function"])) ;
            (* pure-fns has the same shape: declaring every function pure passes
               a positive-only check, and "pure" is a claim consumers act on. *)
            (let pure = query db ["pure-fns"] in
             Batch.contains b ~msg:"pureFn must be reported pure" ~haystack:pure "pureFn" ;
             List.iter
               (fun impure ->
                 Batch.not_contains b
                   ~msg:(Printf.sprintf "pure-fns must not list %s, a known mutator" impure)
                   ~haystack:pure impure)
               ["mapMutator"; "fieldMutator"; "arrayMutator"; "ioFn"]) ;
            Db.with_db db (fun conn ->
                (* Absence, asserted as a NUMBER: an empty capture defaulted to
                   zero is how a query that failed to run reads as a pass. *)
                Assert.kinds_valid b conn ~label:"Go effects"))) ;
  Lwt.return_unit

(* The Rust MIR extractor does not exist yet, so this loads hand-crafted NDJSON
   representing what it would emit. What is under test is the CONTRACT — that a
   producer can supply effects for a language with no extractor, and that its
   claims are carried at the soundness level it declared. *)
let register_rust_contract () =
  Test.register ~__FILE__ ~title:"effects: a producer with no extractor still satisfies the contract"
    ~tags:["effects"; "rust"; "contract"]
  @@ fun () ->
  let db =
    Fixture.raw ~name:"effects_rust"
      {|
CREATE TABLE IF NOT EXISTS functions (id INTEGER PRIMARY KEY, name TEXT, file_path TEXT, exported INTEGER DEFAULT 0);
INSERT INTO functions(name, file_path, exported) VALUES
  ('my_crate::mutator', 'src/lib.rs', 1),
  ('my_crate::pure',    'src/lib.rs', 1),
  ('my_crate::island',  'src/lib.rs', 0);
CREATE TABLE IF NOT EXISTS calls (caller_name TEXT, callee_name TEXT, kind TEXT);
INSERT INTO calls VALUES ('my_crate::mutator', 'my_crate::pure', 'MUST');
CREATE TABLE IF NOT EXISTS comment_db_meta(key TEXT PRIMARY KEY, value TEXT);
INSERT INTO comment_db_meta VALUES ('callgraph_contract', 'v1');
|}
  in
  apply_migration db ;
  let code, out =
    run_command
      ~stdin:
        {|{"type":"effect","function_name":"my_crate::mutator","file_path":"src/lib.rs","value_kind":"HeapRef","soundness":"candidate","producer":"test-rust-stub"}
|}
      (effects_load ()) [db; "--migration"; migration ()]
  in
  if code <> 0 then Test.fail "loading the Rust stub effects failed (exit %d):\n%s" code out ;
  Batch.run (fun b ->
      Batch.contains b ~msg:"the declared mutator must be found by its value kind"
        ~haystack:(query db ["mutators-of"; "HeapRef"]) "mutator" ;
      (let dead = query db ["dead-code"] in
       Batch.contains b ~msg:"a function nothing reaches must be reported dead"
         ~haystack:dead "island" ;
       Batch.not_contains b
         ~msg:"dead-code must not list the declared mutator, which the entry point reaches"
         ~haystack:dead "mutator") ;
      (let pure = query db ["pure-fns"] in
       Batch.contains b ~msg:"a function with no declared effects must be pure"
         ~haystack:pure "pure" ;
       Batch.not_contains b
         ~msg:"pure-fns must not list the declared mutator"
         ~haystack:pure "mutator")) ;
  Lwt.return_unit
