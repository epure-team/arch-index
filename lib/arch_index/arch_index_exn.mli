(******************************************************************************)
(*                                                                            *)
(* Copyright (c) 2026 Epure Team                                              *)
(* All rights reserved.                                                       *)
(*                                                                            *)
(******************************************************************************)

(** Exception-identity recording for one function node.

    See specs/exn-raise-sets.md. One accumulator per lowering context of the
    CFG walker (top-level binding or promoted lambda). Pure: no SQLite, no
    CFG. *)

type form =
  | Raise  (** raise head applied to a literal constructor *)
  | Reraise  (** raise head applied to a variable bound by a handler arm of this node *)
  | Unknown  (** raise head applied to anything else — ⊤ [unknown_exn_value] *)
  | Failwith
  | Invalid_arg
  | Assert
  | Partial_match
  | Compare  (** polymorphic comparison at a type that may hold a closure → [Invalid_argument] *)
  | Division  (** integer [/] / [mod] primitives → [Division_by_zero] *)
  | Index  (** bounds-checked array/string/bytes access → [Invalid_argument] *)

val form_to_string : form -> string

type scope_form = Try | Match_exception

val scope_form_to_string : scope_form -> string

type origin = {
  o_form : form;
  o_path : string option;  (** canonical exception path; [None] for [Reraise]/[Unknown] *)
  o_scope : int option;  (** innermost enclosing scope (local id); for [Reraise], the binding scope *)
  o_escapes : bool;
  o_line : int;
  o_col : int;
}

type scope = {
  s_id : int;  (** local id, minted in enter order (parents before children) *)
  s_parent : int option;
  s_form : scope_form;
  s_line : int;
  s_col : int;
  s_catch_all : bool;
  s_caught : string list;  (** canonical paths caught by closing arms, sorted *)
  s_bound : string list;  (** [Ident.unique_name] of every arm-bound ident *)
}

(** A handler arm, uniformly for [try … with] and [match … with exception]. *)
type arm = {
  a_pat : Typedtree.value Typedtree.general_pattern;
  a_guard : Typedtree.expression option;
  a_rhs : Typedtree.expression;
}

type acc

val create : unit -> acc

val current_scope : acc -> int option

(** {2 Recognisers} *)

(** [%raise] / [%raise_notrace] / [%reraise] primitive, whatever its path. *)
val is_raise_head : Typedtree.expression -> bool

type stdlib_head = Sl_failwith | Sl_invalid_arg | Sl_raise_with_backtrace

(** Persistent [Stdlib] root only. *)
val stdlib_head : Typedtree.expression -> stdlib_head option

(** Canonical exception path: predef → bare name; persistent root → [Path.name];
    root declared by a structure item of this unit ([unit_declared] maps the
    root's [Ident.unique_name] to its module-qualified name) →
    [cmt_modname.<qualified>.<rest>]; otherwise [local:<unique_name><rest>]. *)
val canonical_path :
  unit_declared:(string -> string option) -> cmt_modname:string -> Path.t -> string

(** [exception Alias = Target] → the target path. *)
val rebind_of : Typedtree.extension_constructor -> Path.t option

(** Unguarded and no raise of a non-literal value anywhere in the RHS. *)
val arm_is_closing : arm -> bool

val exception_arms : Typedtree.computation Typedtree.case list -> arm list

val value_arms : Typedtree.value Typedtree.case list -> arm list

(** The value-side twin of {!exception_arms}: flattens a [match]'s computation
    cases into the value patterns they actually contain, so an arm-level
    or-pattern is not lost.

    `Error A | Error C -> rhs` is a [Tpat_or] of two [Tpat_value]s at the
    computation level, not a [Tpat_value]. Keeping only [Tpat_value] cases
    dropped such an arm entirely, so it closed nothing — while the same intent
    written inside the constructor, `Error (A | C)`, closed both. Sound in the
    closing direction: OCaml requires every alternative to bind the same
    variables, and the guard and right-hand side are shared. *)
val value_pats_of_computation :
  Typedtree.computation Typedtree.case list ->
  (Typedtree.value Typedtree.general_pattern
  * Typedtree.expression option
  * Typedtree.expression)
  list

(** {2 Recording (called by the walker at its own AST sites)} *)

val enter_scope :
  acc -> canon:(Path.t -> string) -> form:scope_form -> loc:Location.t -> arms:arm list -> int

val leave_scope : acc -> unit

(** Run [f] with no enclosing scope — for deferred bodies ([lazy], objects,
    functor bodies) that execute outside any lexically enclosing handler. *)
val with_cleared_scopes : acc -> (unit -> 'a) -> 'a

val record_raise_head :
  acc ->
  canon:(Path.t -> string) ->
  args:(Asttypes.arg_label * Typedtree.expression option) list ->
  loc:Location.t ->
  unit

val record_stdlib_head :
  acc ->
  canon:(Path.t -> string) ->
  head:stdlib_head ->
  args:(Asttypes.arg_label * Typedtree.expression option) list ->
  loc:Location.t ->
  unit

(** A raising primitive other than raise (comparison / division / bounds
    check), recognised by primitive name; comparison at a closure-free ground
    type records nothing. *)
val record_prim_head :
  acc ->
  fn:Typedtree.expression ->
  args:(Asttypes.arg_label * Typedtree.expression option) list ->
  loc:Location.t ->
  unit

val record_assert : acc -> loc:Location.t -> unit

val record_partial : acc -> loc:Location.t -> unit

(** Scopes in enter order and origins in source order, with [o_escapes]
    computed from each origin's scope chain. *)
val finalize : acc -> scope list * origin list

(** Does this pattern accept EVERY value of its type?

    A constructor pattern whose arguments constrain the value (a constant, a
    nested constructor) catches a strict subset of its identity, so an arm
    built from it must not be recorded as closing that identity — doing so
    deletes a reachable failure from the answer. Shared with the value
    channels so the two cannot drift apart. *)
val pat_is_irrefutable : Typedtree.value Typedtree.general_pattern -> bool

