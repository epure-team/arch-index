#!/usr/bin/env bash
# selftest-ocaml-shapes.sh — broad regression cover for the OCaml CMT indexer.
#
# selftest-callgraph-ocaml.sh pins the three soundness verdicts on a flat module
# and selftest-callgraph-nested.sh pins the nested-module descent of #16.  This
# one sweeps the module-language shapes around them: deep nesting, curried and
# applied functors, shadowing between a toplevel and a nested homonym, local and
# first-class modules, operators, mutual recursion, classes, and the type side
# of all of it.
#
# Every assertion states a property, not an implementation detail, so a shape
# that is deliberately NOT indexed (an application, a local module) is asserted
# absent rather than left unmentioned -- that is what keeps a later "improvement"
# from silently doubling rows.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
Q="$HERE/arch-query"
fails=0
note() { echo "FAIL: $*" >&2; fails=$((fails+1)); }
say()  { "$Q" "$@" 2>&1; }
command -v opam    >/dev/null 2>&1 || { echo "selftest-ocaml-shapes: opam required" >&2; exit 2; }
command -v sqlite3 >/dev/null 2>&1 || { echo "selftest-ocaml-shapes: sqlite3 required" >&2; exit 2; }

eval "$(cd "$HERE" && opam env 2>/dev/null)" || true

BIN_INSTALL="$HERE/_build/install/default/bin/arch_callgraph_ocaml"
BIN_DEFAULT="$HERE/_build/default/bin/arch_callgraph_ocaml/arch_callgraph_ocaml.exe"
if [ -x "$BIN_INSTALL" ]; then
  BIN="$BIN_INSTALL"
elif [ -x "$BIN_DEFAULT" ]; then
  BIN="$BIN_DEFAULT"
else
  echo "selftest-ocaml-shapes: arch_callgraph_ocaml not built — run ./build.sh first" >&2
  exit 2
fi

TMPDIR_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMPDIR_ROOT"' EXIT

MOD="$TMPDIR_ROOT/shapes"
mkdir -p "$MOD"
cat > "$MOD/dune-project" <<'DUNEPROJ'
(lang dune 3.0)
DUNEPROJ
cat > "$MOD/dune" <<'DUNEFILE'
(library
 (name shapes)
 (modules shapes)
 ; Several bindings exist only to be looked for in the index.
 (flags (:standard -w -32-26-27-34-37-69)))
DUNEFILE

cat > "$MOD/shapes.ml" <<'OCAML'
let base (x : int) : int = x + 1

(* ---- deep nesting: three levels ---- *)
module L1 = struct
  module L2 = struct
    module L3 = struct
      let deep (x : int) : int = base x
    end
  end
end

(* ---- shadowing: a nested homonym must not disturb the toplevel ---- *)
type t = {a : int}

let shadowed (x : int) : int = x

module Shadow = struct
  type t = Variant of string

  let shadowed (x : int) : int = base x
end

(* ---- curried functor, and a functor applied to another's result ---- *)
module type S = sig
  val k : int
end

module Impl = struct
  let k = 2
end

module Curried (A : S) (B : S) = struct
  let sum () : int = A.k + B.k
end

module Wrap (A : S) = struct
  let doubled () : int = A.k * 2
end

module Applied = Curried (Impl) (Impl)
module WrapApplied = Wrap (Impl)

(* ---- operators and mutual recursion ---- *)
let ( >>= ) (x : int) (f : int -> int) : int = f x

let rec even (n : int) : bool = if n = 0 then true else odd (n - 1)
and odd (n : int) : bool = if n = 0 then false else even (n - 1)

(* ---- local module in expression position: defines nothing at file scope ---- *)
let uses_local_module () : int =
  let module Local = struct
    let inner_local () : int = 7
  end in
  Local.inner_local ()

(* ---- first-class module: dynamic, nothing to index ---- *)
let uses_first_class (m : (module S)) : int =
  let module M = (val m) in
  M.k

(* ---- module type of ---- *)
module type ImplLike = module type of Impl

(* ---- include of a nested module: brings bindings into this scope ---- *)
module Source = struct
  let from_source () : int = base 0
end

include Source

(* ---- a class: the indexer must not choke on it ---- *)
class counter =
  object
    val mutable n = 0

    method bump = n <- n + 1
  end

(* ---- exception and a nested type carrying fields ---- *)
exception Boom of string

module Types = struct
  type record = {field_one : int; field_two : string}

  type variant =
    | First
    | Second of int
end
OCAML

cat > "$MOD/shapes.mli" <<'OCAMLI'
val base : int -> int

module L1 : sig
  module L2 : sig
    module L3 : sig
      val deep : int -> int
    end
  end
end

type t = {a : int}

val shadowed : int -> int

module Shadow : sig
  type t = Variant of string

  val shadowed : int -> int
end

module type S = sig
  val k : int
end

module Impl : S

module Curried (A : S) (B : S) : sig
  val sum : unit -> int
end

module Wrap (A : S) : sig
  val doubled : unit -> int
end

val ( >>= ) : int -> (int -> int) -> int
val even : int -> bool
val odd : int -> bool
val uses_local_module : unit -> int
val uses_first_class : (module S) -> int
val from_source : unit -> int

exception Boom of string

module Types : sig
  type record = {field_one : int; field_two : string}

  type variant =
    | First
    | Second of int
end
OCAMLI

( cd "$MOD" && dune build 2>/tmp/dune-shapes-err.txt ) \
  || { cat /tmp/dune-shapes-err.txt >&2; note "dune build of fixture failed"; }
CMT_DIR="$MOD/_build/default"
[ -d "$CMT_DIR" ] || { cat /tmp/dune-shapes-err.txt >&2; note "dune build dir not found"; exit 1; }

DB="$TMPDIR_ROOT/shapes.db"
"$BIN" --build-dir "$CMT_DIR" --db-path "$DB" --schema-path "$HERE/architecture-schema.sql" \
  2>/tmp/shapes-stderr.txt
bin_rc=$?
[ "$bin_rc" -eq 0 ] || { cat /tmp/shapes-stderr.txt >&2; note "arch_callgraph_ocaml failed (exit $bin_rc)"; }
[ -f "$DB" ] || { note "DB not produced"; exit 1; }

count() { sqlite3 "$DB" "SELECT count(*) FROM functions WHERE name = '$1';"; }
expose() { sqlite3 "$DB" "SELECT COALESCE(exposed, -1) FROM functions WHERE name = '$1';"; }
tcount() { sqlite3 "$DB" "SELECT count(*) FROM types WHERE name = '$1';"; }

# ---------- present exactly once, under their definition path ----------
for want in \
  'base' 'shadowed' 'even' 'odd' 'uses_local_module' 'uses_first_class' \
  'L1.L2.L3.deep' 'Shadow.shadowed' 'Curried.sum' 'Wrap.doubled' \
  'Source.from_source'
do
  got=$(count "$want")
  [ "$got" = "1" ] || note "expected exactly one function row '$want', got $got"
done

# ---------- exposed through the .mli, however deeply nested ----------
for want in 'base' 'L1.L2.L3.deep' 'Shadow.shadowed' 'Curried.sum' 'Wrap.doubled' 'even' 'odd'; do
  got=$(expose "$want")
  [ "$got" = "1" ] || note "'$want' should be exposed = 1, got '${got:-missing}'"
done

# ---------- shadowing: the toplevel binding is untouched by its namesake ----------
# Both rows must exist, and the toplevel one must not have inherited the nested
# one's body: a REPLACE on a shared key is exactly the bug this pins.
[ "$(count 'shadowed')" = "1" ] || note "toplevel 'shadowed' lost to its nested homonym"
[ "$(count 'Shadow.shadowed')" = "1" ] || note "'Shadow.shadowed' missing"
callers_of_base=$(sqlite3 "$DB" \
  "SELECT count(*) FROM calls c JOIN functions f ON f.id = c.caller_id
    WHERE c.callee_id = (SELECT id FROM functions WHERE name = 'shadowed' LIMIT 1);")
[ "${callers_of_base:-0}" = "0" ] \
  || note "toplevel 'shadowed' should have no callers; it looks merged with Shadow.shadowed"

# ---------- types are qualified the same way values are ----------
[ "$(tcount 't')" = "1" ] || note "toplevel type 't' should survive its nested homonym"
[ "$(tcount 'Shadow.t')" = "1" ] || note "nested type 'Shadow.t' should be indexed under its path"
[ "$(tcount 'Types.record')" = "1" ] || note "'Types.record' should be indexed"
[ "$(tcount 'Types.variant')" = "1" ] || note "'Types.variant' should be indexed"
fields=$(sqlite3 "$DB" \
  "SELECT count(*) FROM type_fields WHERE type_id = (SELECT id FROM types WHERE name = 't' LIMIT 1);")
[ "${fields:-0}" -ge 1 ] || note "toplevel type 't' lost its fields (cascade from a REPLACE?)"

# ---------- an application defines nothing new ----------
for absent in 'Applied.sum' 'WrapApplied.doubled'; do
  got=$(count "$absent")
  [ "$got" = "0" ] \
    || note "'$absent' should not exist: a functor application indexes no new definition ($got row(s))"
done

# ---------- a local module lives in an expression, not at file scope ----------
got=$(sqlite3 "$DB" "SELECT count(*) FROM functions WHERE name LIKE '%inner_local%';")
[ "$got" = "0" ] \
  || note "'inner_local' is bound by a let module inside a function body and is not a file-scope definition ($got row(s))"

# ---------- include of a NAMED module re-exports without defining ----------
# `include Source` names definitions written in Source, so the row stays
# Source.from_source and nothing is indexed at the toplevel.  The .mli's
# `val from_source` therefore records an exposure key that matches no row.
# This is the documented boundary of "indexed where it is written"; the inline
# `include struct ... end` form is covered by selftest-callgraph-nested.sh.
[ "$(count 'from_source')" = "0" ] \
  || note "'include Source' should not create a second row at the toplevel; definitions are indexed where they are written"
[ "$(count 'Source.from_source')" = "1" ] \
  || note "'Source.from_source' should be indexed where it is defined"

# ---------- calls resolve across every nesting level ----------
base_id=$(sqlite3 "$DB" "SELECT id FROM functions WHERE name = 'base' LIMIT 1;")
if [ -n "$base_id" ]; then
  callers=$(sqlite3 "$DB" \
    "SELECT group_concat(f.name) FROM calls c JOIN functions f ON f.id = c.caller_id
      WHERE c.callee_id = $base_id;")
  for expected in 'L1.L2.L3.deep' 'Shadow.shadowed' 'Source.from_source'; do
    case "$callers" in
      *"$expected"*) ;;
      *) note "'base' should record a call from '$expected'; callers were: ${callers:-none}" ;;
    esac
  done
else
  note "'base' not found in DB"
fi

# ---------- mutual recursion is an edge in both directions ----------
for pair in 'even odd' 'odd even'; do
  set -- $pair
  n=$(sqlite3 "$DB" \
    "SELECT count(*) FROM calls c
       JOIN functions f ON f.id = c.caller_id
      WHERE f.name = '$1' AND c.callee_id = (SELECT id FROM functions WHERE name = '$2' LIMIT 1);")
  [ "${n:-0}" -ge 1 ] || note "mutual recursion: '$1' should record a call to '$2'"
done

# ---------- reachability across three levels of nesting ----------
say "$DB" reaches 'L1.L2.L3.deep' 'base' | grep -q 'PATH EXISTS (must-reach)' \
  || note "reaches L1.L2.L3.deep base should be a MUST path"

# ---------- the class did not derail the walk ----------
# No assertion on how methods are represented -- only that indexing completed
# and the definitions after the class are still there.
[ "$(count 'Source.from_source')" = "1" ] \
  || note "definitions after the class declaration are missing: the walk stopped early"

# ---------- a qualified cross-module call binds to the right homonym --------
# Fx.G1.B.f can be read as unit B holding f, or unit G1 holding B.f. Keeping
# only the last component picks the first reading and binds to an unrelated
# b.ml that happens to define an f -- a confident MUST edge to the wrong
# function.
XMOD="$TMPDIR_ROOT/xmod"
mkdir -p "$XMOD"
cat > "$XMOD/dune-project" <<'XPROJ'
(lang dune 3.0)
XPROJ
cat > "$XMOD/dune" <<'XDUNE'
(library
 (name qual)
 (modules b g1 g2)
 (flags (:standard -w -32)))
XDUNE
printf 'let f (x : int) : int = x + 100\n' > "$XMOD/b.ml"
printf 'module B = struct\n  let f (x : int) : int = x + 1\nend\n' > "$XMOD/g1.ml"
printf 'let use () : int = G1.B.f 1\n' > "$XMOD/g2.ml"

if ( cd "$XMOD" && dune build 2>/tmp/dune-xmod-err.txt ); then
  XDB="$TMPDIR_ROOT/xmod.db"
  "$BIN" --build-dir "$XMOD/_build/default" --db-path "$XDB" \
    --schema-path "$HERE/architecture-schema.sql" >/dev/null 2>&1
  want=$(sqlite3 "$XDB" "SELECT f.id FROM functions f JOIN modules m ON m.id = f.module_id
                          WHERE f.name = 'B.f' AND m.path LIKE '%g1.ml';")
  got=$(sqlite3 "$XDB" "SELECT c.callee_id FROM calls c JOIN functions f ON f.id = c.caller_id
                         WHERE f.name = 'use';")
  if [ -z "$want" ]; then
    note "cross-module fixture: 'B.f' not indexed in g1.ml"
  elif [ "${got:-}" != "$want" ]; then
    wrong=$(sqlite3 "$XDB" "SELECT name FROM functions WHERE id = ${got:-0};")
    note "qualified call G1.B.f resolved to '${wrong:-nothing}' (id ${got:-none}) instead of g1.ml's B.f (id $want)"
  fi
else
  cat /tmp/dune-xmod-err.txt >&2
  note "cross-module fixture failed to build"
fi

if [ "$fails" -eq 0 ]; then
  echo "selftest-ocaml-shapes: PASS"
  exit 0
else
  echo "selftest-ocaml-shapes: FAIL ($fails)"
  exit 1
fi
