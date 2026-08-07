#!/usr/bin/env bash
# selftest-health.sh — A1 (facts) + A2 (measures) health-check subcommands on arch-query:
# missing-docs, missing-mli, type-search, large-files, large-functions, god-modules.
#
# The one rule under test everywhere here: A2 commands are MEASURES, never VERDICTS — they sort
# and report an exact number, they never take a --fail-on-... threshold, and they say so in their
# own output. A1 commands are exact facts and must escape LIKE metacharacters in a free-text
# argument rather than let a literal '_' or '%' act as a wildcard.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
LOAD="$HERE/arch-load"; Q="$HERE/arch-query"
fails=0; note() { echo "FAIL: $*" >&2; fails=$((fails+1)); }
command -v sqlite3 >/dev/null 2>&1 || { echo "selftest-health: sqlite3 required" >&2; exit 2; }
say() { ARCH_QUERY_FORMAT=list "$Q" "$@" 2>&1; }

DB="$(mktemp --suffix=.db)"; rm -f "$DB"
sqlite3 "$DB" < "$HERE/architecture-schema.sql" || { echo "selftest-health: failed to load architecture-schema.sql" >&2; exit 2; }
sqlite3 "$DB" <<'SQL'
INSERT INTO modules(path, lines, has_mli) VALUES
  ('lib/big.ml', 600, 1),
  ('lib/small.ml', 10, 0),
  ('lib/mid.ml', 100, 1);

INSERT INTO functions(module_id, name, signature, line_start, line_end, exposed, intent) VALUES
  ((SELECT id FROM modules WHERE path='lib/big.ml'),   'big_fn',    'int -> string',          1, 205, 1, NULL),
  ((SELECT id FROM modules WHERE path='lib/small.ml'), 'small_fn',  'unit -> unit',           1, 5,   1, 'documented'),
  ((SELECT id FROM modules WHERE path='lib/mid.ml'),   'mid_fn',    'Foo.instance -> bool',   1, 20,  0, NULL),
  ((SELECT id FROM modules WHERE path='lib/mid.ml'),   'another_fn','string -> Foo.instance', 1, 3,   1, NULL),
  ((SELECT id FROM modules WHERE path='lib/mid.ml'),   'fn_us',     'a_b -> c',               1, 1,   0, 'x'),
  ((SELECT id FROM modules WHERE path='lib/mid.ml'),   'fn_x',      'aXb -> c',               1, 1,   0, 'x'),
  ((SELECT id FROM modules WHERE path='lib/big.ml'),   'caller_a',  NULL,                     210, 212, 0, 'x'),
  ((SELECT id FROM modules WHERE path='lib/small.ml'), 'caller_b',  NULL,                     6,   7,   0, 'x');

INSERT INTO calls(caller_id, callee_id, callee_name, call_site, kind) VALUES
  ((SELECT id FROM functions WHERE name='caller_a'), (SELECT id FROM functions WHERE name='big_fn'), 'big_fn', 'x:1', 'MUST'),
  ((SELECT id FROM functions WHERE name='caller_b'), (SELECT id FROM functions WHERE name='big_fn'), 'big_fn', 'x:2', 'MUST'),
  ((SELECT id FROM functions WHERE name='caller_a'), (SELECT id FROM functions WHERE name='mid_fn'), 'mid_fn', 'x:3', 'MUST');
SQL

# ---- A1: missing-docs — exported + no intent -------------------------------------------------
OUT="$(say "$DB" missing-docs)"
echo "$OUT" | grep -q 'lib/big.ml|big_fn|1' || note "missing-docs must list big_fn (exported, no intent)"
echo "$OUT" | grep -q 'lib/mid.ml|another_fn|1' || note "missing-docs must list another_fn (exported, no intent)"
echo "$OUT" | grep -q 'small_fn'  && note "missing-docs must NOT list small_fn (has intent)"
echo "$OUT" | grep -q '\bmid_fn\b' && note "missing-docs must NOT list mid_fn (not exported)"

# ---- A1: missing-mli — has_mli=0 -------------------------------------------------------------
OUT="$(say "$DB" missing-mli)"
echo "$OUT" | grep -q 'lib/small.ml' || note "missing-mli must list lib/small.ml (has_mli=0)"
echo "$OUT" | grep -q 'lib/big.ml'   && note "missing-mli must NOT list lib/big.ml (has_mli=1)"
echo "$OUT" | grep -q 'lib/mid.ml'   && note "missing-mli must NOT list lib/mid.ml (has_mli=1)"

# ---- A1: type-search — substring over signature, with LIKE escaping --------------------------
OUT="$(say "$DB" type-search 'Foo.instance')"
echo "$OUT" | grep -q 'mid_fn'     || note "type-search Foo.instance must list mid_fn (param)"
echo "$OUT" | grep -q 'another_fn' || note "type-search Foo.instance must list another_fn (return)"
N="$(say "$DB" type-search 'Foo.instance' | grep -c .)"
[ "$N" -eq 2 ] || note "type-search Foo.instance must return exactly 2 rows, got $N"
# LIKE-escaping proof: 'a_b' must NOT match 'aXb' — '_' is a SQL wildcard unless escaped.
OUT="$(say "$DB" type-search 'a_b')"
echo "$OUT" | grep -q 'fn_us' || note "type-search a_b must list fn_us (literal a_b)"
echo "$OUT" | grep -q 'fn_x'  && note "type-search a_b must NOT match fn_x (aXb) — '_' must be escaped, not a wildcard"

# ---- A2: large-files — sorted, top-N, no gate -------------------------------------------------
OUT="$(say "$DB" large-files 2)"
N="$(echo "$OUT" | grep -c '^lib/')"
[ "$N" -eq 2 ] || note "large-files 2 must return exactly 2 data rows, got $N"
echo "$OUT" | grep '^lib/' | head -1 | grep -q 'lib/big.ml' || note "large-files must sort DESC by lines (big.ml first)"
say "$DB" large-files | grep -qi 'measure only' || note "large-files must state in its own output that it is a measure, not a gate"

# ---- A2: large-functions — sorted, top-N, no gate ---------------------------------------------
OUT="$(say "$DB" large-functions 3)"
echo "$OUT" | grep -q 'big_fn' || note "large-functions must list big_fn (largest span)"
FIRST_DATA="$(echo "$OUT" | grep '|' | head -1)"
echo "$FIRST_DATA" | grep -q 'big_fn' || note "large-functions must sort DESC by line_count (big_fn first): got '$FIRST_DATA'"
say "$DB" large-functions | grep -qi 'measure only' || note "large-functions must state in its own output that it is a measure, not a gate"

# ---- A2: god-modules — sum of per-function fan-in, grouped by module, no gate ------------------
OUT="$(say "$DB" god-modules)"
echo "$OUT" | grep -q 'lib/big.ml|2\|lib/big.ml.*2$' || note "god-modules: lib/big.ml must show fan_in=2 (big_fn called by caller_a, caller_b)"
echo "$OUT" | grep -q 'lib/mid.ml|1\|lib/mid.ml.*1$' || note "god-modules: lib/mid.ml must show fan_in=1 (mid_fn called by caller_a)"
echo "$OUT" | grep -q 'lib/small.ml' && note "god-modules must NOT list lib/small.ml (no incoming calls)"
say "$DB" god-modules | grep -qi 'measure only' || note "god-modules must state in its own output that it is a measure, not a gate"

# ---- no gate, anywhere: none of the three measure commands accept a --fail-on-... flag --------
for cmd in large-files large-functions god-modules; do
  "$Q" "$DB" "$cmd" --fail-on-size 100 >/dev/null 2>&1
  # the extra positional arg is simply ignored by limit_of's int_of_string_opt fallback — the
  # point under test is that it is IGNORED, not parsed as a threshold that can fail the build.
  [ $? -eq 0 ] || note "$cmd must not turn a stray flag-looking argument into a build failure"
done
"$Q" 2>&1 | grep -qi 'MEASURE' || note "usage text must document the MEASURE/no-gate contract"

# ---- exit-3 feature-detect on a schema that has none of these columns/tables ------------------
FLAT="$(mktemp --suffix=.db)"; rm -f "$FLAT"
"$LOAD" "$FLAT" <<'NDJSON' 2>/dev/null
{"type":"function","name":"f","file_path":"x","exported":true}
{"type":"function","name":"g","file_path":"x"}
{"type":"call","caller_name":"f","callee_name":"g","call_site":"x:1","kind":"MUST"}
NDJSON
for cmd in missing-docs missing-mli "type-search foo" large-files large-functions god-modules; do
  "$Q" "$FLAT" $cmd >/dev/null 2>&1
  [ $? -eq 3 ] || note "'$cmd' on a flat (arch-load) index must REFUSE with exit 3, not crash or answer emptily"
done

rm -f "$DB" "$FLAT"
if [ "$fails" -eq 0 ]; then echo "selftest-health: PASS"; else echo "selftest-health: $fails FAILURE(S)"; exit 1; fi
