(******************************************************************************)
(*                                                                            *)
(* Copyright (c) 2026 Epure Team                                              *)
(* All rights reserved.                                                       *)
(*                                                                            *)
(******************************************************************************)

(** Body comparison for duplicate-function detection.

    Extracts function bodies from source files using the line ranges stored in
    the architecture DB, normalises them, and groups occurrences by content
    hash so callers can determine whether named functions across modules are
    truly identical or merely share a name. *)

(** One occurrence of a named function in the index. *)
type occurrence = {
  path : string;  (** Source-relative path, e.g. [src/db/foo_store.ml] *)
  line_start : int;
  line_end : int;
  body : string;  (** Normalised body text *)
  digest : string;  (** Hex MD5 of [body] — used for grouping *)
}

(** Result of comparing all occurrences of a function name. *)
type result =
  | Not_found  (** No function with that name in the DB *)
  | Identical of occurrence list  (** All occurrences have the same body *)
  | Differs of (string * occurrence list) list
      (** [(digest, occurrences)] — at least two distinct bodies *)

(** Compare all occurrences of [fn_name] in the architecture DB.

    Looks up every function whose name exactly matches [fn_name], reads the
    corresponding source lines, normalises whitespace, and groups by content
    hash.

    @param db          Open SQLite handle to [docs/architecture.db].
    @param project_root  Absolute path to the repository root, prepended to
                         module paths when reading source files.
    @param fn_name     The function name to look up (exact match).

    {pre}
    [db] must be an open SQLite connection to the architecture database.

    {post}
    Returns [Not_found] if no match, [Identical occurrences] if all bodies agree, or [Differs groups] if bodies differ.

    {violators}
    (none)

    {violates}
    (none) *)
val compare_bodies : Sqlite3.db -> project_root:string -> string -> result
