(******************************************************************************)
(*                                                                            *)
(* Copyright (c) 2026 Epure Team                                              *)
(* All rights reserved.                                                       *)
(*                                                                            *)
(******************************************************************************)

(** Broad regression cover for the OCaml CMT indexer: the module-language shapes
    around the nested-module descent — deep nesting, curried and applied
    functors, shadowing between a toplevel binding and a nested homonym, local
    and first-class modules, operators, mutual recursion, classes, and the type
    side of all of it.

    Every assertion states a property, not an implementation detail, so a shape
    that is deliberately NOT indexed (an application, a local module) is
    asserted absent rather than left unmentioned — that is what keeps a later
    "improvement" from silently doubling rows. *)

open Arch_tezt

let fixture_files =
  [
    Fixture.dune_project;
    ( "dune",
      "(library\n\
      \ (name shapes)\n\
      \ (modules shapes)\n\
      \ ; Several bindings exist only to be looked for in the index.\n\
      \ (flags (:standard -w -32-26-27-34-37-69)))\n" );
    ( "shapes.ml",
      {ocaml|let base (x : int) : int = x + 1

(* deep nesting: three levels *)
module L1 = struct
  module L2 = struct
    module L3 = struct
      let deep (x : int) : int = base x
    end
  end
end

(* shadowing: a nested homonym must not disturb the toplevel *)
type t = {a : int}

let shadowed (x : int) : int = x

module Shadow = struct
  type t = Variant of string

  let shadowed (x : int) : int = base x
end

(* curried functor, and a functor applied to another's result *)
module type S = sig
  val k : int
end

module Impl = struct
  let k = 2
end

module Curried (A : S) (B : S) = struct
  let sum () : int = A.k + B.k
end

module Wrap (A : S) = struct
  let doubled () : int = A.k * 2
end

module Applied = Curried (Impl) (Impl)
module WrapApplied = Wrap (Impl)

(* operators and mutual recursion *)
let ( >>= ) (x : int) (f : int -> int) : int = f x

let rec even (n : int) : bool = if n = 0 then true else odd (n - 1)
and odd (n : int) : bool = if n = 0 then false else even (n - 1)

(* local module in expression position: defines nothing at file scope *)
let uses_local_module () : int =
  let module Local = struct
    let inner_local () : int = 7
  end in
  Local.inner_local ()

(* first-class module: dynamic, nothing to index *)
let uses_first_class (m : (module S)) : int =
  let module M = (val m) in
  M.k

module type ImplLike = module type of Impl

(* include of a named module re-exports without defining *)
module Source = struct
  let from_source () : int = base 0
end

include Source

(* a class: the indexer must not choke on it *)
class counter =
  object
    val mutable n = 0

    method bump = n <- n + 1
  end

exception Boom of string

module Types = struct
  type record = {field_one : int; field_two : string}

  type variant =
    | First
    | Second of int
end
|ocaml} );
    ( "shapes.mli",
      {ocaml|val base : int -> int

module L1 : sig
  module L2 : sig
    module L3 : sig
      val deep : int -> int
    end
  end
end

type t = {a : int}

val shadowed : int -> int

module Shadow : sig
  type t = Variant of string

  val shadowed : int -> int
end

module type S = sig
  val k : int
end

module Impl : S

module Curried (A : S) (B : S) : sig
  val sum : unit -> int
end

module Wrap (A : S) : sig
  val doubled : unit -> int
end

val ( >>= ) : int -> (int -> int) -> int
val even : int -> bool
val odd : int -> bool
val uses_local_module : unit -> int
val uses_first_class : (module S) -> int
val from_source : unit -> int

exception Boom of string

module Types : sig
  type record = {field_one : int; field_two : string}

  type variant =
    | First
    | Second of int
end
|ocaml} );
  ]

(* The cross-module fixture is a second, separate project: Fx.G1.B.f can be read
   as "unit B holding f" or "unit G1 holding B.f", and only a second compilation
   unit named B makes the wrong reading reachable. *)
let cross_module_files =
  [
    Fixture.dune_project;
    ( "dune",
      "(library\n (name qual)\n (modules b g1 g2)\n (flags (:standard -w -32)))\n" );
    ("b.ml", "let f (x : int) : int = x + 100\n");
    ("g1.ml", "module B = struct\n  let f (x : int) : int = x + 1\nend\n");
    ("g2.ml", "let use () : int = G1.B.f 1\n");
  ]

let count db name =
  Db.int db (Printf.sprintf "SELECT count(*) FROM functions WHERE name = '%s'" name)

let exposed db name =
  Db.int_opt db
    (Printf.sprintf "SELECT exposed FROM functions WHERE name = '%s'" name)

let type_count db name =
  Db.int db (Printf.sprintf "SELECT count(*) FROM types WHERE name = '%s'" name)

let register () =
  Test.register ~__FILE__ ~title:"cmt: module-language shapes"
    ~tags:["cmt"; "shapes"; "ocaml"]
  @@ fun () ->
  with_fixture ~name:"arch_tezt_shapes" ~files:fixture_files @@ fun fixture ->
  let db_path = index fixture in
  Db.with_db db_path (fun db ->
      (* present exactly once, under their definition path *)
      List.iter
        (fun name ->
          Check.((count db name = 1) int
                   ~error_msg:(Printf.sprintf "%s: %%L row(s), expected %%R" name)))
        [
          "base"; "shadowed"; "even"; "odd"; "uses_local_module";
          "uses_first_class"; "L1.L2.L3.deep"; "Shadow.shadowed"; "Curried.sum";
          "Wrap.doubled"; "Source.from_source";
        ] ;

      (* exposed through the .mli, however deeply nested *)
      List.iter
        (fun name ->
          Check.((exposed db name = Some 1) (option int)
                   ~error_msg:
                     (Printf.sprintf "%s: exposed = %%L, expected %%R" name)))
        [
          "base"; "L1.L2.L3.deep"; "Shadow.shadowed"; "Curried.sum";
          "Wrap.doubled"; "even"; "odd";
        ] ;

      (* shadowing: the toplevel binding is untouched by its namesake. A REPLACE
         on a shared key is exactly the bug this pins. *)
      Check.(
        (Db.int db
           "SELECT count(*) FROM calls c \
            WHERE c.callee_id = (SELECT id FROM functions WHERE name = 'shadowed' LIMIT 1)"
         = 0)
          int
          ~error_msg:
            "toplevel 'shadowed' has %L caller(s), expected %R: it looks merged \
             with Shadow.shadowed") ;

      (* the class did not derail the walk: no assertion on how methods are
         represented, only that the definitions AFTER the class are still
         there. Types.record and Types.variant below are those definitions. *)

      (* types are qualified the same way values are *)
      List.iter
        (fun name ->
          Check.((type_count db name = 1) int
                   ~error_msg:(Printf.sprintf "type %s: %%L row(s), expected %%R" name)))
        ["t"; "Shadow.t"; "Types.record"; "Types.variant"] ;
      Check.(
        (Db.int db
           "SELECT count(*) FROM type_fields \
            WHERE type_id = (SELECT id FROM types WHERE name = 't' LIMIT 1)"
         > 0)
          int
          ~error_msg:
            "toplevel type 't' kept %L field(s): a cascade from a REPLACE would \
             leave none") ;

      (* an application defines nothing new *)
      List.iter
        (fun name ->
          Check.((count db name = 0) int
                   ~error_msg:
                     (Printf.sprintf
                        "%s: %%L row(s), expected %%R — a functor application \
                         indexes no new definition"
                        name)))
        ["Applied.sum"; "WrapApplied.doubled"] ;

      (* a local module lives in an expression, not at file scope *)
      Check.(
        (Db.int db "SELECT count(*) FROM functions WHERE name LIKE '%inner_local%'"
         = 0)
          int
          ~error_msg:
            "inner_local: %L row(s), expected %R — it is bound by a let module \
             inside a function body") ;

      (* include of a NAMED module re-exports without defining: the row stays
         Source.from_source and nothing is indexed at the toplevel *)
      Check.((count db "from_source" = 0) int
               ~error_msg:"toplevel 'from_source': %L row(s), expected %R") ;

      (* calls resolve across every nesting level *)
      let callers_of_base =
        Db.strings db
          "SELECT f.name FROM calls c JOIN functions f ON f.id = c.caller_id \
           WHERE c.callee_id = (SELECT id FROM functions WHERE name = 'base' LIMIT 1)"
      in
      List.iter
        (fun expected ->
          Check.(
            (List.mem expected callers_of_base = true) bool
              ~error_msg:
                (Printf.sprintf
                   "'base' should record a call from %s; callers were: %s"
                   expected
                   (String.concat ", " callers_of_base))))
        ["L1.L2.L3.deep"; "Shadow.shadowed"; "Source.from_source"] ;

      (* mutual recursion is an edge in both directions *)
      List.iter
        (fun (caller, callee) ->
          Check.(
            (Db.int db
               (Printf.sprintf
                  "SELECT count(*) FROM calls c JOIN functions f ON f.id = c.caller_id \
                   WHERE f.name = '%s' AND c.callee_id = (SELECT id FROM functions \
                   WHERE name = '%s' LIMIT 1)"
                  caller callee)
             > 0)
              int
              ~error_msg:
                (Printf.sprintf "mutual recursion: %s -> %s recorded %%L times"
                   caller callee)))
        [("even", "odd"); ("odd", "even")] ;

      (* reachability across three levels of nesting *)
      let verdict = query db_path ["reaches"; "L1.L2.L3.deep"; "base"] in
      Check.(
        (verdict =~ rex "PATH EXISTS \\(must-reach\\)")
          ~error_msg:"reaches L1.L2.L3.deep base said: %L")) ;

  (* a qualified cross-module call binds to the right homonym *)
  with_fixture ~name:"arch_tezt_qual" ~files:cross_module_files @@ fun fixture ->
  let db_path = index fixture in
  Db.with_db db_path (fun db ->
      let want =
        Db.int_opt db
          "SELECT f.id FROM functions f JOIN modules m ON m.id = f.module_id \
           WHERE f.name = 'B.f' AND m.path LIKE '%g1.ml'"
      in
      (* Pin the reference first: were g1.ml's B.f absent, [want] would be None
         and an equally absent [got] would agree with it for the wrong reason. *)
      Check.(
        (want <> None) (option int)
          ~error_msg:"g1.ml's 'B.f' is not indexed, so there is nothing to bind to") ;
      let got =
        Db.int_opt db
          "SELECT c.callee_id FROM calls c JOIN functions f ON f.id = c.caller_id \
           WHERE f.name = 'use'"
      in
      Check.(
        (got = want) (option int)
          ~error_msg:
            "G1.B.f resolved to function id %L, expected %R (g1.ml's B.f): \
             keeping only the last component of the module path binds to an \
             unrelated b.ml")) ;
  Lwt.return_unit
