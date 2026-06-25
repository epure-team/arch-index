(** Minimal I/O helpers for arch_index: stdout/stderr printf wrappers and a
    warn-prefixed stderr helper. *)

val printf : ('a, out_channel, unit) format -> 'a
val eprintf : ('a, out_channel, unit) format -> 'a
val warnf : ('a, out_channel, unit) format -> 'a
