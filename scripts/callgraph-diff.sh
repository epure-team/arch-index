#!/usr/bin/env bash
# callgraph-diff.sh — exhaustive no-drop / kind-monotonicity gate for walker rewrites.
#
# Indexes the same build tree with TWO arch_callgraph_ocaml binaries (a baseline
# ref and the working tree) and compares the full (caller, callee, site) edge
# populations:
#   - DROPPED edges (present in old, absent in new)  → HARD FAIL (false-UNREACHABLE risk)
#   - kind movements per surviving edge              → reported; MUST→demoted is
#     expected during a dominance tightening, demoted→MUST must be justified.
#
# Usage: scripts/callgraph-diff.sh [<baseline-git-ref>]   (default: main)
set -eu
HERE="$(cd "$(dirname "$0")/.." && pwd)"
REF="${1:-main}"
eval "$(cd "$HERE" && opam env 2>/dev/null)" || true

WT="$(mktemp -d)/baseline"
trap 'git -C "$HERE" worktree remove --force "$WT" 2>/dev/null || true' EXIT
git -C "$HERE" worktree add --detach "$WT" "$REF" >/dev/null

echo "== building baseline ($REF) =="
( cd "$WT" && eval "$(opam env 2>/dev/null)" && dune build bin/arch_callgraph_ocaml 2>&1 | tail -2 ) || true
OLD_BIN="$WT/_build/default/bin/arch_callgraph_ocaml/arch_callgraph_ocaml.exe"
[ -x "$OLD_BIN" ] || { echo "callgraph-diff: baseline build failed" >&2; exit 2; }

echo "== building working tree =="
( cd "$HERE" && dune build bin/arch_callgraph_ocaml 2>&1 | tail -2 )
NEW_BIN="$HERE/_build/default/bin/arch_callgraph_ocaml/arch_callgraph_ocaml.exe"

# Index the WORKING TREE's build dir with both binaries (same input universe).
BUILD_DIR="$HERE/_build/default/lib/arch_index"
OLD_DB="$(mktemp)"; NEW_DB="$(mktemp)"
"$OLD_BIN" --build-dir="$BUILD_DIR" --db-path="$OLD_DB" --schema-path="$HERE/architecture-schema.sql" >/dev/null 2>&1
"$NEW_BIN" --build-dir="$BUILD_DIR" --db-path="$NEW_DB" --schema-path="$HERE/architecture-schema.sql" >/dev/null 2>&1

# R2 normalization: the lambda-node redesign MOVES a lambda body's calls from
# the parent to the synthetic lambda node (parent.<fun:L:C>…) — a sanctioned
# reattribution, not a drop. For population comparison, callers are normalized
# to their chain ROOT (strip every .<fun:…> component). Likewise a literal
# argument's old '*TOP*' escape row is REPLACED by a parent→lambda enumerated
# edge; such a row counts as replaced iff the new DB has a lambda edge at the
# same (root caller, site).
norm() { sed -E 's/\.<fun:[^|>]*>//g'; }
dump() { # (root_caller, callee, site, kind) sorted (LC_ALL=C for comm)
  sqlite3 "$1" "SELECT f.name||'|'||c.callee_name||'|'||c.call_site||'|'||c.kind
                FROM calls c JOIN functions f ON c.caller_id=f.id;" | norm | LC_ALL=C sort
}
sites() { # population without kind, lambda chains rooted
  sqlite3 "$1" "SELECT DISTINCT f.name||'|'||c.callee_name||'|'||c.call_site
                FROM calls c JOIN functions f ON c.caller_id=f.id;" | norm | LC_ALL=C sort -u
}
lam_edge_sites() { # root callers holding at least one lambda edge in $1
  # (root-caller granularity: the replaced *TOP* marker sat at the APPLY's
  # line while the enumerated lambda edge carries the LITERAL's line, so a
  # site-exact match is impossible for multi-line applications)
  sqlite3 "$1" "SELECT DISTINCT f.name
                FROM calls c JOIN functions f ON c.caller_id=f.id
                WHERE c.callee_name LIKE '%<fun:%';" | norm | LC_ALL=C sort -u
}

dump "$OLD_DB" > /tmp/cgdiff-old.txt
dump "$NEW_DB" > /tmp/cgdiff-new.txt
sites "$OLD_DB" > /tmp/cgdiff-old-sites.txt
sites "$NEW_DB" > /tmp/cgdiff-new-sites.txt
lam_edge_sites "$NEW_DB" > /tmp/cgdiff-new-lamsites.txt

raw_dropped=$(LC_ALL=C comm -23 /tmp/cgdiff-old-sites.txt /tmp/cgdiff-new-sites.txt)
# Filter the sanctioned replacement: an old '*TOP*' row whose (caller, site)
# now carries a lambda edge. Everything else is a REAL drop.
dropped=$(echo "$raw_dropped" | awk -F'|' '
  NR==FNR { lam[$0]=1; next }
  $2=="*TOP*" && ($1 in lam) { next }
  NF { print }
' /tmp/cgdiff-new-lamsites.txt -)
added=$(LC_ALL=C comm -13 /tmp/cgdiff-old-sites.txt /tmp/cgdiff-new-sites.txt | wc -l)
replaced=$(( $(echo "$raw_dropped" | grep -c . || true) - $(echo "$dropped" | grep -c . || true) ))
echo "== sanctioned *TOP*→lambda replacements: $replaced =="
echo "== populations: old=$(wc -l < /tmp/cgdiff-old-sites.txt) new=$(wc -l < /tmp/cgdiff-new-sites.txt) added=$added =="
echo "== kind distribution =="
echo "old:"; sqlite3 "$OLD_DB" "SELECT '  '||kind||': '||count(*) FROM calls GROUP BY kind;"
echo "new:"; sqlite3 "$NEW_DB" "SELECT '  '||kind||': '||count(*) FROM calls GROUP BY kind;"
echo "== kind movements (old-kind → new-kind, per shared site) =="
join -t'|' -j1 \
  <(awk -F'|' '{print $1"|"$2"|"$3"\t"$4}' /tmp/cgdiff-old.txt | sort -u | awk -F'\t' '{print $1"|"$2}' OFS='|' | sort -t'|' -u) \
  /dev/null 2>/dev/null || true
# simpler movement report via sqlite
sqlite3 "" <<SQL
ATTACH '$OLD_DB' AS o; ATTACH '$NEW_DB' AS n;
SELECT '  '||ok||' -> '||nk||': '||count(*) FROM (
  SELECT DISTINCT fo.name AS caller, co.callee_name AS callee, co.call_site AS site, co.kind AS ok, cn.kind AS nk
  FROM o.calls co JOIN o.functions fo ON co.caller_id=fo.id
  JOIN n.functions fn ON fn.name=fo.name
  JOIN n.calls cn ON cn.caller_id=fn.id AND cn.callee_name=co.callee_name AND cn.call_site=co.call_site
  WHERE co.kind <> cn.kind
) GROUP BY ok, nk;
SQL

if [ -n "$dropped" ]; then
  echo "== DROPPED EDGES (HARD FAIL) =="
  echo "$dropped" | head -40
  echo "callgraph-diff: FAIL ($(echo "$dropped" | wc -l) dropped edges)"
  exit 1
fi
echo "callgraph-diff: PASS (zero dropped edges)"
