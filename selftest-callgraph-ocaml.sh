#!/usr/bin/env bash
# selftest-callgraph-ocaml.sh — end-to-end: OCaml Tier-1 CMT producer → arch-query.
# Builds a controlled OCaml module (3 functions, MUST/MAY_TOP/UNREACHABLE patterns),
# compiles it to .cmt via dune, runs arch_callgraph_ocaml (writes to SQLite directly),
# and asserts all three soundness verdicts (REACHABLE/UNREACHABLE/UNKNOWN).
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
Q="$HERE/arch-query"
fails=0
note()  { echo "FAIL: $*" >&2; fails=$((fails+1)); }
say()   { "$Q" "$@" 2>&1; }
command -v opam    >/dev/null 2>&1 || { echo "selftest-callgraph-ocaml: opam required" >&2; exit 2; }
command -v sqlite3 >/dev/null 2>&1 || { echo "selftest-callgraph-ocaml: sqlite3 required" >&2; exit 2; }

# Use locally built binary (standalone — no EPURE_SRC dependency)
BIN_INSTALL="$HERE/_build/install/default/bin/arch_callgraph_ocaml"
BIN_DEFAULT="$HERE/_build/default/bin/arch_callgraph_ocaml/arch_callgraph_ocaml.exe"
if [ -x "$BIN_INSTALL" ]; then
  BIN="$BIN_INSTALL"
elif [ -x "$BIN_DEFAULT" ]; then
  BIN="$BIN_DEFAULT"
else
  echo "selftest-callgraph-ocaml: arch_callgraph_ocaml not built — run ./build.sh first" >&2
  exit 2
fi

TMPDIR_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMPDIR_ROOT"' EXIT

# ---------- controlled OCaml module ----------
# Functions:
#   add / mul: pure arithmetic, no higher-order → all calls MUST
#   clean_entry: calls only locally-defined top-level functions → no MAY_TOP in its closure
#     → island is UNREACHABLE from clean_entry
#   apply_fn: takes a function PARAMETER f and applies it → f is a Pident not in local_fns → MAY_TOP
#   dirty_entry: calls apply_fn (MUST) which has internal MAY_TOP → UNKNOWN for island from dirty_entry
#   island: never called by anyone → UNREACHABLE from clean_entry, UNKNOWN from dirty_entry
MOD="$TMPDIR_ROOT/testmod"
mkdir -p "$MOD"
cat > "$MOD/dune-project" <<'DUNEPROJ'
(lang dune 3.0)
DUNEPROJ
cat > "$MOD/dune" <<'DUNEFILE'
(library
 (name testcg)
 (modules testcg))
DUNEFILE
cat > "$MOD/testcg.ml" <<'OCAML'
(* Controlled test module for arch_callgraph_ocaml selftest.
   NO higher-order calls in clean_entry's closure (no lambdas passed to stdlib);
   only direct top-level function applications → all MUST, no MAY_TOP.
   dirty_entry's closure contains apply_fn which has MAY_TOP (function parameter call). *)

let add (x : int) (y : int) : int = x + y
let mul (x : int) (y : int) : int = x * y
let island () : int = 99

(** All calls in the closure of direct_calc and clean_entry are MUST:
    only top-level locally-defined functions (add, mul) and no higher-order args. *)
let direct_calc (n : int) : int = add n 1
let clean_entry (n : int) : int = add (direct_calc n) (mul 2 n)

(** apply_fn takes a function parameter f — at the call site f x,
    f is a Pident not in local_fns → MAY_TOP emitted. *)
let apply_fn (f : int -> int) (x : int) : int = f x

(** dirty_entry calls apply_fn (MUST, it's top-level), but apply_fn internally
    has a MAY_TOP edge (the parameter call) — so dirty_entry's closure reaches MAY_TOP. *)
let dirty_entry () : int = apply_fn (fun n -> n + 1) 42
OCAML

# Build the module to produce .cmt files
( cd "$MOD" && opam exec -- dune build 2>/tmp/dune-err.txt ) \
  || { cat /tmp/dune-err.txt >&2; note "dune build of test module failed"; }
CMT_DIR="$MOD/_build/default"
[ -d "$CMT_DIR" ] || { cat /tmp/dune-err.txt >&2; note "dune build dir not found"; exit 1; }

# ---------- run arch_callgraph_ocaml (writes directly to SQLite DB) ----------
DB="$TMPDIR_ROOT/test.db"
SCHEMA="$HERE/architecture-schema.sql"
"$BIN" --build-dir "$CMT_DIR" --db-path "$DB" --schema-path "$SCHEMA" 2>/tmp/ocaml-stderr.txt
bin_rc=$?
[ "$bin_rc" -eq 0 ] || {
  cat /tmp/ocaml-stderr.txt >&2
  note "arch_callgraph_ocaml failed (exit $bin_rc)"
}
[ -f "$DB" ] || { note "DB not produced"; exit 1; }

nfn=$(sqlite3 "$DB" "SELECT count(*) FROM functions;")
[ "$nfn" -gt 0 ] || note "DB has 0 functions — producer emitted nothing"

# ---------- discover function names (ModuleName = Testcg) ----------
fn_clean=$(sqlite3 "$DB"  "SELECT name FROM functions WHERE name LIKE '%clean_entry%' LIMIT 1;")
fn_dirty=$(sqlite3 "$DB"  "SELECT name FROM functions WHERE name LIKE '%dirty_entry%' LIMIT 1;")
fn_island=$(sqlite3 "$DB" "SELECT name FROM functions WHERE name LIKE '%island%' LIMIT 1;")
fn_add=$(sqlite3 "$DB"    "SELECT name FROM functions WHERE name LIKE '%.add' LIMIT 1;")
fn_apply=$(sqlite3 "$DB"  "SELECT name FROM functions WHERE name LIKE '%apply_fn%' LIMIT 1;")

[ -n "$fn_clean"  ] || note "function 'clean_entry' not found in DB"
[ -n "$fn_dirty"  ] || note "function 'dirty_entry' not found in DB"
[ -n "$fn_island" ] || note "function 'island' not found in DB"
[ -n "$fn_add"    ] || note "function 'add' not found in DB"
[ -n "$fn_apply"  ] || note "function 'apply_fn' not found in DB"
[ "$fails" -gt 0 ] && { echo "selftest-callgraph-ocaml: FAIL (function discovery)"; exit 1; }

# ---------- reaches: MUST-only under-approx ----------
# clean_entry → direct_calc → add: all MUST
say "$DB" reaches "$fn_clean" "$fn_add" \
  | grep -q 'PATH EXISTS (must-reach)' || note "reaches $fn_clean $fn_add should be a MUST path"
# island is not reachable via MUST edges from clean_entry
say "$DB" reaches "$fn_clean" "$fn_island" \
  | grep -q 'no MUST path' || note "reaches $fn_clean $fn_island should be no MUST path"

# ---------- unreachable: sound over-approx ----------
# clean_entry closure: add/mul/direct_calc/clean_entry — no MAY_TOP → island UNREACHABLE
say "$DB" unreachable "$fn_clean" "$fn_island" \
  | grep -q 'UNREACHABLE:' || note "unreachable $fn_clean $fn_island should be UNREACHABLE"
# safety: must NOT be REACHABLE (distinct from UNREACHABLE:)
say "$DB" unreachable "$fn_clean" "$fn_island" \
  | grep -q 'REACHABLE (may-reach)' && note "unreachable $fn_clean $fn_island must NOT be REACHABLE"

# dirty_entry → apply_fn (MUST) → *TOP* (MAY_TOP) → UNKNOWN for island
say "$DB" unreachable "$fn_dirty" "$fn_island" \
  | grep -q 'UNKNOWN:' || note "unreachable $fn_dirty $fn_island should be UNKNOWN (apply_fn has MAY_TOP)"
# safety: must NOT be UNREACHABLE
say "$DB" unreachable "$fn_dirty" "$fn_island" \
  | grep -q 'UNREACHABLE: no' && note "unreachable $fn_dirty $fn_island must NOT be UNREACHABLE (MAY_TOP reachable)"

# clean_entry reaches add (MUST path) → REACHABLE
say "$DB" unreachable "$fn_clean" "$fn_add" \
  | grep -q 'REACHABLE (may-reach)' || note "unreachable $fn_clean $fn_add should be REACHABLE"

# ---------- escapes ----------
# dirty_entry should have escaping function (apply_fn reaches *TOP*)
say "$DB" escapes "$fn_dirty" | grep -q '.' \
  || note "escapes $fn_dirty should list at least one escaping function"
# clean_entry should have no escapes
esc_clean=$(say "$DB" escapes "$fn_clean" 2>&1)
echo "$esc_clean" | grep -qE 'no escaping|0 functions|^$' 2>/dev/null || \
  [ -z "$(echo "$esc_clean" | grep -v '^$')" ] || \
  echo "$esc_clean" | grep -q 'no escaping' || \
  note "escapes $fn_clean should have no MAY_TOP in closure (got: $esc_clean)"

# ---------- edge-kind integrity ----------
bad=$(sqlite3 "$DB" "SELECT count(*) FROM calls WHERE kind IS NULL OR kind NOT IN ('MUST','MAY_ENUMERATED','MAY_TOP');")
[ "$bad" -eq 0 ] || note "DB has $bad edges with missing/invalid kind"

if [ "$fails" -eq 0 ]; then
  echo "arch-index callgraph-ocaml selftest: PASS"
  exit 0
else
  echo "arch-index callgraph-ocaml selftest: FAIL ($fails)"
  exit 1
fi
