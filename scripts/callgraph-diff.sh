#!/usr/bin/env bash
# callgraph-diff.sh — exhaustive no-drop / kind-monotonicity gate for walker rewrites.
#
# Indexes the same build tree with TWO arch_callgraph_ocaml binaries (a baseline
# ref and the working tree) and compares the full (caller, callee, site) edge
# populations:
#   - DROPPED edges (present in old, absent in new)  → HARD FAIL (false-UNREACHABLE risk)
#   - kind movements per surviving edge              → reported, NOT gated, and
#     not decidable at small counts: a clean self-comparison already reports
#     ±33 phantom movements. See the KNOWN DEFECT note above the movement
#     report for the mechanism. Read the DROPPED gate as the verdict and the
#     movement table as a lead to chase by hand.
#
# Usage: scripts/callgraph-diff.sh [<baseline-git-ref>]   (default: main)
# pipefail is not hygiene here, it is the point of the script. The population
# dumps below (`dump`, `sites`, `lam_edge_sites`, `lam_edge_caller_sites`) all
# end in `| norm | LC_ALL=C sort`, and without pipefail `set -e` sees SORT's
# status — always 0 — so a sqlite3 that FAILED yields an EMPTY population file
# and the run continues. Two empty populations differ nowhere, so the gate
# prints `PASS (zero dropped edges)` and exits 0 having compared nothing.
#
# (An earlier version of this note justified pipefail by a `| tail -2` on the
# two build steps. Those pipes are gone — the builds redirect to log files and
# are status-checked with `if ! (...)` — but the reason survived intact in the
# dump pipelines, which is where it is pointed now.)
#
# Found by review on this PR, in the sibling class to the `--root .` bug this PR
# exists to fix — both are "the command ran, but not over what you think".
set -euo pipefail
HERE="$(cd "$(dirname "$0")/.." && pwd)"
REF="${1:-main}"
eval "$(cd "$HERE" && opam env 2>/dev/null)" || true

LOGDIR="$(mktemp -d)"
# EVERYTHING this script creates lives under $LOGDIR: the two build logs, the
# six population files the gate reads back, the two SQLite databases, and the
# baseline worktree. A fixed name in a world-writable directory is symlink-
# preemptable, and review demonstrated it rather than arguing it: symlinking
# $LOGDIR/old-sites.txt at a victim file and running the gate destroyed the
# victim's contents through the link, exit 0. Two concurrent runs also
# clobbered each other's -old-sites/-new-sites, after which `comm` compared one
# run's baseline against the other's working tree — an arbitrary PASS or FAIL
# from the gate itself.
#
# One directory, one trap, so nothing survives the run. Getting to that took
# three tries and the second made it worse: it moved the population files under
# $LOGDIR but left `OLD_DB`/`NEW_DB` on bare `mktemp` and $WT's parent on a
# second `mktemp -d`, both OUTSIDE the trap, while claiming in its commit
# message that all fourteen references now resolved under $LOGDIR. Review
# counted /tmp/tmp.* across consecutive runs — 89 → 92 → 95, i.e. +3 leaked
# artifacts per run, two of them 1.8 MB each — so the rewrite TRIPLED the
# ~1.1 MB/run leak it claimed to have removed, into a /tmp this project has
# already had fill to 100%. Anything new this script creates goes under
# $LOGDIR; a fresh `mktemp` here is the bug, not the fix.
WT="$LOGDIR/baseline"
trap 'git -C "$HERE" worktree remove --force "$WT" 2>/dev/null || true; rm -rf "$LOGDIR"' EXIT
git -C "$HERE" worktree add --detach "$WT" "$REF" >/dev/null

echo "== building baseline ($REF) =="
# BUILD WHAT YOU INDEX. Both build steps name `lib/arch_index` as well as the
# exe, because BUILD_DIR below indexes the LIBRARY's .cmt files and linking
# bin/arch_callgraph_ocaml needs only .cmx/.cmi — an exe-only build produces
# no .cmt for the library at all. Measured on a clean tree: exe-only leaves 1
# .cmt (arch_index__.cmt, the module-alias file) where
# `dune build --root . lib/arch_index` leaves 24. So an exe-only build left
# the corpus to be whatever some earlier, unrelated build happened to have
# lying around — see the magnitude floor below for what that cost.
#
# The baseline worktree is freshly created, so a failed build leaves no .exe and
# the -x guard catches it. Keep the guard anyway: it is what turns a build
# failure into a clear message instead of a confusing missing-file error.
if ! ( cd "$WT" && eval "$(opam env 2>/dev/null)" && dune build --root . lib/arch_index bin/arch_callgraph_ocaml ) >$LOGDIR/base-build.log 2>&1
then
  echo "callgraph-diff: baseline ($REF) build FAILED — refusing to compare" >&2
  tail -20 $LOGDIR/base-build.log >&2
  exit 2
fi
OLD_BIN="$WT/_build/default/bin/arch_callgraph_ocaml/arch_callgraph_ocaml.exe"
[ -x "$OLD_BIN" ] || { echo "callgraph-diff: baseline produced no binary" >&2; exit 2; }

echo "== building working tree =="
# This is the dangerous one: unlike the baseline, $HERE usually HAS a binary
# from an earlier build, so a swallowed failure produces a wrong answer rather
# than a missing file.
if ! ( cd "$HERE" && dune build --root . lib/arch_index bin/arch_callgraph_ocaml ) >$LOGDIR/new-build.log 2>&1
then
  echo "callgraph-diff: working-tree build FAILED — refusing to compare against a stale binary" >&2
  tail -20 $LOGDIR/new-build.log >&2
  exit 2
fi
NEW_BIN="$HERE/_build/default/bin/arch_callgraph_ocaml/arch_callgraph_ocaml.exe"
[ -x "$NEW_BIN" ] || { echo "callgraph-diff: working tree produced no binary" >&2; exit 2; }

# Index the WORKING TREE's build dir with both binaries (same input universe).
BUILD_DIR="$HERE/_build/default/lib/arch_index"
OLD_DB="$LOGDIR/old.db"; NEW_DB="$LOGDIR/new.db"
"$OLD_BIN" --build-dir="$BUILD_DIR" --db-path="$OLD_DB" --schema-path="$HERE/architecture-schema.sql" >/dev/null 2>&1
"$NEW_BIN" --build-dir="$BUILD_DIR" --db-path="$NEW_DB" --schema-path="$HERE/architecture-schema.sql" >/dev/null 2>&1

# A population gate must not pass with no population — nor, and this is the
# part that actually bit, with a FRACTION of one. The old guard tested
# `sites == 0`, but the hazard is a PARTIAL corpus, which is never zero.
# Review built 3 of the library's 23 modules' .cmt as real dune targets, ran
# the gate, and got
#   == populations: old=1643 new=1643 added=0 ==
#   callgraph-diff: PASS (zero dropped edges)      exit 0
# on 34% of the corpus. The zero case fired at all only by luck: the single
# .cmt an exe-only build leaves is the module-alias file, which declares no
# functions, so the count landed on exactly the one value the guard tested for.
#
# A partial corpus is undetectable by the comparison itself. Every unbuilt
# module's edges are absent from BOTH databases, so a real drop inside them
# cannot show up as a difference — the gate reports agreement about nothing.
# Hence a MAGNITUDE floor, against the reference this repo already commits:
# test/fixtures/self-index-stats.txt, the golden the CI self-index smoke test
# diffs against. `-ge` and not `-eq`, because a branch may legitimately add
# modules before its golden is refreshed; a corpus SMALLER than the golden's is
# missing .cmt files, and that is the state that must refuse.
#
# The floor is a receipt, not the fix: the two `lib/arch_index` build targets
# above are what make the corpus complete by construction. Both sides are
# checked because they index the same BUILD_DIR — if one is short, so is the
# other, and reporting whichever we notice first is enough.
GOLDEN="$HERE/test/fixtures/self-index-stats.txt"
want_modules="$(sed -n 's/^modules: *//p' "$GOLDEN")"
[ -n "$want_modules" ] || { echo "callgraph-diff: no 'modules:' line in $GOLDEN — cannot establish a corpus floor" >&2; exit 2; }
check_corpus() { # $1 = side label, $2 = db
  local got
  got="$(sqlite3 "$2" "SELECT count(*) FROM modules;")"
  # `if`, not `[ ... ] && return 0`: under `set -e` a failing AND-list is not a
  # tested condition, so the short-circuit would abort the script before the
  # diagnostic below ever printed.
  if [ "$got" -ge "$want_modules" ]; then return 0; fi
  echo "callgraph-diff: REFUSING — the $1 index covers $got of the $want_modules modules" >&2
  echo "  recorded by $GOLDEN, so the corpus under" >&2
  echo "    $BUILD_DIR" >&2
  echo "  is PARTIAL. Both sides then agree about the modules that are missing," >&2
  echo "  and a dropped edge inside them cannot appear as a difference — the" >&2
  echo "  comparison would pass while proving nothing. Run" >&2
  echo "    dune build --root . lib/arch_index" >&2
  echo "  and retry. (If modules were deliberately removed, refresh $GOLDEN.)" >&2
  exit 2
}
check_corpus baseline "$OLD_DB"
check_corpus "working tree" "$NEW_DB"

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

dump "$OLD_DB" > $LOGDIR/old.txt
dump "$NEW_DB" > $LOGDIR/new.txt
sites "$OLD_DB" > $LOGDIR/old-sites.txt
sites "$NEW_DB" > $LOGDIR/new-sites.txt
lam_edge_sites "$NEW_DB" > $LOGDIR/new-lamsites.txt
lam_edge_caller_sites "$NEW_DB" > $LOGDIR/new-lamcallersites.txt

raw_dropped=$(LC_ALL=C comm -23 $LOGDIR/old-sites.txt $LOGDIR/new-sites.txt)
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
' $LOGDIR/new-lamcallersites.txt $LOGDIR/new-lamsites.txt -)
added=$(LC_ALL=C comm -13 $LOGDIR/old-sites.txt $LOGDIR/new-sites.txt | wc -l)
replaced=$(( $(echo "$raw_dropped" | grep -c . || true) - $(echo "$dropped" | grep -c . || true) ))
echo "== sanctioned *TOP*→lambda replacements: $replaced =="
echo "== populations: old=$(wc -l < $LOGDIR/old-sites.txt) new=$(wc -l < $LOGDIR/new-sites.txt) added=$added =="
echo "== kind distribution =="
echo "old:"; sqlite3 "$OLD_DB" "SELECT '  '||kind||': '||count(*) FROM calls GROUP BY kind;"
echo "new:"; sqlite3 "$NEW_DB" "SELECT '  '||kind||': '||count(*) FROM calls GROUP BY kind;"
echo "== kind movements (old-kind → new-kind, per shared site) =="
# KNOWN DEFECT (pre-existing, not fixed here). A clean self-comparison — the
# SAME binary run twice into two fresh databases — reports 33 phantom
# MAY_ENUMERATED -> MUST movements AND 33 in the reverse direction, despite the
# two kind histograms being identical, i.e. despite zero real movements.
#
# THE MECHANISM, verified rather than inferred. `(caller_id, callee_name,
# call_site)` is NOT a unique key: `call_site` is file:line with no COLUMN (see
# architecture-schema.sql's note on top_anchor), so several distinct calls to
# the same callee on one source line collapse onto one triple — and a
# short-circuit operator makes some of them conditional and others not:
#
#   claims -> Stdlib.=  @arch_errors_config.ml:553   kinds = MUST, MAY_ENUMERATED, MAY_ENUMERATED
#
# 33 triples carry more than one distinct kind within a SINGLE database. The
# self-join below then cross-matches a caller's own duplicate rows, and 44
# ordered raw pairs collapse to exactly the 33 triples reported.
#
# So this is NOT an indexer defect: those rows are genuinely different calls,
# correctly kinded. The defect is entirely in this report, which joins on a
# key that does not identify a call.
#
# An earlier version of this comment blamed a `functions.name` fan-out and a
# missing norm(). That was wrong and it actively misdirected — a reader who
# checked for name collisions would have found none and concluded the counts
# were sound. Three controls disprove it: of the 66 phantom rows, ZERO have a
# caller name shared by more than one function; re-joining on `fn.id = fo.id`
# (perfect identity, no fan-out possible) still yields 33/33; and excluding
# every collided name still yields 33/33. There ARE 21 names shared by
# multiple `functions` rows on this corpus, but they are a separate latent
# hazard that does not bite here, and none of them contains `<fun:` so norm()
# would change nothing for them.
#
# Real remedy: give the join a key that identifies a call — de-duplicate
# (caller, callee, site) to its DISTINCT kind set per side before joining, or
# add a column to call_site. NOT a norm() over caller identity.
#
# The DROPPED-EDGES gate above is unaffected: it compares norm()'d site
# populations as SETS, so duplicate rows on one line collapse harmlessly.
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
