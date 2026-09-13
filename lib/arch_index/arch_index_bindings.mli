type formal_kind = Named | Unit

type formal = {
  position : int;
  kind : formal_kind;
  binder_key : string option;
  name : string option;
}

type declaration = {
  declaration_key : string;
  name : string;
  location : string;
  formals : formal list;
}

type result = {
  ordinal : int;
  status : string;
  reason : string option;
  declaration_key : string option;
  formal_position : int option;
  head_application_ordinal : int option;
  actual_root_key : string option;
}

type collection = {
  declarations : declaration list;
  results : result list;
}

val collect : Typedtree.structure -> collection
(** Collect local named functor declarations and account for every catalogue
    application using the catalogue collector's exact ordinals. Local Pident
    aliases are followed by compiler identity, and consecutive literal
    functor results advance one formal per nested application. Identity
    conflicts and malformed named binders raise before results are returned. *)

val store_collected : Sqlite3.db -> producer_run_id:int -> artifact:string -> collection -> unit
val store_failed : Sqlite3.db -> producer_run_id:int -> artifact:string -> unit
val finalize_contract : Sqlite3.db -> selected_inputs:int -> bool
(** Call only after all producer data transactions have committed. Clears any
    previous binding marker, validates the complete catalogue and binding facts
    in a new transaction, then writes v1 only when valid. Returns false for
    inconsistent data; SQL and transaction failures raise. *)
