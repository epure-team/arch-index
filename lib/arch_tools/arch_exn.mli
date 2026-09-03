(** Transitive, handler-aware may-raise sets over an arch-index DB
    (specs/exn-raise-sets.md). See the .ml header for the lattice and the
    call-site subtraction rule. *)

module SS : Set.S with type elt = string
module SM : Map.S with type key = string

type reason_kind = May_top_edge | External | Unknown_exn_value | Inferred_bind

val reason_kind_to_string : reason_kind -> string

type reason = {kind : reason_kind; witness : string}

module RS : Set.S with type elt = reason

(** [Known s] — bounded, sound over-approximation; [Top (known, rs)] —
    unbounded, one reason per witness, with the resolved part still carried
    so a ⊤ verdict never hides what IS known to escape. *)
type set = Known of SS.t | Top of SS.t * RS.t

(** The resolved part of a set ([Known s] → [s]; [Top (k, _)] → [k]). *)
val known_part : set -> SS.t

type t

val not_analysed : string

(** Loads functions, calls (with their handler scopes), scopes, origins and
    rebinds. [channel] (default ["exception"]) selects which error channel:
    ["exception"] keeps its historical shape — every [calls] row is an edge,
    and its [exn_origins]/[exn_scopes] are the [channel='exception'] rows
    (FR-029's byte-identical requirement); any other channel's edges are the
    [exn_edges] rows with [role='propagates'] on that channel, and its
    origins/scopes are the rows tagged with that channel name
    (specs/error-channels.md). Raises [Arch_db.Refused] with
    {!not_analysed} when the DB is on the Flat schema or carries no
    [exn_contract] meta flag.

    [~use_builtin_summaries]: fold in a small built-in [Stdlib] summary
    table on the [exception] channel (specs/error-channels.md FR-031) —
    [List.hd]/[List.nth]/[List.tl] -> [Failure], [Hashtbl.find]/
    [List.find]/[List.assoc] -> [Not_found], [Option.get] ->
    [Invalid_argument], [int_of_string] -> [Failure], [String.sub]/
    [String.get] -> [Invalid_argument]. OFF by default — deliberately
    opt-in, so it never silently moves the two external-corpora exception
    numbers the anti-regression gate checks (a config-declared
    [\[summaries\]] entry is unconditional either way: it only ever fires on
    an EXTERNAL callee, i.e. one absent from the index). *)
val load : ?channel:string -> ?use_builtin_summaries:bool -> Arch_db.t -> t

(** Every function-row key ([#id]) with a given display name. *)
val keys_of_name : t -> string -> string list

(** Display name of a key. *)
val name_of : t -> string -> string option

val file_of : t -> string -> string option

val all_keys : t -> string list

val n_origins : t -> int

val n_scopes : t -> int

val n_escaping : t -> int

(** Worklist fixpoint. With [assume_externals_pure], callees outside the index
    contribute nothing (a stated hypothesis — the caller must stamp its output). *)
val solve : ?assume_externals_pure:bool -> t -> set SM.t

val set_to_string : set -> string

(** [BOUNDED: {…}] / [UNBOUNDED (⊤)] / [BOUNDED_UNDER_HYP(externals_pure): {…}]. *)
val verdict : assume_externals_pure:bool -> set -> string

(** [exception | via | how] rows for one node — under ⊤ the known part is
    still listed. *)
val rows_for : t -> assume_externals_pure:bool -> set SM.t -> string -> Arch_db.cell list list

(** One line per reason: [<kind> <witness>]. *)
val reasons_of : set -> string list

val dominant_reason : set -> reason_kind option

(** Canonicalise through [exception A = B] rebinds. *)
val canon : t -> string -> string

(** [is_carrier t key]: is the function-key node a c-carrier of [t]'s loaded
    channel (specs/error-channels.md "Carrier check")? Always [true] for the
    [exception] channel (every node may raise); for a value channel, exactly
    the nodes marked in [channel_carriers] — [may-fail] answers
    [NOT_A_CARRIER(c)] instead of a verdict when this is [false]. *)
val is_carrier : t -> string -> bool
