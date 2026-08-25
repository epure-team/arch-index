(******************************************************************************)
(*                                                                            *)
(* Copyright (c) 2026 Epure Team                                              *)
(* All rights reserved.                                                       *)
(*                                                                            *)
(******************************************************************************)

(** LSP subprocess manager built on jsonrpc_client/stdio_transport. *)

(** [file_uri_of_path path] is the [file://] URI for [path], absolutised against
    the current directory when [path] is relative, with ".", "..", and doubled
    separators resolved.

    ".." is resolved LEXICALLY, not through the filesystem: no symlink is
    followed, so ["/link/../x"] becomes ["/x"] whatever [/link] points at. A
    ".." with nothing left to pop saturates at the root rather than escaping
    it.

    A [file://] URI must carry an absolute path. The project directory arrives as
    a Cmdliner [dir] argument, which returns the string exactly as typed, so
    `--project .` yielded [file://./src/foo.ml] — not a valid file URI. The
    server then cannot open the document, every [textDocument/documentSymbol]
    comes back empty, and the run writes an empty index while reporting success.

    {pre}
    (none)

    {post}
    The result starts with [file:///] and contains no ".", ".." or empty
    segment. [path_of_file_uri] of the result is the absolutised path.

    {violators}
    (none)

    {violates}
    (none) *)
val file_uri_of_path : string -> string

(** [relative_path ~project_dir abs_path] is [abs_path] made relative to
    [project_dir], or [abs_path] unchanged when it lies outside it.

    BOTH arguments are normalised first (see {!file_uri_of_path} for what that
    means: lexical [.]/[..] resolution, no symlink following, saturation at the
    root). Normalising only [project_dir] was the original bug — it was compared
    verbatim against an absolute path from the server, so a relative [--project]
    never matched and every stored path stayed absolute, making the index
    machine-specific. Normalising only one side leaves the same class of miss
    whenever the server's path carries a [.] or [..] segment.

    Matching is lexical and requires a segment boundary: [project_dir] of
    [/a/b] does not capture [/a/bc.ml]. When [project_dir] normalises to the
    filesystem root, the root IS the separator, so the result is [abs_path]
    with its single leading [/] removed.

    {pre}
    [abs_path] is expected to be absolute. A relative one is absolutised
    against the process CWD, which may then match [project_dir] and yield a
    plausible-looking but unintended relative result — callers pass paths
    derived from server URIs, which are absolute.

    {post}
    Returns a path with no leading separator when [abs_path] is under
    [project_dir]; returns the normalised [abs_path] unchanged otherwise.

    {violators}
    (none)

    {violates}
    (none) *)
val relative_path : project_dir:string -> string -> string

(** [path_of_file_uri uri] strips a leading [file://] if present, returning the
    path. A string that is not a [file://] URI is returned unchanged rather than
    mangled — the LSP peer is not obliged to echo the scheme.

    The inverse of {!file_uri_of_path}. Both halves live together because they
    were previously three separate copies of the strip in two modules, free to
    drift apart from the construction they mirror.

    {pre}
    (none)

    {post}
    Returns [uri] without its [file://] prefix when it has one, else [uri].

    {violators}
    (none)

    {violates}
    (none) *)
val path_of_file_uri : string -> string

type t

(** [start ~sw ~env ~command ~args ~project_dir ?init_options ()] spawns the
    LSP server, performs the initialize/initialized handshake, returns a
    connected client.  [init_options] is forwarded as [initializationOptions]
    in the LSP initialize request (defaults to [`Null]).
    Returns [Error msg] if the server fails to start or initialize. *)
val start :
  sw:Eio.Switch.t ->
  env:Eio_unix.Stdenv.base ->
  command:string ->
  args:string list ->
  project_dir:string ->
  ?init_options:Yojson.Safe.t ->
  ?ready_timeout:float ->
  ?ready_grace:float ->
  ?ready_quiet:float ->
  unit ->
  (t, string) result

(** [request t ~method_ ~params ()] sends a JSON-RPC 2.0 request and returns
    the result as a Yojson value. Returns [Error msg] on failure. *)
val request :
  t ->
  method_:string ->
  ?params:Yojson.Safe.t ->
  unit ->
  (Yojson.Safe.t, string) result

(** [notify t ~method_ ~params ()] sends a JSON-RPC notification (no response). *)
val notify : t -> method_:string -> ?params:Yojson.Safe.t -> unit -> unit

(** What {!start}'s handshake learned about the server's background work.

    {!start} waits for it because a server that is still loading answers
    [prepareCallHierarchy] with an empty list rather than an error, making
    "still indexing" indistinguishable from "no calls".

    The four outcomes are NOT interchangeable, which is why this is not a bool:

    - [Reported] — the server's indexing phase closed. Authoritative.
    - [Quiescent] — every token it opened has closed and nothing has arrived for
      [ready_quiet] seconds. A HEURISTIC: a server whose next phase begins after
      a longer gap than that window is indistinguishable from one that has
      finished, and rust-analyzer has exactly that shape. Do not treat it as a
      fact about the index.
    - [No_progress] — [ready_grace] elapsed with no progress at all. Expected
      from a server with nothing to do, or one that does not report progress.
    - [Timed_out] — [ready_timeout] elapsed with work still in flight. The
      budget was too small, or the server is much slower than expected.
    - [Stream_ended] — the server closed its output during the handshake. No
      budget would have helped; kept distinct from [Timed_out] because the two
      send an operator to opposite fixes.

    None of these is an error. Anything other than [Reported] means the caller
    learned nothing it can rely on and should fall back to its own bounded
    retry. *)
type readiness =
  | Reported
  | Quiescent
  | No_progress
  | Timed_out
  | Stream_ended

val readiness : t -> readiness
val readiness_to_string : readiness -> string

(** [shutdown t] sends shutdown + exit, waits for process exit. *)
val shutdown : t -> unit
