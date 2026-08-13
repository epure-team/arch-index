(******************************************************************************)
(*                                                                            *)
(* Copyright (c) 2026 Epure Team                                              *)
(* All rights reserved.                                                       *)
(*                                                                            *)
(******************************************************************************)

(** The OCaml CMT producer, on three fixtures each aimed at a different way the
    analysis can lie.

    The first is the happy shape: a closure of direct top-level applications has
    no ⊤ in it, so UNREACHABLE there is a proof; add one call through a function
    PARAMETER and every question about that closure becomes UNKNOWN.

    The second is the soundness corpus — a parameter shadowing a top-level name,
    a function-typed value, a cross-module chain, a callback passed to an
    external higher-order function. Each of these was once resolved to the wrong
    thing, and each wrong resolution produced a confident answer.

    The third separates DEFERRED from DEAD. The lowering gives deferred code — a
    lazy thunk, an object method, a functor body, an optional-argument default —
    a CFG block with no incoming edge, which is exactly what stops those calls
    being MUST. But "unreachable from this entry" and "can never run" are
    different questions, and dead_code_sites answers the second: its only use is
    telling someone to delete code. Reading the first as the second reported
    every optional-argument default in the project as dead. The self-index
    golden cannot catch that — it counts modules, functions and calls, and
    dead_code_sites is 0 there either way. *)

open Arch_tezt

(* The producer's names are module-qualified; the test discovers them rather
   than hard-coding a mangling that belongs to the producer. A name that does
   not resolve is fatal: every verdict below would otherwise be asked about a
   function that does not exist. *)
let discover db ~like =
  Db.with_db db (fun conn ->
      match
        Db.string_opt conn
          (Printf.sprintf "SELECT name FROM functions WHERE name LIKE '%%%s%%' LIMIT 1" like)
      with
      | Some n -> n
      | None -> Test.fail "the producer emitted no function matching %S" like)

let register_kinds () =
  Test.register ~__FILE__ ~title:"cmt: a closure with no ⊤ proves, one with a ⊤ does not"
    ~tags:["cmt"; "callgraph"]
  @@ fun () ->
  with_fixture ~name:"cgo_kinds"
    ~files:
      [
        ("dune-project", "(lang dune 3.0)\n");
        ("dune", "(library\n (name testcg)\n (modules testcg))\n");
        ("testcg.ml", {|(* Controlled test module for arch_callgraph_ocaml selftest.
   NO higher-order calls in clean_entry's closure (no lambdas passed to stdlib);
   only direct top-level function applications → all MUST, no MAY_TOP.
   dirty_entry's closure contains apply_fn which has MAY_TOP (function parameter call). *)

let add (x : int) (y : int) : int = x + y
let mul (x : int) (y : int) : int = x * y
let island () : int = 99

(** All calls in the closure of direct_calc and clean_entry are MUST:
    only top-level locally-defined functions (add, mul) and no higher-order args. *)
let direct_calc (n : int) : int = add n 1
let clean_entry (n : int) : int = add (direct_calc n) (mul 2 n)

(** apply_fn takes a function parameter f — at the call site f x,
    f is a Pident not in local_fns → MAY_TOP emitted. *)
let apply_fn (f : int -> int) (x : int) : int = f x

(** dirty_entry calls apply_fn (MUST, it's top-level), but apply_fn internally
    has a MAY_TOP edge (the parameter call) — so dirty_entry's closure reaches MAY_TOP. *)
let dirty_entry () : int = apply_fn (fun n -> n + 1) 42
|});
      ]
  @@ fun fixture ->
  let db = index fixture in
  let clean = discover db ~like:"clean_entry" in
  let dirty = discover db ~like:"dirty_entry" in
  let island = discover db ~like:"island" in
  let add = discover db ~like:"add" in
  Batch.run (fun b ->
      Db.with_db db (fun conn ->
          Assert.produced_functions b conn ~label:"OCaml" ;
          Assert.kinds_valid b conn ~label:"OCaml") ;

      (* reaches: MUST only. *)
      Batch.contains b ~msg:"clean_entry -> add is a MUST chain of direct applications"
        ~haystack:(query db ["reaches"; clean; add]) "PATH EXISTS (must-reach)" ;
      Batch.contains b ~msg:"clean_entry never reaches island by a MUST path"
        ~haystack:(query db ["reaches"; clean; island]) "no MUST path" ;

      (* unreachable: a closed cone proves, an escaping one does not. *)
      let clean_island = query db ["unreachable"; clean; island] in
      Batch.contains b ~msg:"clean_entry's closure holds no ⊤, so island is UNREACHABLE"
        ~haystack:clean_island "UNREACHABLE:" ;
      Batch.not_contains b ~msg:"UNREACHABLE and REACHABLE are different answers"
        ~haystack:clean_island "REACHABLE (may-reach)" ;
      let dirty_island = query db ["unreachable"; dirty; island] in
      Batch.contains b
        ~msg:"dirty_entry reaches apply_fn, which calls a PARAMETER, so island is UNKNOWN"
        ~haystack:dirty_island "UNKNOWN:" ;
      Batch.not_contains b ~msg:"a reachable ⊤ forbids claiming UNREACHABLE"
        ~haystack:dirty_island "UNREACHABLE: no" ;
      Batch.contains b ~msg:"clean_entry does reach add"
        ~haystack:(query db ["unreachable"; clean; add]) "REACHABLE (may-reach)" ;

      (* escapes: present where a ⊤ is, empty where none is. *)
      Batch.ge_int b ~msg:"escapes dirty_entry must list the escaping function"
        (List.length (lines (query db ["escapes"; dirty])))
        1 ;
      Batch.eq_int b ~msg:"escapes clean_entry must be empty — no ⊤ in its closure"
        (List.length (lines (query db ["escapes"; clean])))
        0) ;
  Lwt.return_unit

let register_soundness () =
  Test.register ~__FILE__ ~title:"cmt: shadows, function values and callbacks resolve honestly"
    ~tags:["cmt"; "callgraph"; "soundness"]
  @@ fun () ->
  with_fixture ~name:"cgo_snd"
    ~files:
      [
        ("dune-project", "(lang dune 3.0)\n");
        ("dune", "(library (name snd) (modules efa crossb))\n");
        ("crossb.ml", {|let sink (x : int) : int = x
let direct (x : int) : int = sink (x + 5)
let mid (f : int -> int) (x : int) : int = f x
|});
        ("efa.ml", {|let target (x : int) : int = x + 1
let island (x : int) : int = x + 2
let entry_direct (x : int) : int = Crossb.direct x
let entry_unknown (x : int) : int = Crossb.mid (fun y -> y) x
let call_param (target : int -> int) (x : int) : int = target x
let chosen : int -> int = if Array.length Sys.argv > 0 then target else island
let entry_val (x : int) : int = chosen x
let entry_hof (xs : int list) : int list = List.map island xs
let entry_hof_param (g : int -> int) (xs : int list) : int list = List.map g xs
|});
      ]
  @@ fun fixture ->
  let db = index fixture in
  Batch.run (fun b ->
      Db.with_db db (fun conn ->
          Batch.eq_string_opt b ~msg:"a non-empty index must carry the contract flag"
            (Db.string_opt conn
               "SELECT value FROM comment_db_meta WHERE key='callgraph_contract'")
            (Some "v1")) ;

      (* A parameter that SHADOWS a top-level function is not that function.
         Resolution is by Ident stamp, so a shadow cannot forge a MUST. *)
      Batch.contains b
        ~msg:"applying a parameter that shadows a top-level name is not a MUST edge"
        ~haystack:(query db ["reaches"; "call_param"; "target"]) "no MUST path" ;
      Batch.contains b ~msg:"a parameter call is ⊤, so the closure is UNKNOWN"
        ~haystack:(query db ["unreachable"; "call_param"; "island"]) "UNKNOWN" ;

      (* A function-typed VALUE has no single callee. *)
      Batch.contains b ~msg:"calling a function-typed value is ⊤, so UNKNOWN"
        ~haystack:(query db ["unreachable"; "entry_val"; "island"]) "UNKNOWN" ;

      (* Cross-module: the MUST chain is followed, and a ⊤ inside a cross-module
         callee still surfaces at the caller. *)
      Batch.contains b ~msg:"a cross-module MUST chain is followed"
        ~haystack:(query db ["reaches"; "entry_direct"; "sink"]) "PATH EXISTS" ;
      Batch.contains b ~msg:"a ⊤ inside a cross-module callee surfaces at the caller"
        ~haystack:(query db ["unreachable"; "entry_unknown"; "sink"]) "UNKNOWN" ;
      Batch.contains b ~msg:"a pure MUST-only chain still yields a sound negative"
        ~haystack:(query db ["unreachable"; "entry_direct"; "island"]) "UNREACHABLE" ;

      (* An unknown root is refused, never answered. *)
      Batch.exit_code b ~msg:"an unknown root must REFUSE, never answer UNREACHABLE" ~expected:3
        (query_raw db ["unreachable"; "no_such_fn"; "also_missing"]) ;

      (* A named local function passed to an external higher-order call escapes
         as a callback: reachable, but never a MUST path. *)
      Batch.contains b ~msg:"a named callback passed to List.map is REACHABLE"
        ~haystack:(query db ["unreachable"; "entry_hof"; "island"]) "REACHABLE (may-reach)" ;
      Batch.contains b ~msg:"a callback is MAY_ENUMERATED, so never a MUST path"
        ~haystack:(query db ["reaches"; "entry_hof"; "island"]) "no MUST path" ;
      Batch.contains b ~msg:"a PARAMETER callback has an unknown target, so UNKNOWN"
        ~haystack:(query db ["unreachable"; "entry_hof_param"; "island"]) "UNKNOWN") ;
  Lwt.return_unit

let register_deferred_is_not_dead () =
  Test.register ~__FILE__ ~title:"cmt: deferred code is not dead code"
    ~tags:["cmt"; "dead_code"]
  @@ fun () ->
  with_fixture ~name:"cgo_defr"
    ~files:
      [
        ("dune-project", "(lang dune 3.0)\n");
        (* -w -a: truly_dead writes a statement after an unconditional raise,
           which is warning 21 and an error under dune's dev profile. Without
           this the module does not compile and every assertion here passes
           vacuously. *)
        ("dune", "(library (name defr) (modules defr) (flags (:standard -w -a)))\n");
        ("defr.ml", {|let in_default () = 1
let in_lazy () = 2
let in_method () = 3
let in_functor () = 4
let after_raise () = 5

(* DEFERRED, not dead: the default runs on every call that omits ?fmt. *)
let opt_default ?(fmt = in_default ()) (x : int) : int = fmt + x

(* DEFERRED, not dead: forced later. *)
let uses_lazy () : int =
  let l = lazy (in_lazy ()) in
  Lazy.force l

(* DEFERRED, not dead: invoked through the object. *)
let uses_object () : int =
  let o = object method go () = in_method () end in
  o#go ()

(* DEFERRED, not dead: runs on functor application. *)
let uses_functor () : int =
  let module Make (X : sig end) = struct let v = in_functor () end in
  let module M = Make (struct end) in
  M.v

(* GENUINELY dead: nothing can execute after a raise in the same block. *)
let truly_dead (x : int) : int =
  if x > 0 then failwith "boom" else failwith "bang" ;
  after_raise ()
|});
      ]
  @@ fun fixture ->
  let db = index fixture in
  Batch.run (fun b ->
      Db.with_db db (fun conn ->
          let dead =
            Db.strings conn "SELECT DISTINCT callee_name FROM dead_code_sites"
          in
          List.iter
            (fun callee ->
              (* Present in the index at all? Otherwise the assertion below is
                 vacuous and the fixture has stopped exercising the construct. *)
              Batch.ge_int b
                ~msg:
                  (Printf.sprintf
                     "no call edge to %s — the fixture stopped exercising this construct" callee)
                (Db.int conn
                   (Printf.sprintf "SELECT count(*) FROM calls WHERE callee_name='%s'" callee))
                1 ;
              Batch.check b
                ~msg:
                  (Printf.sprintf
                     "%s is DEFERRED, not dead — it runs on a later entry, so telling someone to \
                      delete it is wrong"
                     callee)
                (not (List.mem callee dead)))
            ["in_default"; "in_lazy"; "in_method"; "in_functor"] ;
          (* The counterweight: without it, "stop computing dead code at all"
             would pass everything above. *)
          Batch.check b
            ~msg:
              "after_raise follows an unconditional raise and must still be reported dead"
            (List.mem "after_raise" dead))) ;
  Lwt.return_unit

(* Cross-library homonyms: two libraries, each with an `api.ml`.

   The resolver mapped a qualified reference's module component to a source path
   through a table keyed by CAPITALISED BASENAME, built with [Hashtbl.replace] —
   one path per name, last writer wins. `Api` designated whichever `api.ml` was
   scanned last, so a MUST edge pointed at the wrong function: reachability
   forged toward the survivor, lost from every loser, verdict still `sound`.

   Two wrong answers were shipped before the right one, and this fixture is
   pinned against BOTH of them, because each is a different way to lie:

   - REFUSING to bind. An unresolved qualified callee is encoded bit-for-bit
     like an external leaf (`kind = MUST`, `callee_id = NULL`), so `arch-rules`
     answered `pass` and `unreachable` answered `sound` on a fixture whose
     source literally calls the forbidden function.
   - NARROWING by directory segment — reading `Sublib` in `Sublib.Api.run` as
     the directory `sublib/` and binding there with kind MUST. Dune laying a
     library out under a directory of its name is a convention, not a
     guarantee: a library `q` in `alt/` next to a library `qq` in `q/` makes
     the filter elect the wrong library and stamp it MUST. That is the original
     defect re-created by its own fix, so the heuristic is gone.

   What is asserted instead is the CANDIDATE SET: one MAY_ENUMERATED row per
   module the name could designate. It costs precision here — this is a layout
   where the directory heuristic happened to be right, and `reaches` can no
   longer prove the path — but the set is guaranteed to CONTAIN the true target,
   and no member of it is ever claimed as a proof.

   Four cases, because they fail independently:
   - `entry` and `entry2` (both ways round: a resolver that always picks the
     same library passes either one alone, and which one it picks depends on
     directory traversal order, so a single direction is half inert);
   - `X.B.f` regresses if an ambiguous OUTER component aborts the walk instead
     of letting a deeper, unique component decide — and it is also what keeps
     the rest non-vacuous, since a resolver that enumerated everything would
     still pass the two above;
   - the type usage exercises a third copy of the same collapse, which resolved
     `Api.t` in one library to the other library's `t`. A type usage has one FK
     and no candidate-set kind, so the honest answer there is NULL. *)
let homonym_libs =
  [
    ("dune-project", "(lang dune 3.0)\n");
    ("rootlib/dune", "(library (name rootlib) (libraries sublib))\n");
    ("rootlib/api.ml", "type t = int\nlet run (x : int) : int = x + 1\n");
    ( "rootlib/caller.ml",
      "let entry (h : (string, int) Hashtbl.t) = Sublib.Api.run h\n\
       let entry2 (x : int) : int = Api.run x\n\
       let use_t (v : Api.t) : int = v\n" );
    (* The same ambiguity on the module-deps path, which is a SEPARATE resolver
       and regressed on its own after the call path was fixed: an unresolved dep
       degrades to its dotted string, so a path-shaped `forbid dep` selector
       stops matching and the rule goes green on a file that says `open`. *)
    ( "rootlib/opener.ml",
      "open Sublib.Api\n\nlet via_open (h : (string, int) Hashtbl.t) = run h\n" );
    ("sublib/dune", "(library (name sublib))\n");
    ("sublib/api.ml",
     "type t = string\nlet run (h : (string, int) Hashtbl.t) = Hashtbl.replace h \"k\" 1\n");
    (* `X` is ambiguous (two x.ml) but `B` is unique: an outer ambiguity must not
       abort the walk before the component that actually decides. *)
    ("p/dune", "(library (name p))\n");
    ("p/x.ml", "let z = 1\n");
    ("q/dune", "(library (name q))\n");
    ("q/x.ml", "let z = 2\n");
    ("xlib/dune", "(library (name x))\n");
    ("xlib/b.ml", "let f (n : int) : int = n + 1\n");
    ("cl/dune", "(library (name cl) (libraries x))\n");
    ("cl/caller.ml", "let deep (n : int) : int = X.B.f n\n");
  ]

let register_cross_library_homonyms () =
  Test.register ~__FILE__
    ~title:"cmt: a name shared by two libraries binds to the candidate set, never to one guess"
    ~tags:["cmt"; "resolve"; "homonym"]
  @@ fun () ->
  with_fixture ~name:"homonym_libs" ~files:homonym_libs @@ fun fixture ->
  let db = index fixture in
  Db.with_db db (fun conn ->
      let fn_id ~name ~path =
        match
          Db.int_opt conn
            (Printf.sprintf
               "SELECT f.id FROM functions f JOIN modules m ON f.module_id = m.id WHERE \
                f.name = '%s' AND m.path LIKE '%%%s'"
               name path)
        with
        | Some id -> id
        | None -> Test.fail "the fixture has no '%s' in %s" name path
      in
      let root_run = fn_id ~name:"run" ~path:"rootlib/api.ml" in
      let sub_run = fn_id ~name:"run" ~path:"sublib/api.ml" in
      (* COALESCE, not int_opt alone: the row EXISTS with a NULL callee_id when
         the resolver declines, and "no row" and "row with NULL" are different
         facts that must not both read as None. *)
      (* group_concat, not a scalar read: an ambiguous binding emits SEVERAL
         rows for one call site, and a scalar reader fails hard on the extra row
         — a caught failure, but reported as "expected at most one row" instead
         of naming what bound where. This reads the whole set as text so both
         the resolved case and the enumerated case produce a legible message. *)
      (* Sorted, so the expectation is a stable string rather than one that
         depends on the order sqlite happens to aggregate rows in. Reading the
         whole set as text also means a wrong answer names what bound where,
         instead of a scalar reader failing with "expected at most one row". *)
      let callees ~caller ~like =
        match
          Db.string_opt conn
            (Printf.sprintf
               "SELECT group_concat(id, ',') FROM (SELECT DISTINCT COALESCE(c.callee_id, -1) \
                AS id FROM calls c JOIN functions f ON c.caller_id = f.id WHERE f.name = '%s' \
                AND c.callee_name LIKE '%s' ORDER BY id)"
               caller like)
        with
        | None | Some "" ->
            Test.fail "the fixture recorded no call from %s matching %s" caller like
        | Some s -> s
      in
      let kinds ~caller ~like =
        match
          Db.string_opt conn
            (Printf.sprintf
               "SELECT group_concat(k, ',') FROM (SELECT DISTINCT COALESCE(c.kind, 'NULL') AS \
                k FROM calls c JOIN functions f ON c.caller_id = f.id WHERE f.name = '%s' AND \
                c.callee_name LIKE '%s' ORDER BY k)"
               caller like)
        with
        | None | Some "" -> Test.fail "no call from %s matching %s" caller like
        | Some s -> s
      in
      let set = String.concat "," (List.sort compare [root_run; sub_run] |> List.map string_of_int) in
      Batch.run (fun b ->
          Batch.check b
            ~msg:"the fixture must produce TWO distinct 'run' functions, one per library"
            (root_run <> sub_run) ;
          (* Both directions, and the same expected SET both times — which is
             the point: the resolver cannot tell them apart, and the assertion
             says so rather than pretending it can. What each direction pins is
             that its own true target is IN the set. *)
          Batch.eq_string b
            ~msg:
              "entry calls Sublib.Api.run: the candidate set must be both runs, so it contains \
               SUBLIB's (-1 = declined, which is encoded like an external leaf)"
            (callees ~caller:"entry" ~like:"%Api.run")
            set ;
          Batch.eq_string b
            ~msg:
              "entry2 calls Api.run from inside rootlib: the same set, so it contains ROOTLIB's"
            (callees ~caller:"entry2" ~like:"%Api.run")
            set ;
          (* The kind is what stops the set being read as a proof. Two ids under
             kind MUST would be strictly worse than the bug being fixed: two
             forged must-paths instead of one. *)
          List.iter
            (fun caller ->
              Batch.eq_string b
                ~msg:
                  (Printf.sprintf
                     "every edge of %s's candidate set must be MAY_ENUMERATED — a MUST here \
                      would be a forged proof"
                     caller)
                (kinds ~caller ~like:"%Api.run")
                "MAY_ENUMERATED")
            ["entry"; "entry2"] ;
          (* An ambiguous OUTER component must not abort the walk: `X` is two
             modules, `B` is one, and the answer is decided by `B`. This is also
             the non-vacuity guard for everything above — a resolver that simply
             enumerated every homonym, or refused on any ambiguity at all, would
             satisfy the candidate-set assertions and fail here. *)
          Batch.eq_string b
            ~msg:"an ambiguous outer component must not lose a deeper unique resolution"
            (callees ~caller:"deep" ~like:"%B.f")
            (string_of_int (fn_id ~name:"f" ~path:"xlib/b.ml")) ;
          Batch.eq_string b
            ~msg:"and that unique resolution must still be a MUST edge, not a demoted one"
            (kinds ~caller:"deep" ~like:"%B.f")
            "MUST" ;
          (* The third copy of the collapse: same key, same last-writer-wins,
             in type-usage resolution. Both api.ml define a `t`, so both are
             candidates — and type_usage has a single FK with no enumerated
             kind, so the answer is NULL. Asserted against the ROOT id rather
             than just "not sub": binding to either one would be a guess, and
             the one that looks right here is right by coincidence of layout. *)
          let type_id ~path =
            match
              Db.int_opt conn
                (Printf.sprintf
                   "SELECT t.id FROM types t JOIN modules m ON t.module_id = m.id WHERE t.name \
                    = 't' AND m.path LIKE '%%%s'"
                   path)
            with
            | Some id -> id
            | None -> Test.fail "the fixture has no type 't' in %s" path
          in
          Batch.check b
            ~msg:"the fixture must produce TWO distinct types named 't', one per library"
            (type_id ~path:"rootlib/api.ml" <> type_id ~path:"sublib/api.ml") ;
          Batch.eq_int_opt b
            ~msg:
              "a type written Api.t where two modules define one must stay unresolved (-1), \
               not pick a homonym"
            (Db.int_opt conn
               "SELECT COALESCE(type_id, -1) FROM type_usage WHERE type_name LIKE '%Api.t'")
            (Some (-1)) ;
          (* Module deps are resolved by their own code path, and that path kept
             the refusal for a round after the call path had dropped it. Asserted
             on the TARGET PATHS rather than a row count: a count of 2 is also
             what "resolved to the same module twice" produces, and one of those
             two must be sublib's — the module the file actually opens. *)
          Batch.eq_string_opt b
            ~msg:
              "`open Sublib.Api` must record one dep row per candidate module, sublib's among \
               them — not one NULL row, which reads exactly like an external dependency"
            (Db.string_opt conn
               "SELECT group_concat(p, ',') FROM (SELECT DISTINCT COALESCE((SELECT path FROM \
                modules WHERE id = d.target_module), 'NULL') AS p FROM module_deps d WHERE \
                d.target_path = 'Sublib.Api' ORDER BY p)")
            (Some "rootlib/api.ml,sublib/api.ml")) ;
      (* The end-to-end consequence, which is the whole reason the kind matters.
         With the pre-fix resolver both of these lied: `reaches` proved a
         must-path to whichever `run` won the last write, and on the losing side
         `unreachable` said UNREACHABLE about a function the source calls. *)
      Batch.run (fun b ->
          Batch.contains b
            ~msg:"a candidate set must not be walkable as a proof — reaches must decline"
            ~haystack:(query db ["reaches"; "entry"; "run"])
            "no MUST path" ;
          Batch.contains b
            ~msg:
              "but the target must stay in the may-closure: UNREACHABLE here would be the \
               original forged verdict"
            ~haystack:(query db ["unreachable"; "entry"; "run"])
            "REACHABLE (may-reach)")) ;
  Lwt.return_unit
