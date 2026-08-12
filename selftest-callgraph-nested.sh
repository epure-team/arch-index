#!/usr/bin/env bash
# selftest-callgraph-nested.sh — regression cover for issue #16: functions defined
# inside a nested module or a functor body must be indexed, and a toplevel function
# called only from inside a functor must keep its incoming caller.
#
# Before the fix, the walker registered only the compilation unit's toplevel
# Tstr_value bindings: everything inside `module M = struct ... end` or
# `module Make (P : S) = struct ... end` was absent from the index, and a helper
# called only from a functor body showed zero callers -- so every query crossing a
# functor degraded to UNKNOWN.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
Q="$HERE/arch-query"
fails=0
note()  { echo "FAIL: $*" >&2; fails=$((fails+1)); }
say()   { "$Q" "$@" 2>&1; }
command -v opam    >/dev/null 2>&1 || { echo "selftest-callgraph-nested: opam required" >&2; exit 2; }
command -v sqlite3 >/dev/null 2>&1 || { echo "selftest-callgraph-nested: sqlite3 required" >&2; exit 2; }

# Pin the switch env from the repo root before cd'ing into the fixture dir, as
# opam resolves local switches from CWD.
eval "$(cd "$HERE" && opam env 2>/dev/null)" || true

BIN_INSTALL="$HERE/_build/install/default/bin/arch_callgraph_ocaml"
BIN_DEFAULT="$HERE/_build/default/bin/arch_callgraph_ocaml/arch_callgraph_ocaml.exe"
if [ -x "$BIN_INSTALL" ]; then
  BIN="$BIN_INSTALL"
elif [ -x "$BIN_DEFAULT" ]; then
  BIN="$BIN_DEFAULT"
else
  echo "selftest-callgraph-nested: arch_callgraph_ocaml not built — run ./build.sh first" >&2
  exit 2
fi

TMPDIR_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMPDIR_ROOT"' EXIT

# ---------- controlled OCaml module ----------
# helper      : toplevel, called ONLY from inside the functor body — the regression.
# Make.inner  : defined in a functor body; calls helper.
# Make.outer  : defined in a functor body; calls inner.
# Plain.nested: defined in a plain nested module; calls helper too.
# M           : an application of Make — must NOT produce a second set of rows,
#               because definitions are indexed where they are written.
MOD="$TMPDIR_ROOT/testnested"
mkdir -p "$MOD"
cat > "$MOD/dune-project" <<'DUNEPROJ'
(lang dune 3.0)
DUNEPROJ
cat > "$MOD/dune" <<'DUNEFILE'
(library
 (name testnested)
 (modules testnested)
 ; unused_inner is deliberately unreferenced: it is the dead-code candidate.
 (flags (:standard -w -32)))
DUNEFILE
# The .mli exposes the functor's result signature, so the signature walk has
# something nested to find: without it, Make.inner would be indexed but stay
# exposed = 0 and unscored, and the comment gate would still be blind to it.
cat > "$MOD/testnested.mli" <<'OCAMLI'
val helper : int -> int

module type S = sig
  val base : int
end

module Impl : S

module Make (P : S) : sig
  val apply : (int -> int) -> int -> int

  (** [inner x] adds [P.base] to [x] and hands it to [helper].

      {pre}
      None.

      {post}
      Returns [helper (x + P.base)].

      {violators}
      helper — a change to its arithmetic changes what inner returns.

      {violates}
      (none) *)
  val inner : int -> int

  val outer : unit -> int
end

module Plain : sig
  val nested : unit -> int
end

module type T = sig
  val go : int -> int
end

module Named (P : S) : T

val included_fn : unit -> int

module R1 : sig
  val f : int -> int
end

module R2 : sig
  val g : int -> int
end

module Scoped : sig
  val uses : unit -> int
end

module M : sig
  val inner : int -> int
  val outer : unit -> int
end
OCAMLI
cat > "$MOD/testnested.ml" <<'OCAML'
(* Controlled fixture for the nested-module / functor indexing regression. *)

let helper (x : int) : int = x + 1

module type S = sig
  val base : int
end

module Impl = struct
  let base = 7
end

module Make (P : S) = struct
  let inner (x : int) : int = helper (x + P.base)
  let outer () : int = inner 1

  (* Calls a function parameter: an unresolvable head, so the roots provably
     reach a MAY_TOP edge. *)
  let apply (f : int -> int) (x : int) : int = f x

  (* Nested, not in the .mli, called by nobody: the dead-code candidate. *)
  let unused_inner () : int = 0
end

module Plain = struct
  let nested () : int = helper 0
end

(* A named result signature -- the spelling most .mli files use. *)
module type T = sig
  val go : int -> int
end

module Named (P : S) : T = struct
  let go (x : int) : int = helper (x + P.base)
end

(* include struct: its bindings land in the enclosing scope. *)
include struct
  let included_fn () : int = helper 1
end

(* Recursive modules. *)
module rec R1 : sig
  val f : int -> int
end = struct
  let f x = R2.g x
end

and R2 : sig
  val g : int -> int
end = struct
  let g x = helper x
end

(* An open local to a nested module is not a dependency of this file. *)
module Scoped = struct
  open Stdlib.List

  let uses () : int = length []
end

module M = Make (Impl)
OCAML

( cd "$MOD" && dune build 2>/tmp/dune-nested-err.txt ) \
  || { cat /tmp/dune-nested-err.txt >&2; note "dune build of fixture failed"; }
CMT_DIR="$MOD/_build/default"
[ -d "$CMT_DIR" ] || { cat /tmp/dune-nested-err.txt >&2; note "dune build dir not found"; exit 1; }

DB="$TMPDIR_ROOT/nested.db"
SCHEMA="$HERE/architecture-schema.sql"
"$BIN" --build-dir "$CMT_DIR" --db-path "$DB" --schema-path "$SCHEMA" 2>/tmp/nested-stderr.txt
bin_rc=$?
[ "$bin_rc" -eq 0 ] || { cat /tmp/nested-stderr.txt >&2; note "arch_callgraph_ocaml failed (exit $bin_rc)"; }
[ -f "$DB" ] || { note "DB not produced"; exit 1; }

# ---------- nested definitions are indexed, under their definition path ----------
for want in 'Make.inner' 'Make.outer' 'Plain.nested'; do
  got=$(sqlite3 "$DB" "SELECT count(*) FROM functions WHERE name = '$want';")
  [ "$got" = "1" ] || note "expected exactly one function row named '$want', got $got"
done

# ---------- the regression itself: helper keeps its callers ----------
fn_helper_id=$(sqlite3 "$DB" "SELECT id FROM functions WHERE name = 'helper' LIMIT 1;")
[ -n "$fn_helper_id" ] || note "toplevel function 'helper' not found in DB"
if [ -n "$fn_helper_id" ]; then
  callers=$(sqlite3 "$DB" \
    "SELECT count(DISTINCT c.caller_id) FROM calls c WHERE c.callee_id = $fn_helper_id;")
  # Make.inner and Plain.nested both call it; before the fix this was 0.
  [ "${callers:-0}" -ge 2 ] \
    || note "'helper' should have at least 2 distinct callers from inside nested modules, got ${callers:-0}"
fi

# ---------- the signature walk reaches into the functor's result ----------
# Without it, the row above exists but is invisible to anything gating on
# exposure or on comment quality.
exposed=$(sqlite3 "$DB" "SELECT exposed FROM functions WHERE name = 'Make.inner';")
[ "$exposed" = "1" ] || note "'Make.inner' should be exposed = 1 (got '${exposed:-}'), the .mli declares it"
score=$(sqlite3 "$DB" "SELECT COALESCE(comment_quality_score, -1) FROM functions WHERE name = 'Make.inner';")
[ "${score:--1}" -ge 74 ] \
  || note "'Make.inner' should carry its doc-comment score from the .mli, got '${score:-}'"

# ---------- a functor application defines nothing new ----------
dup=$(sqlite3 "$DB" "SELECT count(*) FROM functions WHERE name LIKE 'M.%';")
[ "$dup" = "0" ] || note "functor application M = Make (Impl) produced $dup extra function row(s); definitions must be indexed once, where they are written"

# ---------- named result signatures, recursive modules, include ----------
# module Named (P : S) : T is the spelling most .mli files use; walking only
# inline sig...end would leave its API indexed but never exposed.
for want in 'Named.go' 'R1.f' 'R2.g' 'included_fn' 'Scoped.uses'; do
  got=$(sqlite3 "$DB" "SELECT COALESCE(exposed, -1) FROM functions WHERE name = '$want';")
  [ "${got:--1}" = "1" ] || note "'$want' should be indexed and exposed = 1, got '${got:-missing}'"
done

# ---------- an open local to a nested module is not a file dependency ----------
leaked=$(sqlite3 "$DB" \
  "SELECT count(*) FROM module_deps WHERE target_path LIKE 'Stdlib.List%';")
[ "${leaked:-0}" = "0" ] \
  || note "the open inside module Scoped leaked into file-scoped module_deps ($leaked row(s))"

# ---------- reachability now discriminates across the functor boundary ----------
say "$DB" reaches 'Make.outer' 'helper' \
  | grep -q 'PATH EXISTS (must-reach)' \
  || note "reaches Make.outer helper should be a MUST path (was UNKNOWN before the fix)"

# ---------- dead-code stays honest once a ⊤ edge is reachable ----------
# Nested definitions whose only caller goes through a functor parameter are
# reachable only via ⊤; claiming them sound-dead would be a false confident
# answer, so the verdict must degrade instead.
# Asserted positively: the column header is literally "verdict_soundness", so
# grepping for "sound" would match the header whatever the verdict says.
dc=$(say "$DB" dead-code)
echo "$dc" | grep -q 'Make.unused_inner' \
  || note "dead-code should list Make.unused_inner, which nothing calls and the .mli does not expose"
echo "$dc" | grep -q 'MAY_TOP reachable' \
  || note "dead-code should degrade its verdict when a MAY_TOP edge is reachable from the roots, and say why"

if [ "$fails" -eq 0 ]; then
  echo "selftest-callgraph-nested: PASS"
  exit 0
else
  echo "selftest-callgraph-nested: FAIL ($fails)"
  exit 1
fi
