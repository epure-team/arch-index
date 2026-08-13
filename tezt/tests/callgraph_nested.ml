(******************************************************************************)
(*                                                                            *)
(* Copyright (c) 2026 Epure Team                                              *)
(* All rights reserved.                                                       *)
(*                                                                            *)
(******************************************************************************)

(** Nested modules and functors: definitions indexed where they are WRITTEN.

    The regression this covers is narrow and was invisible from the outside. The
    walker registered only a compilation unit's toplevel bindings, so everything
    inside [module M = struct ... end] or [module Make (P : S) = struct ... end]
    was absent — not as a function row, and not as a call target. A helper called
    only from inside a functor showed zero callers, and every query crossing a
    functor degraded to UNKNOWN. Soundness was never violated, because those
    edges were already ⊤; the answers simply stopped discriminating.

    Two further properties are asserted because each was a separate bug hiding
    behind the first: a functor APPLICATION must define nothing new (definitions
    are indexed once, where they are written), and the signature walk must reach
    into a functor's result — otherwise the rows exist but stay invisible to
    anything gating on exposure or on comment quality. *)

open Arch_tezt

let fixture_files =
  [
    ("dune-project", "(lang dune 3.0)\n");
    ( "dune",
      "(library\n\
      \ (name testnested)\n\
      \ (modules testnested)\n\
      \ ; unused_inner is deliberately unreferenced: it is the dead-code candidate.\n\
      \ (flags (:standard -w -32)))\n" );
    ("testnested.mli", {|val helper : int -> int

module type S = sig
  val base : int
end

module Impl : S

module Make (P : S) : sig
  val apply : (int -> int) -> int -> int

  (** [inner x] adds [P.base] to [x] and hands it to [helper].

      {pre}
      None.

      {post}
      Returns [helper (x + P.base)].

      {violators}
      helper — a change to its arithmetic changes what inner returns.

      {violates}
      (none) *)
  val inner : int -> int

  val outer : unit -> int
end

module Plain : sig
  val nested : unit -> int
end

module type T = sig
  val go : int -> int
end

module Named (P : S) : T

val included_fn : unit -> int

module R1 : sig
  val f : int -> int
end

module R2 : sig
  val g : int -> int
end

module Scoped : sig
  val uses : unit -> int
end

module M : sig
  val inner : int -> int
  val outer : unit -> int
end
|});
    ("testnested.ml", {|(* Controlled fixture for the nested-module / functor indexing regression. *)

let helper (x : int) : int = x + 1

module type S = sig
  val base : int
end

module Impl = struct
  let base = 7
end

module Make (P : S) = struct
  let inner (x : int) : int = helper (x + P.base)
  let outer () : int = inner 1

  (* Calls a function parameter: an unresolvable head, so the roots provably
     reach a MAY_TOP edge. *)
  let apply (f : int -> int) (x : int) : int = f x

  (* Nested, not in the .mli, called by nobody: the dead-code candidate. *)
  let unused_inner () : int = 0
end

module Plain = struct
  let nested () : int = helper 0
end

(* A named result signature -- the spelling most .mli files use. *)
module type T = sig
  val go : int -> int
end

module Named (P : S) : T = struct
  let go (x : int) : int = helper (x + P.base)
end

(* include struct: its bindings land in the enclosing scope. *)
include struct
  let included_fn () : int = helper 1
end

(* Recursive modules. *)
module rec R1 : sig
  val f : int -> int
end = struct
  let f x = R2.g x
end

and R2 : sig
  val g : int -> int
end = struct
  let g x = helper x
end

(* An open local to a nested module is not a dependency of this file. *)
module Scoped = struct
  open Stdlib.List

  let uses () : int = length []
end

module M = Make (Impl)
|});
  ]

let register () =
  Test.register ~__FILE__
    ~title:"cmt: nested modules and functors are indexed where they are written"
    ~tags:["cmt"; "nested"; "functor"]
  @@ fun () ->
  with_fixture ~name:"nested" ~files:fixture_files @@ fun fixture ->
  let db = index fixture in
  Batch.run (fun b ->
      Db.with_db db (fun conn ->
          (* Indexed under their definition path, exactly once each. *)
          List.iter
            (fun want ->
              Batch.eq_int b
                ~msg:(Printf.sprintf "exactly one function row named %S" want)
                (Db.int conn
                   (Printf.sprintf "SELECT count(*) FROM functions WHERE name = '%s'" want))
                1)
            ["Make.inner"; "Make.outer"; "Plain.nested"] ;

          (* The regression itself. Before the fix this count was 0: helper was
             called from inside a functor body and from a plain nested module,
             and neither call site existed. *)
          (match Db.int_opt conn "SELECT id FROM functions WHERE name = 'helper' LIMIT 1" with
          | None -> Batch.note b "the toplevel function 'helper' is not in the index"
          | Some id ->
              Batch.ge_int b
                ~msg:"'helper' must keep its callers from inside nested modules"
                (Db.int conn
                   (Printf.sprintf
                      "SELECT count(DISTINCT c.caller_id) FROM calls c WHERE c.callee_id = %d" id))
                2) ;

          (* The signature walk reaches into the functor's result signature.
             Without it the row above exists but is invisible to any gate. *)
          Batch.eq_string_opt b ~msg:"'Make.inner' must be exposed — the .mli declares it"
            (Db.string_opt conn "SELECT exposed FROM functions WHERE name = 'Make.inner'")
            (Some "1") ;
          Batch.ge_int b ~msg:"'Make.inner' must carry its doc-comment score from the .mli"
            (Db.int conn
               "SELECT COALESCE(comment_quality_score, -1) FROM functions WHERE name = \
                'Make.inner'")
            74 ;

          (* A functor application is not a definition site. Indexing it would
             produce one set of rows per instantiation. *)
          Batch.eq_int b
            ~msg:"the application M = Make (Impl) must define nothing new"
            (Db.int conn "SELECT count(*) FROM functions WHERE name LIKE 'M.%'")
            0 ;

          (* Named result signatures are the spelling most .mli files use;
             walking only inline sig...end would leave these indexed but never
             exposed. Recursive modules and `include struct` are the same walk. *)
          List.iter
            (fun want ->
              Batch.eq_string_opt b
                ~msg:(Printf.sprintf "%S must be indexed and exposed" want)
                (Db.string_opt conn
                   (Printf.sprintf
                      "SELECT COALESCE(exposed, -1) FROM functions WHERE name = '%s'" want))
                (Some "1"))
            ["Named.go"; "R1.f"; "R2.g"; "included_fn"; "Scoped.uses"] ;

          (* An `open` inside a nested module is scoped to it, not to the file.

             Weaker than it looks, and said so rather than left implied:
             `module_deps` is written ONLY by the LSP path (arch_index.ml), never
             by arch-callgraph-ocaml, so the table is empty here by construction.
             A leak would still trip this, but a producer with no open-tracking
             at all passes it identically. *)
          Batch.eq_int b
            ~msg:"the open inside module Scoped must not leak into file-scoped module_deps"
            (Db.int conn
               "SELECT count(*) FROM module_deps WHERE target_path LIKE 'Stdlib.List%'")
            0) ;

      (* Reachability discriminates across the functor boundary now. *)
      Batch.contains b ~msg:"reaches Make.outer helper must be a MUST path (was UNKNOWN before)"
        ~haystack:(query db ["reaches"; "Make.outer"; "helper"]) "PATH EXISTS (must-reach)" ;

      (* Nested definitions whose only caller goes through a functor parameter
         are reachable only via ⊤, so a confident dead verdict would be false.
         Asserted POSITIVELY on the degradation message: the column header is
         literally "verdict_soundness", so grepping for "sound" would match the
         header whatever the verdict said. *)
      let dc = query db ["dead-code"] in
      Batch.contains b
        ~msg:"dead-code must list Make.unused_inner, which nothing calls and the .mli hides"
        ~haystack:dc "Make.unused_inner" ;
      Batch.contains b
        ~msg:"dead-code must degrade its verdict when a ⊤ edge is reachable, and say why"
        ~haystack:dc "MAY_TOP reachable") ;
  Lwt.return_unit
