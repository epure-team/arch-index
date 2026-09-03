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

(** [path_matches pattern actual]: [pattern] may contain [*] wildcards
    (matching zero or more characters, no other glob syntax) — used so one
    profile path such as [Tezos_protocol_environment_*.Error_monad.tzfail]
    covers every protocol instance (slice 4, "Profile-path wildcards"). A
    pattern with no [*] matches only the identical string. *)
val path_matches : string -> string -> bool

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

(** Refuse an effective config in which some channel is STRUCTURALLY
    unreachable: carrier selection is first-match-wins over the merged
    channel list, so a channel all of whose carrier types are already
    claimed by an earlier channel can never own a carrier — yet it is still
    published in [comment_db_meta.error_contract], making every query on it
    answer [NOT_A_CARRIER] (a claim about the analysed code) where the truth
    is "this channel was never applicable". [Error] names both channels and
    the shared carrier type, and says to reorder or merge them. Independent
    of any corpus: it reads the config alone, so it is checked before
    indexing starts. Two channels sharing a carrier type but distinguished
    by [error_type]/[error_arg] are reachable and are NOT refused. *)
val check_reachable : t -> (unit, string) result

(** {2 Validation — declared-set-with-found-flags}

    [seen] stores ONLY the paths declared by a config's channels, each with
    a found flag — never the corpus (which can be tens of thousands of
    paths). [create] pre-populates it from a config; [note_value_path] /
    [note_type_path] flip a flag to found when the walker meets a matching
    path, and are a cheap no-op for anything not declared. *)
type seen

(** Pre-populate a [seen] set with every path [t]'s channels declare, each
    starting unfound. The split matters, because only [note_value_path] can
    ever flip a value flag and only [note_type_path] a type flag:
    - values: origins / handlers / binds / transforms / converters / sinks;
    - types: [type_paths] plus [lift] and [unwrap], which name type
      constructors ([Lwt.t], [...Error_monad.trace]) and are matched against
      a [Tconstr]'s path by {!Arch_index_errch}, not against a call head.
      Filing them as values made them permanently unmatchable and
      [--errors-strict] permanently fatal (review round 1). *)
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
    the same effective config came from a file.

    [~strict:true] additionally turns a per-path miss into a fatal error —
    but only for a channel the operator is responsible for: one whose name
    is not a built-in's, or whose declarations differ from that built-in's
    (redeclaring [\[channel.option\]] in a profile puts the whole channel
    back under strict). An UNTOUCHED built-in's misses stay warnings: they
    are not the operator's declarations, and one of them ([Stdlib.option])
    is a spelling the compiler never prints, which made [--errors-strict]
    unsatisfiable for every config and every corpus (review round 1). *)
val validate : t -> seen -> strict:bool -> ?builtin_names:string list -> unit -> (unit, string) result
