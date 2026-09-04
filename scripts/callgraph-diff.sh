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
# pipefail is not hygiene here, it is the point of the script. Both build steps
# below end in `| tail -2`, and without it `set -e` sees TAIL's status — always
# 0 — so a build that FAILED continues silently. The working tree normally holds
# an .exe from a previous build, so the run then proceeds with BOTH binaries
# present, both databases populated, and a diff that is non-empty, plausible and
# describing the wrong binary. Nothing downstream can catch that: this script's
# whole job is to compare two binaries, and it would be comparing one of them
# with itself-from-earlier.
#
# Found by review on this PR, in the sibling class to the `--root .` bug this PR
# exists to fix — both are "the command ran, but not over what you think".
set -euo pipefail
HERE="$(cd "$(dirname "$0")/.." && pwd)"
REF="${1:-main}"
eval "$(cd "$HERE" && opam env 2>/dev/null)" || true

WT="$(mktemp -d)/baseline"
trap 'git -C "$HERE" worktree remove --force "$WT" 2>/dev/null || true' EXIT
git -C "$HERE" worktree add --detach "$WT" "$REF" >/dev/null

echo "== building baseline ($REF) =="
# The baseline worktree is freshly created, so a failed build leaves no .exe and
# the -x guard catches it. Keep the guard anyway: it is what turns a build
# failure into a clear message instead of a confusing missing-file error.
if ! ( cd "$WT" && eval "$(opam env 2>/dev/null)" && dune build --root . bin/arch_callgraph_ocaml ) >/tmp/cgdiff-base-build.log 2>&1
then
  echo "callgraph-diff: baseline ($REF) build FAILED — refusing to compare" >&2
  tail -20 /tmp/cgdiff-base-build.log >&2
  exit 2
fi
OLD_BIN="$WT/_build/default/bin/arch_callgraph_ocaml/arch_callgraph_ocaml.exe"
[ -x "$OLD_BIN" ] || { echo "callgraph-diff: baseline produced no binary" >&2; exit 2; }

echo "== building working tree =="
# This is the dangerous one: unlike the baseline, $HERE usually HAS a binary
# from an earlier build, so a swallowed failure produces a wrong answer rather
# than a missing file.
if ! ( cd "$HERE" && dune build --root . bin/arch_callgraph_ocaml ) >/tmp/cgdiff-new-build.log 2>&1
then
  echo "callgraph-diff: working-tree build FAILED — refusing to compare against a stale binary" >&2
  tail -20 /tmp/cgdiff-new-build.log >&2
  exit 2
fi
NEW_BIN="$HERE/_build/default/bin/arch_callgraph_ocaml/arch_callgraph_ocaml.exe"
[ -x "$NEW_BIN" ] || { echo "callgraph-diff: working tree produced no binary" >&2; exit 2; }

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
lam_edge_caller_sites() { # (root_caller, site) pairs with a lambda-node CALLEE
  # (R2b: a local-lambda invocation's callee is renamed from the bare local
  # name to the node name at the SAME site — sanctioned rename, not a drop)
  sqlite3 "$1" "SELECT DISTINCT f.name||'\`'||c.call_site
                FROM calls c JOIN functions f ON c.caller_id=f.id
                WHERE c.callee_name LIKE '%<fun:%';" | norm | LC_ALL=C sort -u
}

dump "$OLD_DB" > /tmp/cgdiff-old.txt
dump "$NEW_DB" > /tmp/cgdiff-new.txt
sites "$OLD_DB" > /tmp/cgdiff-old-sites.txt
sites "$NEW_DB" > /tmp/cgdiff-new-sites.txt
lam_edge_sites "$NEW_DB" > /tmp/cgdiff-new-lamsites.txt
lam_edge_caller_sites "$NEW_DB" > /tmp/cgdiff-new-lamcallersites.txt

raw_dropped=$(LC_ALL=C comm -23 /tmp/cgdiff-old-sites.txt /tmp/cgdiff-new-sites.txt)
# Filter the sanctioned replacements:
#   (a) an old '*TOP*' row whose root caller now carries a lambda edge
#       (literal argument's escape marker replaced by the enumerated edge);
#   (b) an old bare-local-name row whose exact (caller, site) now carries a
#       lambda-node callee (local-lambda invocation renamed to the node).
# Everything else is a REAL drop.
dropped=$(echo "$raw_dropped" | awk -F'|' '
  FILENAME ~ /lamcallersites/ { lamsite[$0]=1; next }
  FILENAME ~ /lamsites/    { lam[$0]=1; next }
  $2=="*TOP*" && ($1 in lam) { next }
  # rule (b) is deliberately narrow: only an old BARE-LOCAL-NAME callee (no
  # module qualifier, not *TOP*) may be a renamed local-lambda invocation —
  # a qualified or *TOP* callee dropped at a lambda-edge site is a REAL drop.
  $2 != "*TOP*" && index($2, ".") == 0 && (($1"`"$3) in lamsite) { next }
  NF { print }
' /tmp/cgdiff-new-lamcallersites.txt /tmp/cgdiff-new-lamsites.txt -)
added=$(LC_ALL=C comm -13 /tmp/cgdiff-old-sites.txt /tmp/cgdiff-new-sites.txt | wc -l)
replaced=$(( $(echo "$raw_dropped" | grep -c . || true) - $(echo "$dropped" | grep -c . || true) ))
echo "== sanctioned *TOP*→lambda replacements: $replaced =="
echo "== populations: old=$(wc -l < /tmp/cgdiff-old-sites.txt) new=$(wc -l < /tmp/cgdiff-new-sites.txt) added=$added =="
echo "== kind distribution =="
echo "old:"; sqlite3 "$OLD_DB" "SELECT '  '||kind||': '||count(*) FROM calls GROUP BY kind;"
echo "new:"; sqlite3 "$NEW_DB" "SELECT '  '||kind||': '||count(*) FROM calls GROUP BY kind;"
echo "== kind movements (old-kind → new-kind, per shared site) =="
# KNOWN DEFECT (pre-existing, not fixed here): this join is on `functions.name`
# alone, not on the normalized/rooted caller identity used everywhere else in
# this script (see norm()/sites() above). Any function name shared by more
# than one distinct function (21 such names were observed on a clean
# self-comparison, i.e. comparing a tree against itself) fans this join out
# across all of them, reporting kind "movements" that never happened. Measured
# symptom: a clean self-comparison (old == new binary) reported 33 phantom
# MAY_ENUMERATED -> MUST movements below, despite zero actual kind changes.
# Do not trust this section's counts without independently checking for
# name-collision fan-out; the DROPPED-EDGES gate above is unaffected (it joins
# through norm()'d site identity, not bare function name).
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
  head -40 <<<"$dropped"
  echo "callgraph-diff: FAIL ($(echo "$dropped" | wc -l) dropped edges)"
  exit 1
fi
echo "callgraph-diff: PASS (zero dropped edges)"
