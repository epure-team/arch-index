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
    exit (function can never complete), nothing is always-executed. *)
val solve : t -> verdict

(** Does this block run on every execution of the function (post-dominates the
    entry and is reachable from it)? Calls in such a block may be MUST. *)
val always_exec : verdict -> int -> bool

(** Is this block reachable from the entry? (Unreachable blocks hold calls that
    are recorded but demoted — code after a diverging terminator.) *)
val reachable : verdict -> int -> bool
