exception Changed
(** Raised when a caller-supplied digest differs across the protected read. *)

val read_checked :
  digest:(string -> string) -> read:(string -> 'a) -> string -> string * 'a
(** [read_checked ~digest ~read path] returns the initial digest and read value,
    or raises {!Changed} when the post-read digest differs. *)
