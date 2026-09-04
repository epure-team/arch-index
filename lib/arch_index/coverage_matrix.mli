(******************************************************************************)
(*                                                                            *)
(* Copyright (c) 2026 Epure Team                                              *)
(* All rights reserved.                                                       *)
(*                                                                            *)
(******************************************************************************)

(** Roadmap 1.3: the honest-absence guarantee.

    One row per (language, analysis) pair a run against a TARGET project
    could have attempted. A language/analysis with no invocable producer is
    recorded as [Not_analysed] with an install/build instruction, not left as
    silence — the inverse of #23 (a missing LSP binary producing an empty
    database with exit 0).

    Six analysis kinds exist in the roadmap's own vocabulary
    (callgraph/effects/cfg/decisions/coverage/types), but they are NOT
    uniformly invocable: [callgraph] and [effects] are real, independently
    invocable producers per language; [cfg] and [types] are properties
    EMITTED BY the callgraph producer for a language, not separate binaries,
    so their coverage rows mirror the callgraph row rather than being
    independently probed; [coverage] (test-line coverage) requires an
    externally-supplied LCOV tracefile this module cannot discover on its
    own; [decisions] ([poc/decision-lint]) is a proof-of-concept outside the
    main dune build entirely. Each is handled on its own honest terms rather
    than forced through one lookup mechanism — see [compute]'s doc for the
    per-kind detection strategy actually used. *)

type status = Covered | Not_analysed | Failed | Partial

(** One row of the coverage matrix.

    {pre}
    (none)

    {post}
    [language] is [None] for a cross-language analysis ([coverage],
    [decisions]) not scoped to a single language.

    {violators}
    (none)

    {violates}
    (none) *)
type row = {language : string option; analysis : string; status : status; detail : string option}

(** [status_to_string s] — the exact string this status is stored as in
    [analysis_coverage.status] (and the CHECK constraint's vocabulary).

    {pre}
    (none)

    {post}
    Returns ["covered"], ["not_analysed"], ["failed"], or ["partial"].

    {violators}
    (none)

    {violates}
    (none) *)
val status_to_string : status -> string

(** [find_sibling_tool ~from_dir rel] searches upward from [from_dir] (trying
    both [rel] and [_build/default/rel] at each ancestor, mirroring the
    convention every producer wrapper script in this repo uses to find its
    own compiled binary), then from the current working directory if that
    search fails, for an executable file at the relative path [rel].

    {pre}
    (none)

    {post}
    [Some path] to the first executable match found, or [None] if no
    ancestor of [from_dir] or the current directory has one.

    {violators}
    (none)

    {violates}
    (none) *)
val find_sibling_tool : from_dir:string -> string -> string option

(** [find_repo_root ~from_dir] locates this arch-index checkout's own SOURCE
    root by searching upward from [from_dir] (then the current working
    directory) for a directory that contains both [architecture-schema.sql]
    and a [_build] subdirectory. Both conditions together, not
    [architecture-schema.sql] alone: dune mirrors every file it depends on
    into [_build/default/] as part of its own build sandbox, so
    [_build/default/architecture-schema.sql] is a real, separate file dune
    creates — a marker-alone search starting from inside
    [_build/default/bin/...] (where every executable built by this project
    lives) finds THAT copy first, one directory short of the genuine root.
    [_build/default] itself never contains a further [_build] subdirectory
    of its own, so requiring both conditions cannot match the mirror.

    {pre}
    (none)

    {post}
    [Some dir] naming the first ancestor (of [from_dir] or the current
    directory) satisfying both conditions, or [None] if neither search finds
    one.

    {violators}
    (none)

    {violates}
    (none) *)
val find_repo_root : from_dir:string -> string option

(** [compute ~project_dir ~repo_root ?lcov ()] builds the full coverage
    matrix for [project_dir] (the project being analysed).

    Per-kind detection strategy:
    - [callgraph]: OCaml — [Some d] when [project_dir/_build/default] exists
      and contains at least one [.cmt]/[.cmti] file ([Covered]), present but
      empty ([Partial]), absent ([Not_analysed], "run dune build first").
      Go/Rust — availability of the DRIVER each repo-root wrapper script
      itself gates ([repo_root/bin/arch-callgraph-go]; one of
      [callgraph-rust/target/{release,debug}] or
      [$CARGO_TARGET_DIR/{release,debug}] for Rust), not the wrapper
      script's own existence — the wrapper is checked into git and always
      present, so checking it would report [Covered] on every checkout
      regardless of whether the driver behind it is built. Checked from
      [repo_root], NOT [project_dir] — these are tools THIS installation
      ships, not something the target project provides. Every other
      language registered in {!Language_registry} — {!Language_registry.lookup}
      against [project_dir], [detail] filled from
      {!Language_registry.lsp_install_instruction} on failure.
    - [effects]: OCaml — availability of the sibling [arch_effects_ocaml]
      binary (a plain bundled executable, so "built" is the only
      precondition). Every other language — [Not_analysed], "no effects
      producer ships for this language" (Go's effects producer exists only
      as test-harness infrastructure today, not a shipped binary — see
      [coverage_matrix.ml]'s own comment for why this is not silently
      promoted to [Covered]).
    - [cfg], [types]: NOT independently invoked — each language's row
      mirrors that language's own [callgraph] row's status, with [detail]
      noting the derivation.
    - [coverage] (test-line): language [None]. [Not_analysed] ("requires an
      externally-supplied LCOV tracefile") unless [lcov] names an existing
      file AND the sibling [arch_coverage] binary is available, in which
      case [Covered].
    - [decisions]: language [None]. Always [Not_analysed] —
      [poc/decision-lint] is outside the main dune build graph.

    {pre}
    [project_dir] should be a real, readable directory. [repo_root] should
    be this arch-index checkout's own root (where its wrapper scripts live).

    {post}
    Returns one row per (language, analysis) pair considered — every
    language {!Language_registry.detect_language_roots} finds in
    [project_dir], times every analysis kind whose scope includes that
    language, plus the two cross-language rows.

    {violators}
    (none)

    {violates}
    (none) *)
(** [db_path] is the database this run will WRITE its rows into. It is read
    first, read-only and best-effort, for [comment_db_meta.error_contract] —
    the record of which error channels a producer actually emitted, written
    only after the transaction carrying those rows commits, so its presence is
    a completion marker rather than a statement of intent.

    The [error_channels] row is then:
    - [Covered] when the contract parses and names at least one channel. A
      SHORTER contract is still covered: a built-in channel whose carrier type
      does not occur in the corpus is deliberately omitted by the producer, so
      fewer channels means less to analyse, not less analysis. WHICH channels
      ran is stated in the detail, where an [exception]-only database still
      reads differently from one carrying all three.
    - [Not_analysed] when the contract is unparseable or names nothing, or when
      the database HAS been indexed and carries no contract at all — an older
      producer, or a run that did not complete. Answering from capability there
      would report an analysis that demonstrably did not record itself.
    - derived from the callgraph probe when there is no database yet, which is
      the one case where capability is the honest answer: this run is about to
      create it.

    Any read failure is treated as "no evidence", never an error. *)
val compute :
  project_dir:string -> repo_root:string -> ?lcov:string -> ?db_path:string -> unit -> row list

(** [write_coverage db rows] replaces the entire contents of
    [analysis_coverage] with [rows] — snapshot semantics: this describes the
    run that just computed [rows], not an accumulating history.

    {pre}
    [db] must already have the [analysis_coverage] table (any schema that
    includes [architecture-schema.sql] does).

    {post}
    [analysis_coverage] contains exactly [rows] afterward. Returns unit.

    {violators}
    (none)

    {violates}
    (none) *)
val write_coverage : Sqlite3.db -> row list -> unit

(** [has_gap rows] — whether any row is [Not_analysed] or [Failed]. Callers
    use this to decide an exit code: a gap without [--allow-partial] is a
    hard failure, per the roadmap's own ratchet ("a non-zero exit unless
    --allow-partial is given").

    {pre}
    (none)

    {post}
    Returns a bool.

    {violators}
    (none)

    {violates}
    (none) *)
val has_gap : row list -> bool
