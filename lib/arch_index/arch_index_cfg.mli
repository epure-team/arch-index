(******************************************************************************)
(*                                                                            *)
(* Copyright (c) 2026 Epure Team                                              *)
(* All rights reserved.                                                       *)
(*                                                                            *)
(******************************************************************************)

(** Pure per-function control-flow graph with post-dominance (see .ml). *)

type t

(** The entry block index (always [0], present after [create]). *)
val entry : int

(** Fresh single-block graph. *)
val create : unit -> t

(** Allocate a fresh, empty block; returns its index. *)
val new_block : t -> int

(** [add_edge g a b] adds a control-flow edge [a → b]. No-op if [a] is
    terminated (diverging terminators admit no fall-through). *)
val add_edge : t -> int -> int -> unit

(** Mark a block as ending in a diverging (noreturn) terminator: it flows to
    the virtual exit at [solve] time and accepts no further successors. *)
val terminate : t -> int -> unit

type verdict

(** Solve post-dominance + entry-reachability. If no path reaches the virtual
    exit (function can never complete), nothing is always-executed.

    [deferred] lists blocks that the lowering deliberately left without an
    incoming edge because they hold code that runs on a LATER, separate entry —
    a lazy thunk, an object method, a functor body, an optional argument's
    default. They stay entry-unreachable (which is what demotes their calls),
    but they seed [may_run]. *)
val solve : ?deferred:int list -> t -> verdict

(** Does this block run on every execution of the function (post-dominates the
    entry and is reachable from it)? Calls in such a block may be MUST. *)
val always_exec : verdict -> int -> bool

(** Is this block reachable from the entry? (Unreachable blocks hold calls that
    are recorded but demoted — code after a diverging terminator.) *)
val reachable : verdict -> int -> bool

(** Can this block execute at all — from the entry, or from a deferred root?
    Use the negation, not [not (reachable …)], for any "this code is dead"
    claim: deferred bodies are entry-unreachable by construction. *)
val may_run : verdict -> int -> bool
