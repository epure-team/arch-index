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
    ("dune", "(library (name efxtest) (modules efxtest efxdeep efxtwin))\n");
    (* A SECOND module, so the effect closures have a boundary to cross. The
       fixture was single-module, which is why three closures that stopped at
       every module boundary went unnoticed. *)
    ("efxdeep.ml", {|let deep_mutator (h : (string, int) Hashtbl.t) = Hashtbl.replace h "deep" 1
|});
    (* The HOMONYM of the mutator: same short name, different module, PURE. A
       review proved the closures, once they crossed module boundaries, matched
       members by NAME on arrival — so calling THIS function read as reaching
       efxdeep's mutation, effects-of invented an effect and mutators-of a
       transitive mutator. The pair is what makes name-conflation observable. *)
    ("efxtwin.ml", {|let deep_mutator (h : (string, int) Hashtbl.t) : int = Hashtbl.length h
|});
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

(* Mutates nothing itself, and its only callee lives in ANOTHER module. *)
let cross_entry (h : (string, int) Hashtbl.t) = Efxdeep.deep_mutator h

(* Calls ONLY the pure twin — the function whose name matches the mutator. *)
let twin_caller (h : (string, int) Hashtbl.t) : int = Efxtwin.deep_mutator h
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

      (* Across a MODULE boundary, in all three directions.

         Every closure here used to hop by joining a callee NAME against a
         function NAME. A caller records its callee as dune spells it
         (`Efxdeep.deep_mutator`) while that function's own name is
         `deep_mutator`, so the join failed and each query stopped at the
         boundary: `effects-of` returned nothing, `mutators-of` lost the
         transitive caller, and `pure-fns` called an impure function pure.
         Nothing covered this because the fixture had a single module. *)
      (let cross = discover db ~like:"cross_entry" ~unlike:None in
       Batch.contains b
         ~msg:"effects-of must cross the module boundary to reach Efxdeep.deep_mutator"
         ~haystack:(query db ["effects-of"; cross]) "deep_mutator" ;
       Batch.contains b
         ~msg:"mutators-of must list the cross-module caller as a transitive mutator"
         ~haystack:(query db ["mutators-of"; "HashTbl"]) cross ;
       (* The one that matters most: "pure" is a claim consumers act on. *)
       Batch.not_contains b
         ~msg:
           "pure-fns must not call cross_entry pure — it reaches a HashTbl mutation one module \
            away"
         ~haystack:(query db ["pure-fns"]) cross) ;

      (* The homonym, in both directions the review proved broken: calling the
         PURE twin of a mutator must not read as reaching the mutation. *)
      (let twin = discover db ~like:"twin_caller" ~unlike:None in
       Batch.eq_int b
         ~msg:
           "effects-of twin_caller must be EMPTY — its only callee is the pure twin, and \
            attributing efxdeep's mutation to it is name-conflation"
         (List.length (lines (query db ["effects-of"; twin])))
         0 ;
       Batch.not_contains b
         ~msg:"mutators-of must not list twin_caller — it reaches no mutation"
         ~haystack:(query db ["mutators-of"; "HashTbl"]) twin) ;
      (* Anti-stub: a closure that answers every question with everything —
         `ON 1=1` in the transitive step — satisfies purely positive
         assertions. island_fn calls nothing and mutates nothing: any output
         listing it is inventing. *)
      Batch.not_contains b
        ~msg:"mutators-of must not list island_fn, which calls and mutates nothing"
        ~haystack:(query db ["mutators-of"; "HashTbl"]) "island_fn" ;
      Batch.eq_int b
        ~msg:"effects-of island_fn must be EMPTY — it calls nothing"
        (List.length (lines (query db ["effects-of"; "island_fn"])))
        0 ;

      Batch.contains b ~msg:"a function with no effects must be listed pure"
        ~haystack:(query db ["pure-fns"]) "pure_fn" ;
      (* Rooted EXPLICITLY. The bare `dead-code` call this replaces passed for
         the wrong reason: this fixture has no .mli, nothing is exposed, the
         default root set was empty and EVERY function came back dead — the
         assertion could not fail. The guard that now refuses that invocation
         is itself under test here. *)
      Batch.exit_code b
        ~msg:
          "dead-code with no roots on an index with nothing exposed must refuse — an empty \
           root set reports the whole index as deletable"
        ~expected:2
        (query_raw db ["dead-code"]) ;
      (let entry = discover db ~like:"exported_entry" ~unlike:None in
       let dead = query db ["dead-code"; "--roots"; entry] in
       Batch.contains b ~msg:"a function nothing calls must be reported dead" ~haystack:dead
         "island_fn" ;
       Batch.not_contains b
         ~msg:"dead-code must not list record_mutator, which exported_entry calls"
         ~haystack:dead "record_mutator")) ;
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
          (* [-buildvcs=false]: see the detailed comment on the equivalent build in
             callgraph_go.ml — Go silently omits VCS stamping in a git worktree (no
             [vcs] lines in [go version -m]) rather than erroring; verified on
             go1.26.4, no build failure reproduced in a worktree with or without this
             flag. Kept anyway: costs nothing, and guards toolchains/configurations
             where the VCS lookup IS fatal (e.g. a [safe.directory] refusal). *)
          let code, output = run_command ~cwd:dir "go" ["build"; "-buildvcs=false"; "-o"; out; "."] in
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

(* The endpoint mapping between [function_effects] (name + path, no id) and
   [functions] (id-keyed), on a HAND-BUILT main-schema index — no producer
   involved, because what is under test is the query layer's resolution rule,
   and the CMT resolver has homonym defects of its own that would pollute an
   end-to-end fixture.

   Three findings of an adversarial review, each pinned in both directions:
   - basename collision: `run` in `api.ml` (pure) vs `run` in `src/api.ml`
     (mutator), effect recorded under the build-dir path. The suffix match must
     prefer the LONGEST path, or the shallow homonym takes the row and calling
     the pure twin reads as reaching the mutation.
   - LIKE wildcards in data: `_` matches `/`, so `foo_bar.ml` matched an effect
     recorded in `foo/bar.ml`. The comparison must be substr arithmetic.
   - ghost effects: a fe row whose function has no [functions] row (producer
     data the loader does not FK-check) must still be listed as a direct
     mutator, not silently dropped by the id join. *)
let register_endpoint_ambiguity () =
  Test.register ~__FILE__
    ~title:"effects: name+path endpoints resolve to the right id, or to all, never to a wrong one"
    ~tags:["effects"; "query"; "homonym"]
  @@ fun () ->
  let db =
    Fixture.raw ~name:"effects_endpoints"
      {|
CREATE TABLE comment_db_meta(key TEXT, value TEXT);
INSERT INTO comment_db_meta VALUES('callgraph_contract','v1');
CREATE TABLE modules(id INTEGER PRIMARY KEY, name TEXT, path TEXT);
CREATE TABLE functions(id INTEGER PRIMARY KEY, module_id INT, name TEXT, exposed INT, line_start INT, line_end INT);
CREATE TABLE calls(id INTEGER PRIMARY KEY, caller_id INT, callee_id INT, callee_name TEXT, call_site TEXT, kind TEXT);
INSERT INTO modules VALUES (1,'api','api.ml'),(2,'api2','src/api.ml'),(3,'m3','m3.ml'),(4,'fb','foo_bar.ml'),(5,'fbr','foo/bar.ml');
INSERT INTO functions VALUES
 (1,1,'run',0,1,2),(2,2,'run',0,1,2),
 (3,3,'caller',0,1,2),(4,3,'purecaller',0,3,4),
 (5,4,'wild',0,1,2),(6,3,'wildcaller',0,5,6),(7,5,'wild',0,1,2),(8,3,'realcaller',0,7,8);
INSERT INTO calls VALUES
 (1,3,2,'Api.run','m3.ml:1','MUST'),
 (2,4,1,'Api.run','m3.ml:3','MUST'),
 (3,6,5,'Fb.wild','m3.ml:5','MUST'),
 (4,8,7,'Fbr.wild','m3.ml:7','MUST');
|}
  in
  apply_migration db ;
  Db.with_db_rw db (fun conn ->
      Db.exec conn
        {|INSERT INTO function_effects (function_name, file_path, value_kind, target, is_direct, soundness) VALUES
 ('run','default/src/.s.objs/byte/src/api.ml','HashTbl','tbl',1,'sound'),
 ('wild','default/.l.objs/byte/foo/bar.ml','HashTbl','t',1,'sound'),
 ('ghost_mut','gm.ml','HashTbl','g',1,'sound');|}) ;
  Batch.run (fun b ->
      Batch.contains b
        ~msg:"caller reaches the src/api.ml mutator by id: its effect must be reported"
        ~haystack:(query db ["effects-of"; "caller"]) "HashTbl" ;
      Batch.eq_int b
        ~msg:
          "purecaller reaches only api.ml's pure run: attributing src/api.ml's effect to it \
           is a basename conflation (the longest-path preference is what prevents it)"
        (List.length (lines (query db ["effects-of"; "purecaller"])))
        0 ;
      Batch.eq_int b
        ~msg:
          "wildcaller reaches only foo_bar.ml's wild: matching it against foo/bar.ml's effect \
           needs `_` to match `/`, i.e. LIKE with data as the pattern"
        (List.length (lines (query db ["effects-of"; "wildcaller"])))
        0 ;
      Batch.contains b
        ~msg:"realcaller reaches foo/bar.ml's wild: the true attribution must survive"
        ~haystack:(query db ["effects-of"; "realcaller"]) "HashTbl" ;
      (let muts = query db ["mutators-of"; "HashTbl"] in
       (* Line-ANCHORED, not a substring: the bare needle "caller" matches
          realcaller/wildcaller/purecaller, and even "caller|" is still a
          substring of "realcaller|" — the review that flagged the weak needle
          proposed that spelling, and it is weak too. Only a line PREFIX pins
          this row. *)
       Batch.check b ~msg:"caller must be listed as a transitive HashTbl mutator"
         (List.exists (has_prefix ~prefix:"caller|") (lines muts)) ;
       Batch.not_contains b
         ~msg:"purecaller must not be listed — its callee mutates nothing" ~haystack:muts
         "purecaller" ;
       Batch.not_contains b
         ~msg:"wildcaller must not be listed — the `_`/`/` conflation invented its path"
         ~haystack:muts "wildcaller" ;
       Batch.contains b
         ~msg:
           "an effect row with NO functions row is producer data, not noise: it must be \
            listed as a direct mutator, not dropped by the id join"
         ~haystack:muts "ghost_mut")) ;
  (* The FLAT root universe, refused and accepted at its exact boundary: a
     CALLER without a functions row is a legitimate root (it has outgoing
     edges); a CALLEE-only name has none, so rooting there makes the cone
     itself and every function comes back dead — the report the guard exists
     to refuse. `*TOP*` is the sentinel spelling of the same trap. *)
  let flat =
    Fixture.raw ~name:"effects_flat_roots"
      {|
CREATE TABLE comment_db_meta(key TEXT, value TEXT);
CREATE TABLE functions(name TEXT, file_path TEXT, exported INT);
INSERT INTO functions VALUES ('a','x',0),('b','x',0),('island','x',0);
CREATE TABLE calls(caller_name TEXT, caller_file TEXT, callee_name TEXT, callee_file TEXT, call_site TEXT, kind TEXT);
INSERT INTO calls VALUES
 ('entry','x','a','x','x:1','MUST'),
 ('a','x','b','x','x:2','MUST'),
 ('b','x','*TOP*',NULL,'x:3','MAY_TOP'),
 ('a','x','fmt.Println',NULL,'x:4','MUST');
|}
  in
  Batch.run (fun b ->
      Batch.exit_code b
        ~msg:"rooting at the ⊤ sentinel must refuse — its cone is itself, everything else dead"
        ~expected:2
        (query_raw flat ["dead-code"; "--roots"; "*TOP*"]) ;
      Batch.exit_code b
        ~msg:"rooting at a callee-only external must refuse for the same reason" ~expected:2
        (query_raw flat ["dead-code"; "--roots"; "fmt.Println"]) ;
      (let code, out = query_raw flat ["dead-code"; "--roots"; "entry"] in
       Batch.eq_int b
         ~msg:"a caller-only root is legitimate on the flat schema (it has outgoing edges)" code
         0 ;
       Batch.contains b ~msg:"and the report discriminates: island is dead" ~haystack:out
         "island" ;
       Batch.not_contains b ~msg:"while b, reached through a, is not" ~haystack:out "b|")) ;
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
