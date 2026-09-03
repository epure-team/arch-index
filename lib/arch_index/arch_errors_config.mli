(******************************************************************************)
(*                                                                            *)
(* Copyright (c) 2026 Epure Team                                              *)
(* All rights reserved.                                                       *)
(*                                                                            *)
(******************************************************************************)

(** Error-channels configuration (specs/error-channels.md, slice 0).

    A "channel" is a way for a function to fail: [exception] (unwinding,
    already shipped) or a value channel (an error carried in the function's
    returned value, e.g. [result]/[option]). This module owns the config
    vocabulary ([arch-errors.toml]), its built-ins, TOML parsing, merge
    order, digesting, and the declared-set-with-found-flags validation
    machinery. It does NOT change the analysis: slices 0-1 emit only the
    [exception] channel; [result]/[option] are declared here so discovery,
    merge and validation have real built-in data to exercise, but no
    producer code reads [t] to change what gets written yet. *)

(** [mode] of a [transforms] entry: [Add] keeps the inner set (union with the
    literal argument's origins, e.g. [record_trace]); [Replace] discards it
    (e.g. [Result.map_error]). *)
type mode = Add | Replace

(** One channel's declared vocabulary, straight off the TOML shape in
    specs/error-channels.md's Clarifications table. *)
type channel = {
  name : string;
  type_paths : string list;
      (** The carrier ['type'] plus ['underlying'] plus ['aliases'] — every
          spelling under which the carrier type may print in a [.cmt]. Empty
          for a marker channel with no carrier type (e.g. [exception]). *)
  error_arg : int option;  (** 1-based; not applicable for an alias carrier. *)
  lift : string list;
  error_type : string option;  (** [Some ""] = identity (e.g. [option]'s [None]). *)
  unwrap : string list;
  origins : (string * int) list;  (** (path, 1-based literal-argument position) *)
  binds : string list;
  handlers : (string * int) list;  (** (path, 1-based value-argument position) *)
  transforms : (string * mode * int) list;
  converters : (string * string * string * int * string option) list;
      (** (path, from, to, arg, error path — [None] = opaque identity) *)
  sinks : string list;
}

(** Effective configuration: declared channels plus [[summaries]] — per
    callee path, the declared origin set on each named channel. *)
type t = {
  channels : channel list;
  summaries : (string * (string * string list) list) list;
      (** (callee path, [(channel name, origin paths)] list) *)
}

(** [exception] (marker, no carrier type — same rows the shipped exception
    analysis already writes), [result] ([Stdlib.result], [error_arg = 2]),
    [option] ([option], identity [None]). *)
val builtin : t

(** Parse one TOML 1.0 document (already read from disk) into a config. An
    unknown key anywhere in the [\[channel.*\]]/[\[summaries\]] shape is an
    error naming it; a TOML syntax error is passed through as-is. *)
val of_toml : string -> (t, string) result

(** [merge base override] — channel/summary entries in [override] replace
    same-named entries from [base]; entries present only in one side are
    kept; declaration order is [base]'s order, then [override]'s new
    entries appended. Composition order per Clarifications: builtin <
    profile < user, so [merge (merge builtin profile) user]. *)
val merge : t -> t -> t

(** [Digest.to_hex] of a canonical (sorted, structural — not textual)
    serialisation of the effective config: stable across reformatting of
    the same declarations, changes when any declared list changes. *)
val digest : t -> string

(** {2 Validation — declared-set-with-found-flags}

    [seen] stores ONLY the paths declared by a config's channels, each with
    a found flag — never the corpus (which can be tens of thousands of
    paths). [create] pre-populates it from a config; [note_value_path] /
    [note_type_path] flip a flag to found when the walker meets a matching
    path, and are a cheap no-op for anything not declared. *)
type seen

(** Pre-populate a [seen] set with every path [t]'s channels declare
    (values: origins/lift/unwrap/handlers/binds/transforms/converters/sinks;
    types: [type_paths]), each starting unfound. *)
val create : t -> seen

val note_value_path : seen -> string -> unit

val note_type_path : seen -> string -> unit

(** Declared paths never marked found, sorted. What
    [comment_db_meta.error_config_unmatched] is built from. *)
val unmatched : seen -> string list

(** Per-path miss (declared path never seen) is a warning, printed here and
    reflected in {!unmatched}. A channel with a non-empty {!channel.type_paths}
    none of which was ever seen as a type is FATAL regardless of [strict]
    (the "declaration matching nothing" bug class) — UNLESS its name is in
    [builtin_names] (default [[]]): a built-in channel whose carrier type is
    simply absent from a small/non-matching corpus is not a declaration bug
    (Clarifications: "Built-in channels that match nothing"), so it is only
    ever a warning, per-channel, independent of whether OTHER channels in
    the same effective config came from a file. [~strict:true] also turns
    any per-path miss into a fatal error. *)
val validate : t -> seen -> strict:bool -> ?builtin_names:string list -> unit -> (unit, string) result
