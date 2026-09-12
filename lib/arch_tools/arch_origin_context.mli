(** Structured syntax-only divisor evidence for displayed origin offenders. *)

val json_for_sites :
  Arch_db.t -> displayed_row_ids:string list -> offender_row_ids:string list ->
  Yojson.Safe.t list * int * int
