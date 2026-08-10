#!/usr/bin/env bash
# selftest-duplicates.sh — A3: arch-body-compare, the CLI surface for
# Arch_index_compare.compare_bodies (body-hash duplicate proof).
#
# Under test: single-name compare (NOT FOUND / SINGLE / DUPLICATE / DIFFERS), the full-index
# `duplicates` sweep, the empty-body disambiguation (two unreadable bodies must NOT be reported as
# a proven duplicate), and exit-3 refusal on a flat (arch-load) index that has no source mapping.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
LOAD="$HERE/arch-load"; BC="$HERE/arch-body-compare"
fails=0; note() { echo "FAIL: $*" >&2; fails=$((fails+1)); }
command -v sqlite3 >/dev/null 2>&1 || { echo "selftest-duplicates: sqlite3 required" >&2; exit 2; }

REPO="$(mktemp -d)"
mkdir -p "$REPO/lib/a" "$REPO/lib/b" "$REPO/lib/c"
# same_a and same_b: byte-identical canonical body under different names AND as two
# occurrences of the SAME name `dup` — arch-body-compare works name-by-name, so the fixture below
# puts the duplicate under one shared name `dup` in two modules.
cat > "$REPO/lib/a/dup.ml" <<'EOF'
  let run () =
      1 + 1
EOF
cat > "$REPO/lib/b/dup.ml" <<'EOF'
  let run () =
      1 + 1
EOF
cat > "$REPO/lib/c/dup.ml" <<'EOF'
let run () =
2 + 2
EOF
cat > "$REPO/lib/a/solo.ml" <<'EOF'
let solo () = 42
EOF

DB="$(mktemp --suffix=.db)"; rm -f "$DB"
sqlite3 "$DB" < "$HERE/architecture-schema.sql"
sqlite3 "$DB" <<SQL
INSERT INTO modules(path, lines) VALUES ('lib/a/dup.ml', 2), ('lib/b/dup.ml', 2), ('lib/a/solo.ml', 1);
INSERT INTO functions(module_id, name, line_start, line_end) VALUES
  ((SELECT id FROM modules WHERE path='lib/a/dup.ml'), 'dup', 1, 2),
  ((SELECT id FROM modules WHERE path='lib/b/dup.ml'), 'dup', 1, 2),
  ((SELECT id FROM modules WHERE path='lib/a/solo.ml'), 'solo', 1, 1);
SQL

# ---- single-name mode -------------------------------------------------------------------------
"$BC" "$DB" nope --repo "$REPO" | grep -q 'NOT FOUND' || note "an unknown name must report NOT FOUND"
"$BC" "$DB" solo --repo "$REPO" | grep -q 'SINGLE'    || note "a name defined once must report SINGLE, not a duplicate"
"$BC" "$DB" dup  --repo "$REPO" | grep -q 'DUPLICATE: 2 occurrence' \
  || note "two byte-identical occurrences of dup must be reported as a proven DUPLICATE"

# Language-independent whitespace folding is unsafe inside literals/comments.  Even an
# indentation-only difference is conservatively DIFFERS until a language-aware canonicaliser can
# prove it lexical, rather than source content.
sed 's/^  //' "$REPO/lib/b/dup.ml" > "$REPO/lib/b/dup.ml.tmp"
mv "$REPO/lib/b/dup.ml.tmp" "$REPO/lib/b/dup.ml"
"$BC" "$DB" dup --repo "$REPO" | grep -q 'DIFFERS: 2 occurrence' \
  || note "whitespace differences must conservatively report DIFFERS"
cp "$REPO/lib/a/dup.ml" "$REPO/lib/b/dup.ml"

# a genuinely different third occurrence flips the verdict to DIFFERS
sqlite3 "$DB" "INSERT INTO modules(path, lines) VALUES ('lib/c/dup.ml', 2);
  INSERT INTO functions(module_id, name, line_start, line_end)
  VALUES ((SELECT id FROM modules WHERE path='lib/c/dup.ml'), 'dup', 1, 2);"
"$BC" "$DB" dup --repo "$REPO" | grep -q 'DIFFERS: 3 occurrence' \
  || note "adding a genuinely different body must flip dup's verdict to DIFFERS across 3 occurrences"
# remove it again so the rest of this script sees the 2-occurrence duplicate
sqlite3 "$DB" "DELETE FROM functions WHERE name='dup' AND module_id=(SELECT id FROM modules WHERE path='lib/c/dup.ml');
  DELETE FROM modules WHERE path='lib/c/dup.ml';"

# ---- duplicates sweep --------------------------------------------------------------------------
OUT="$("$BC" "$DB" duplicates --repo "$REPO")"
echo "$OUT" | grep -q '1 proven duplicate' || note "duplicates sweep must report exactly 1 proven duplicate: $OUT"
echo "$OUT" | grep -q 'DUPLICATE dup' || note "duplicates sweep must list 'dup' as the proven duplicate"
echo "$OUT" | grep -q 'solo' && note "duplicates sweep must NOT mention solo (defined once, not a candidate)"

OUT_JSON="$(ARCH_QUERY_FORMAT=json "$BC" "$DB" duplicates --repo "$REPO" --format json)"
# Guarded by `if`, not `command -v python3 && ... || note`: that pattern's `&&`/`||` short-circuit
# the SAME way whether python3 is absent or the python3 call itself fails, so an absent python3
# would trip `note` as a false FAILURE instead of just skipping this JSON-shape check.
if command -v python3 >/dev/null 2>&1; then
  printf '%s' "$OUT_JSON" | python3 -c '
import json,sys
d=json.load(sys.stdin)
assert d["candidates_with_multiple_definitions"] == 1, d
names=[x["name"] for x in d["proven_duplicates"]]
assert names == ["dup"], names
assert d["unverifiable_empty_body"] == [], d
' 2>/dev/null || note "duplicates --format json must report exactly one proven duplicate named dup"
fi

# ---- empty-body disambiguation: two unreadable occurrences must NOT be a proven duplicate ------
GHOST_DB="$(mktemp --suffix=.db)"; rm -f "$GHOST_DB"
sqlite3 "$GHOST_DB" < "$HERE/architecture-schema.sql"
sqlite3 "$GHOST_DB" <<'SQL'
INSERT INTO modules(path, lines) VALUES ('lib/gone/x.ml', 5), ('lib/gone/y.ml', 5);
INSERT INTO functions(module_id, name, line_start, line_end) VALUES
  ((SELECT id FROM modules WHERE path='lib/gone/x.ml'), 'ghost', 1, 5),
  ((SELECT id FROM modules WHERE path='lib/gone/y.ml'), 'ghost', 1, 5);
SQL
"$BC" "$GHOST_DB" ghost --repo "$REPO" | grep -q 'UNVERIFIABLE' \
  || note "two occurrences whose source files do not exist must report UNVERIFIABLE, not DUPLICATE"
"$BC" "$GHOST_DB" ghost --repo "$REPO" | grep -q '^DUPLICATE' \
  && note "an unreadable-body match must NEVER be reported as a proven DUPLICATE"
"$BC" "$GHOST_DB" duplicates --repo "$REPO" | grep -q '0 proven duplicate' \
  || note "the duplicates sweep must exclude an unverifiable (empty-body) match from its proven-duplicate count"
"$BC" "$GHOST_DB" duplicates --repo "$REPO" | grep -q 'ghost' \
  || note "the duplicates sweep must still surface ghost, under UNVERIFIABLE"
rm -f "$GHOST_DB"

# ---- exit-3 refusal on a flat (arch-load) index -------------------------------------------------
FLAT="$(mktemp --suffix=.db)"; rm -f "$FLAT"
"$LOAD" "$FLAT" <<'NDJSON' 2>/dev/null
{"type":"function","name":"f","file_path":"x","exported":true}
{"type":"function","name":"g","file_path":"x"}
{"type":"call","caller_name":"f","callee_name":"g","call_site":"x:1","kind":"MUST"}
NDJSON
"$BC" "$FLAT" f >/dev/null 2>&1
[ $? -eq 3 ] || note "arch-body-compare on a flat (arch-load) index must REFUSE with exit 3 (no modules table)"
"$BC" "$FLAT" duplicates >/dev/null 2>&1
[ $? -eq 3 ] || note "arch-body-compare duplicates on a flat index must REFUSE with exit 3"

# ---- not an arch-index DB at all: exit 2, not 3 (a soundness verdict vs a broken input) ---------
NOTADB="$(mktemp --suffix=.db)"; rm -f "$NOTADB"
sqlite3 "$NOTADB" "CREATE TABLE unrelated(x INTEGER);"
"$BC" "$NOTADB" anything >/dev/null 2>&1
[ $? -eq 2 ] || note "arch-body-compare on a DB with no functions table must exit 2 (broken input), not 3"

rm -rf "$REPO"; rm -f "$DB" "$FLAT" "$NOTADB"
if [ "$fails" -eq 0 ]; then echo "selftest-duplicates: PASS"; else echo "selftest-duplicates: $fails FAILURE(S)"; exit 1; fi
