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

(* Cross-library homonyms: several compilation units sharing a source basename.

   The resolver mapped a qualified reference's module component through a table
   keyed by CAPITALISED BASENAME, built with [Hashtbl.replace] — one path per
   name, last writer wins. Two libraries each holding an `api.ml` collapsed to
   one entry, so `Api` designated whichever was scanned last: a MUST edge
   pointing at the wrong function, reachability forged toward the survivor and
   lost from every loser, verdict still `sound`. The same collapse existed three
   times over — calls, module dependencies and type usages.

   Resolution now keys on the COMPILATION UNIT, taken from the .cmt filename:
   `rootlib__Api` and `sublib__Api` are distinct keys for the two `api.ml`.

   The fixture is built to refute the two wrong fixes that were tried before it,
   because each looks right on a simpler fixture:

   - REFUSING to bind. An unresolved callee is stored `kind = MUST,
     callee_id = NULL`, which is bit-for-bit an external leaf like `Stdlib.+`,
     so `arch-rules` answered `pass` and `unreachable` answered UNREACHABLE
     about a call the source plainly makes.
   - NARROWING by directory segment — reading `Sublib` as the directory
     `sublib/`. Library `x` here lives in `xlib/`, which is exactly the shape
     that breaks it: dune derives the object directory from the LIBRARY name,
     so the identity is in `xlib/.x.objs/byte/x__B.cmt` and not in the source
     layout. `deep` pins it.

   `inc/` is the case that decides the shape of the fix: `api.ml` is
   `include Base_api`, so the unit resolves but holds no row for `run`. That is
   NOT a reason to look elsewhere — falling back to the basename map there is
   how a reference to one library's `run` gets bound to another's. It must
   degrade, and it must degrade to ⊤ rather than to a NULL leaf, or the two
   verdicts above go quietly wrong. *)
let homonym_libs =
  [
    ("dune-project", "(lang dune 3.0)\n");
    ("rootlib/dune", "(library (name rootlib) (libraries sublib))\n");
    (* A hand-written library module makes dune emit the ALIAS module
       `Rootlib__` and compile every sibling with `-open Rootlib__`, so an
       intra-library reference roots at `Rootlib__` rather than `Rootlib`. This
       one file is what turns `entry2` and `use_t` below into a test of the
       alias root; without it the fixture never exercises the most ordinary
       library layout there is — the one this repository itself uses. A review
       added exactly this file to an earlier version and two assertions flipped
       to sublib. *)
    ("rootlib/rootlib.ml", "module Api = Api\nmodule Caller = Caller\nmodule Opener = Opener\n");
    ("rootlib/api.ml", "type t = int\nlet run (x : int) : int = x + 1\n");
    ( "rootlib/caller.ml",
      "let entry (h : (string, int) Hashtbl.t) = Sublib.Api.run h\n\
       let entry2 (x : int) : int = Api.run x\n\
       let use_t (v : Api.t) : int = v\n" );
    (* The dependency path is a SEPARATE resolver and regressed on its own after
       the call path was fixed: an unresolved dep degrades to its dotted string,
       so a path-shaped `forbid dep` selector stops matching and the rule goes
       green on a file that plainly says `open`. *)
    ( "rootlib/opener.ml",
      "open Sublib.Api\n\nlet via_open (h : (string, int) Hashtbl.t) = run h\n" );
    (* The type probe's mirror. One direction alone passes under a pure
       basename resolver whenever scan order happens to favour the asserted
       library — the same defect that made the first deps assertion inert, found
       for deps and not carried across to types. Two usages of two different
       units cannot both be right by luck. *)
    ("sublib/user.ml", "let use_t (v : Api.t) : int = String.length v\n");
    ("sublib/dune", "(library (name sublib))\n");
    ( "sublib/api.ml",
      "type t = string\nlet run (h : (string, int) Hashtbl.t) = Hashtbl.replace h \"k\" 1\n" );
    (* `X` is ambiguous (two x.ml) but `B` is unique: an outer ambiguity must not
       abort the walk before the component that actually decides. The library is
       `x` and the directory is `xlib` — deliberately different. *)
    ("p/dune", "(library (name p))\n");
    ("p/x.ml", "let z = 1\n");
    ("q/dune", "(library (name q))\n");
    ("q/x.ml", "let z = 2\n");
    ("xlib/dune", "(library (name x))\n");
    ("xlib/b.ml", "let f (n : int) : int = n + 1\n");
    ("cl/dune", "(library (name cl) (libraries x))\n");
    ("cl/caller.ml", "let deep (n : int) : int = X.B.f n\n");
    (* A SECOND `open`, of the other homonym. One alone proves nothing: the
       basename map resolves `Api` to whichever api.ml was scanned last, and on
       this fixture that happens to be sublib's — so an assertion on the sublib
       side alone passes under a resolver that ignores the unit entirely. Two
       opens of two different units cannot both be right by luck. *)
    ("dep2/dune", "(library (name dep2) (libraries rootlib))\n");
    ("dep2/opener2.ml", "open Rootlib.Api\n\nlet use_r (x : int) : int = run x\n");
    (* Two executables. Every `(executable (name main))` stanza mangles its
       modules to `dune__exe__<Module>`, so these two `util.ml` share a unit
       NAME while being different compilation units — the unit map is no more
       injective than the basename map was. Keeping one of them silently would
       reinstate the original defect on a different key, with a MUST edge from
       one program into another it never links. This repository has the
       collision for real (`dune__exe__Main` covers three modules). *)
    (* The caller is NOT the main module: an executable's own entry module
       compiles to `dune__exe`, not `dune__exe__Main`, so a call written there
       is not indexed and an assertion about it passes vacuously — which is
       exactly how the first version of this case failed to catch anything. *)
    ("e1/dune", "(executable (name main) (modules main util caller))\n");
    ("e1/util.ml", "let helper (n : int) : int = n + 1\n");
    ("e1/caller.ml", "let go (n : int) : int = Util.helper n\n");
    ("e1/main.ml", "let () = ignore (Caller.go 1)\n");
    ("e2/dune", "(executable (name main) (modules main util))\n");
    ("e2/util.ml", "let helper (n : int) : int = n - 1\n");
    ("e2/main.ml", "let () = ignore (Util.helper 1)\n");
    (* Re-export: the unit resolves, the name is not a row in it. *)
    ("inc/dune", "(library (name inc))\n");
    ("inc/base_api.ml", "let run (n : int) : int = n + 2\n");
    ("inc/api.ml", "include Base_api\n");
    ("icl/dune", "(library (name icl) (libraries inc))\n");
    ("icl/caller.ml", "let via_include (n : int) : int = Inc.Api.run n\n");
  ]

let register_cross_library_homonyms () =
  Test.register ~__FILE__
    ~title:"cmt: a qualified reference resolves by compilation unit, not by basename"
    ~tags:["cmt"; "resolve"; "homonym"]
  @@ fun () ->
  with_fixture ~name:"homonym_libs" ~files:homonym_libs @@ fun fixture ->
  let db = index fixture in
  Db.with_db db (fun conn ->
      (* Every probe reads a COUNT alongside the value it asserts. A scalar read
         cannot tell "bound to the right module" from "bound to the right module
         AND to a second one as well", and emitting a duplicate row is a real
         regression shape for a resolver that stopped being a single lookup. *)
      let binding ~caller ~like =
        let one q =
          match Db.string_opt conn q with Some s -> s | None -> "<no row>"
        in
        one
          (Printf.sprintf
             "SELECT count(*) || ' row(s) -> ' || COALESCE(group_concat(DISTINCT tgt), '<none>') \
              FROM (SELECT COALESCE(m.path || ':' || f.name, 'UNRESOLVED:' || c.kind) AS tgt \
              FROM calls c JOIN functions fc ON c.caller_id = fc.id LEFT JOIN functions f ON \
              c.callee_id = f.id LEFT JOIN modules m ON f.module_id = m.id WHERE fc.name = '%s' \
              AND c.callee_name LIKE '%s')"
             caller like)
      in
      Batch.run (fun b ->
          (* The fixture must actually contain the collision it is about. *)
          Batch.eq_string_opt b
            ~msg:"the fixture must hold two DISTINCT units both spelled api.ml"
            (Db.string_opt conn
               "SELECT group_concat(unit_name, ',') FROM (SELECT unit_name FROM modules WHERE \
                path LIKE '%/api.ml' AND unit_name LIKE '%__Api' ORDER BY unit_name)")
            (Some "inc__Api,rootlib__Api,sublib__Api") ;
          (* Both directions. A resolver that always picks the same library
             passes either one alone, and which one it picks depends on
             directory traversal order — so one direction is half inert. *)
          Batch.eq_string b
            ~msg:"entry calls Sublib.Api.run and must bind to SUBLIB's run, once, as MUST"
            (binding ~caller:"entry" ~like:"%Api.run")
            "1 row(s) -> sublib/api.ml:run" ;
          Batch.eq_string b
            ~msg:"entry2 calls Api.run inside rootlib and must bind to ROOTLIB's run"
            (binding ~caller:"entry2" ~like:"%Api.run")
            "1 row(s) -> rootlib/api.ml:run" ;
          Batch.eq_string b
            ~msg:"a name reached through `open` resolves by unit like any other"
            (binding ~caller:"via_open" ~like:"%Api.run")
            "1 row(s) -> sublib/api.ml:run" ;
          (* Library `x` in directory `xlib`: a resolver reading identity off
             the source layout binds this wrong or not at all. *)
          Batch.eq_string b
            ~msg:
              "an ambiguous outer component must not lose a deeper unique resolution, and the \
               library (x) is not its directory (xlib)"
            (binding ~caller:"deep" ~like:"%B.f")
            "1 row(s) -> xlib/b.ml:f" ;
          (* The re-export. The only forbidden outcome is a confident binding
             into a DIFFERENT unit; ⊤ is what honest ignorance looks like here,
             and a NULL leaf is what it must not look like. *)
          Batch.eq_string b
            ~msg:
              "Inc.Api.run is provided by an include: the unit is known, so this must degrade to \
               ⊤ — never bind to another library's run, never a NULL leaf that reads as external"
            (binding ~caller:"via_include" ~like:"%Api.run")
            "1 row(s) -> UNRESOLVED:MAY_TOP" ;
          (* Type usages are the third copy of the collapse, and they need a
             POSITIVE control: asserting only that the wrong answer is absent is
             satisfied by a resolver that resolves no types at all. *)
          List.iter
            (fun (fn, want) ->
              Batch.eq_string_opt b
                ~msg:
                  (Printf.sprintf
                     "the type written Api.t in %s must resolve to ITS OWN library's t" fn)
                (Db.string_opt conn
                   (Printf.sprintf
                      "SELECT COALESCE(m.path, 'UNRESOLVED') FROM type_usage tu JOIN functions \
                       fu ON tu.function_id = fu.id JOIN modules fm ON fu.module_id = fm.id \
                       LEFT JOIN types t ON tu.type_id = t.id LEFT JOIN modules m ON \
                       t.module_id = m.id WHERE tu.type_name LIKE '%%Api.t' AND fm.path = '%s'"
                      fn))
                (Some want))
            [("rootlib/caller.ml", "rootlib/api.ml"); ("sublib/user.ml", "sublib/api.ml")] ;
          (* The other side of the ⊤ branch: a unit this index does NOT hold
             must stay a MUST leaf. Without this, emitting ⊤ for every
             unresolved callee also passes — and that turns 78% of a real graph
             into ⊤ while the golden file, which counts calls and not kinds,
             still matches exactly. *)
          Batch.eq_string b
            ~msg:"an external callee stays a MUST leaf, never ⊤"
            (binding ~caller:"run" ~like:"%Hashtbl.replace")
            "1 row(s) -> UNRESOLVED:MUST" ;
          (* Module deps are resolved by their own code path. Asserted on the
             target PATH and the row count: a count alone is also what "resolved
             to the same module twice" produces. *)
          Batch.eq_string_opt b
            ~msg:"`open Sublib.Api` must record exactly one dep row, pointing at sublib"
            (Db.string_opt conn
               "SELECT count(*) || ' -> ' || COALESCE(group_concat(DISTINCT p), '<none>') FROM \
                (SELECT COALESCE(mt.path, 'UNRESOLVED') AS p FROM module_deps d LEFT JOIN modules \
                 mt ON d.target_module = mt.id WHERE d.target_path = 'Sublib.Api')")
            (Some "1 -> sublib/api.ml") ;
          Batch.eq_string_opt b
            ~msg:"`open Rootlib.Api` must record its own dep row, pointing at rootlib"
            (Db.string_opt conn
               "SELECT count(*) || ' -> ' || COALESCE(group_concat(DISTINCT p), '<none>') FROM \
                (SELECT COALESCE(mt.path, 'UNRESOLVED') AS p FROM module_deps d LEFT JOIN modules \
                 mt ON d.target_module = mt.id WHERE d.target_path = 'Rootlib.Api')")
            (Some "1 -> rootlib/api.ml") ;
          Batch.eq_string_opt b
            ~msg:"the fixture must really collide: two units both named dune__exe__Util"
            (Db.string_opt conn
               "SELECT count(*) FROM modules WHERE unit_name = 'dune__exe__Util'")
            (Some "2") ;
          (* The only forbidden answer is e2. Resolving to e1 would be correct
             and is not required — the point is that a colliding unit name must
             never be resolved by picking one of its members. *)
          (* A collided unit name must resolve to NOTHING. Asserting merely
             "not e2" is satisfied by picking the first member, which happens to
             be e1 here — right by list order, not by resolution, and the
             mutation that keeps an arbitrary member passed under it. *)
          Batch.eq_string b
            ~msg:
              "two units sharing dune__exe__Util cannot be told apart, so the call must degrade \
               to ⊤ rather than pick either one"
            (binding ~caller:"go" ~like:"%Util.helper")
            "1 row(s) -> UNRESOLVED:MAY_TOP") ;
      (* The end-to-end consequence of the ⊤ on the re-export: `unreachable`
         must decline. UNREACHABLE here would be the forged verdict the whole
         change exists to prevent. *)
      Batch.run (fun b ->
          Batch.contains b
            ~msg:
              "a call into a unit whose name we cannot place must not let unreachable prove \
               anything"
            ~haystack:(query db ["unreachable"; "via_include"; "run"])
            "UNKNOWN")) ;
  Lwt.return_unit
