(** Minimal I/O helpers for arch_index — replaces Epure_lib.Cli_output and
    Epure_lib.Log. *)

val printf : ('a, out_channel, unit) format -> 'a
val eprintf : ('a, out_channel, unit) format -> 'a
val warnf : ('a, out_channel, unit) format -> 'a
