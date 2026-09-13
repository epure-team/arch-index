val read : Arch_db.t -> limit:int -> Arch_db.cell list list * Arch_db.cell list list
(** Validate and read the catalogue in its own read-only snapshot. *)

val read_unwrapped : Arch_db.t -> limit:int -> Arch_db.cell list list * Arch_db.cell list list
(** Validate and read the catalogue in a caller-owned snapshot. *)
