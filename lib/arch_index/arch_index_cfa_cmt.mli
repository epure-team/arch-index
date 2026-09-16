type t
type owner

(** Flat CFA candidates require one LSP symbol and one root CMT binder. *)
val flat_symbol_unique : lsp_count:int -> root_count:int -> bool

val create :
  binding_name:(prefix:string -> Ident.t -> string) ->
  fn_arity:(Typedtree.expression -> int) ->
  Typedtree.structure ->
  t

(** Record the storage outcome of a root function body.  The notification is
    accepted only for the exact binder/body pair discovered during the CMT
    pre-pass; names and locations are not identities. *)
val notify_stored_root :
  t -> binder:Ident.t -> body:Typedtree.expression -> canonical_name:string -> unit

val notify_rejected_root :
  t -> binder:Ident.t -> body:Typedtree.expression -> unit

val fresh_owner : t -> owner
val observe_literal : t -> owner:owner -> expr:Typedtree.expression -> name:string -> arity:int -> unit
val notify_stored_literal : t -> name:string -> unit
val register_local_alias : t -> owner:owner -> binder:Ident.t -> source:Ident.t -> unit
val register_local_expr : t -> owner:owner -> binder:Ident.t -> Typedtree.expression -> unit

(** Register one physical application before the session is finalized.  The
    returned token is session-private and must be consumed before persistence. *)
val register_call :
  t -> owner:owner -> binder:Ident.t -> head:Typedtree.expression -> supplied:int -> omitted_slots:int ->
  legacy_residual:bool -> int option

val register_expr_call : t -> owner:owner -> Typedtree.expression -> head:Typedtree.expression -> supplied:int -> omitted_slots:int -> legacy_residual:bool -> int

val finalize : t -> unit

module For_tests : sig
  val finalize_with_after_staging_hook : t -> (unit -> unit) -> unit
end

val value_of_call :
  t -> int ->
  ((string * int) list * Arch_index_cfa.reason list * int * int * bool) option
