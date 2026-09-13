val read : Arch_db.t -> limit:int -> Arch_db.cell list list * Arch_db.cell list list
(** Fully validate the v1 binding contract and return its summary and bounded rows.
    The read is performed in one read-only snapshot. *)
