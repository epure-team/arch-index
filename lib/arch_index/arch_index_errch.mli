(******************************************************************************)
(*                                                                            *)
(* Copyright (c) 2026 Epure Team                                              *)
(* All rights reserved.                                                       *)
(*                                                                            *)
(******************************************************************************)

(** Value-channel (specs/error-channels.md) origin/scope recording for one
    function node. SLICE 2 scope: monomorphic [result]/[option]-shaped
    channels only — no lift, unwrap, binds, transforms or converters. Pure:
    no SQLite, no CFG; mirrors [Arch_index_exn]'s shape but a value-channel
    "scope" is a POINT fact (it covers exactly one call's head, never a
    lexical region), so there is no enter/leave stack here. *)

(** [carrier_channel_of_type ~channels ty]: strip leading [Tarrow]s from
    [ty]; if what remains is [Tconstr (p, args, _)] with [p] naming one of
    [channels]' [type_paths], and (when that channel declares [error_arg])
    the type argument at that 1-based position has a head path equal to the
    channel's [error_type], or [error_type] is unset/[""], or that argument
    is a type variable — return that channel. [None] otherwise. Also used,
    unchanged, on a [Texp_construct]'s [cstr_res] (never an arrow) to decide
    which channel a constructor belongs to. *)
val carrier_channel_of_type :
  channels:Arch_errors_config.channel list -> Types.type_expr -> Arch_errors_config.channel option

(** [bind_shape_channel ~channels ty]: [ty] (an UNSTRIPPED function type, the
    operator's own type before application) has the shape
    [c -> ('a -> c) -> c] for some declared channel [c] — [None] otherwise.
    Used to flag an application whose head is NOT a declared [binds] path but
    whose type says it binds a carrier anyway (specs/error-channels.md
    "Binds": [inferred_bind]). *)
val bind_shape_channel :
  channels:Arch_errors_config.channel list -> Types.type_expr -> Arch_errors_config.channel option

(** Canonical path of an ordinary (non-extensible) constructor: the module
    portion of its constructed type's canonical path (via [canon_type],
    expected to be [Arch_index_exn.canonical_path] partially applied) plus
    the bare constructor name — e.g. type [Ec_a.err] constructor [A] →
    ["Ec_a.A"]. *)
val constructor_canonical_path :
  canon_type:(Path.t -> string) -> Types.type_expr -> string -> string

(** Canonical path of a literal constructor application/pattern argument:
    [Cstr_extension] reuses [canon_exn] (exception-style, extensible-variant
    identity); an ordinary constructor uses {!constructor_canonical_path}.
    [None] for anything that is not itself a constructor application. *)
val literal_ctor_path_of_expr :
  canon_type:(Path.t -> string) -> canon_exn:(Path.t -> string) -> Typedtree.expression -> string option

val literal_ctor_path_of_pat :
  canon_type:(Path.t -> string) ->
  canon_exn:(Path.t -> string) ->
  Typedtree.value Typedtree.general_pattern ->
  string option

(** Bare identifiers a value pattern binds ([Tpat_var]/[Tpat_alias]/[Tpat_or]
    union), for the "re-return" recognition rule (EC-3's sibling: an
    [Error e -> Error e] arm's [Error e] neither closes nor is a fresh
    origin — see [Implement] item 2/EC-1). *)
val pat_bound_idents : Typedtree.value Typedtree.general_pattern -> string list

(** What one match arm demonstrably catches on a value channel: a SET of
    canonical error identities, plus whether the arm closes the channel
    outright. Deliberately the same shape as the exception channel's
    [Arch_index_exn.pat_class] (minus its [bound] field, returned separately
    by {!classify_value_pat}) — the two classifiers answer the same question
    and must not drift.

    Set-valued because closing exactly one identity is not enough: an earlier
    [string option] read [None] as "catch-all" and so closed the entire
    channel on any non-single-literal argument (unsound); the three-case
    [Catch_all | Caught of string | Unrecognised] that replaced it was sound
    but could name only ONE identity, so [Error (A | B)] closed NEITHER.
    Everything downstream is already set-valued, so a set costs nothing. *)
type pat_class = {
  caught : string list;  (** canonical identities this arm fully catches *)
  catch_all : bool;  (** it also catches every OTHER identity of the channel *)
}

(** One arm's classification against a channel's origin constructor
    ([bare_ctor], [arg_pos] — [0] = no-argument identity, e.g. [None]):
    [Some (class, bound_idents)] when the pattern matches that constructor,
    [None] when the pattern does not apply to it at all (e.g. an [Ok x] arm).
    [{caught = []; catch_all = false}] means the arm matches a real but
    unnameable subset and must be treated as closing nothing. *)
val classify_value_pat :
  canon_type:(Path.t -> string) ->
  canon_exn:(Path.t -> string) ->
  bare_ctor:string ->
  arg_pos:int ->
  Typedtree.value Typedtree.general_pattern ->
  (pat_class * string list) option

(** Free occurrence of any of [idents] (by [Ident.unique_name]) in [e].
    Over-approximates on purpose (no shadowing awareness): the EC-3 closing
    rule ("bound variables do not occur in the RHS") is only sound in the
    non-closing direction if a false "occurs" never fires — a
    misclassification-as-occurring only makes an arm non-closing, which is
    the safe (propagates-more) side. *)
val idents_occur : idents:string list -> Typedtree.expression -> bool

(** {2 Recording} *)

type origin = {
  o_channel : string;
  o_path : string option;
  o_form : string;
  o_line : int;
  o_col : int;
}

(** A value-channel handler: covers exactly one call's head (linked
    separately, by the caller, via [call_exn_scopes]). [s_caught] mirrors
    [exn_scopes.exn_path]s — canonical error paths a closing arm catches. *)
type scope = {
  s_id : int;
  s_channel : string;
  s_catch_all : bool;
  s_caught : string list;
  s_line : int;
  s_col : int;
}

type acc

val create : unit -> acc

(** Mint and record a new scope, returning its local id (this node's own
    numbering — distinct from [Arch_index_exn]'s, rewritten to a real
    [exn_scopes] row id by the caller once inserted). *)
val add_scope :
  acc -> channel:string -> catch_all:bool -> caught:string list -> loc:Location.t -> int

(** [~form]: defaults to ["unknown"] when [path = None], ["raise"]
    otherwise — pass it explicitly for ["inferred_bind"] (see {!origin}). *)
val add_origin :
  acc -> channel:string -> path:string option -> ?form:string -> loc:Location.t -> unit -> unit

val finalize : acc -> scope list * origin list
