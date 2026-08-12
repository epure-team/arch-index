#!/usr/bin/env bash
# selftest-multilang.sh — one polyglot repository, one index.
#
# selftest-lsp-languages.sh indexes each language in its own project and its own
# database. Real repositories are not shaped like that: a Go service and a
# TypeScript front end sit side by side, and `arch_index --project <repo>` with
# no --language must cover both. That path had never been exercised: the runner
# picked a single language through detect_language, so everything else in the
# repository was silently absent from the index.
#
# What this pins:
#   * auto-detection finds every language in the tree, not the first one;
#   * each language is indexed from the directory holding its project file,
#     since typescript-language-server refuses a root with no tsconfig.json;
#   * rows from all of them land in one database;
#   * file paths and call sites are relative to the REPOSITORY, not to each
#     language's sub-root, or two sub-projects with a main.go each would be
#     indistinguishable;
#   * the language meta key records every contributor.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
fails=0
note() { echo "FAIL: $*" >&2; fails=$((fails+1)); }
command -v sqlite3 >/dev/null 2>&1 || { echo "selftest-multilang: sqlite3 required" >&2; exit 2; }
command -v opam    >/dev/null 2>&1 && eval "$(cd "$HERE" && opam env 2>/dev/null)" || true

# Probe by running the servers, not by finding them: a rustup-style shim on PATH
# with no component behind it passes a `command -v` and then indexes nothing.
# Exit 0 on a missing server -- this test needs two language servers at once, and
# a CI runner that has neither should report "not exercised", not "failed".
gopls version >/dev/null 2>&1 || {
  echo "selftest-multilang: gopls not runnable — not exercised" >&2; exit 0; }
typescript-language-server --version >/dev/null 2>&1 || {
  echo "selftest-multilang: typescript-language-server not runnable — not exercised" >&2; exit 0; }
for tool in go npm node; do
  command -v "$tool" >/dev/null 2>&1 || {
    echo "selftest-multilang: $tool not on PATH — not exercised" >&2
    exit 0
  }
done

CLI_INSTALL="$HERE/_build/install/default/bin/arch_index"
CLI_DEFAULT="$HERE/_build/default/bin/arch_index_cli/arch_index_cli.exe"
if [ -x "$CLI_INSTALL" ]; then
  CLI="$CLI_INSTALL"
elif [ -x "$CLI_DEFAULT" ]; then
  CLI="$CLI_DEFAULT"
else
  echo "selftest-multilang: arch_index_cli not built — run ./build.sh first" >&2
  exit 2
fi

TMPDIR_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMPDIR_ROOT"' EXIT

REPO="$TMPDIR_ROOT/polyrepo"
mkdir -p "$REPO/gosvc" "$REPO/tsapp/src"

cat > "$REPO/gosvc/go.mod" <<'GOMOD'
module polysvc

go 1.21
GOMOD
cat > "$REPO/gosvc/main.go" <<'GOSRC'
package main

func goHelper(x int) int { return x + 1 }

func GoEntry(x int) int { return goHelper(x) }

func main() { _ = GoEntry(1) }
GOSRC

cat > "$REPO/tsapp/tsconfig.json" <<'TSCONFIG'
{"compilerOptions":{"target":"ES2020","module":"commonjs","strict":true},"include":["src"]}
TSCONFIG
cat > "$REPO/tsapp/src/index.ts" <<'TSSRC'
export function tsHelper(x: number): number { return x + 1; }
export function tsEntry(x: number): number { return tsHelper(x); }
function tsIsland(): number { return 9; }
TSSRC

( cd "$REPO/tsapp" && npm i --silent --no-audit --no-fund typescript@5 ts-morph >/dev/null 2>&1 ) \
  || { echo "selftest-multilang: npm install failed — skipping" >&2; exit 2; }

DB="$TMPDIR_ROOT/poly.db"
# No --language: the point is that auto-detection covers the whole repository.
"$CLI" --project "$REPO" --output "$DB" >/dev/null 2>&1
[ -f "$DB" ] || { note "no database produced"; echo "selftest-multilang: FAIL ($fails)"; exit 1; }

q() { sqlite3 "$DB" "$1"; }

# ---------- both languages contributed ----------
langs=$(q "SELECT value FROM comment_db_meta WHERE key = 'language';")
case "$langs" in
  *go*) ;;
  *) note "the language meta key ('${langs:-unset}') does not mention go" ;;
esac
case "$langs" in
  *typescript*) ;;
  *) note "the language meta key ('${langs:-unset}') does not mention typescript" ;;
esac

# ---------- rows from both, in one database ----------
for fn in 'GoEntry' 'goHelper' 'tsEntry' 'tsHelper' 'tsIsland'; do
  n=$(q "SELECT count(*) FROM functions WHERE name = '$fn';")
  [ "${n:-0}" -ge 1 ] || note "'$fn' missing from the combined index"
done

# ---------- paths are relative to the repository, not to each sub-root ----------
gp=$(q "SELECT file_path FROM functions WHERE name = 'GoEntry' LIMIT 1;")
[ "$gp" = "gosvc/main.go" ] \
  || note "Go rows should be rooted at the repository: expected gosvc/main.go, got '${gp:-none}'"
tp=$(q "SELECT file_path FROM functions WHERE name = 'tsEntry' LIMIT 1;")
[ "$tp" = "tsapp/src/index.ts" ] \
  || note "TypeScript rows should be rooted at the repository: expected tsapp/src/index.ts, got '${tp:-none}'"

# ---------- call sites carry the same rooting ----------
site=$(q "SELECT call_site FROM calls WHERE caller_name = 'GoEntry' LIMIT 1;")
case "${site:-}" in
  gosvc/main.go:*) ;;
  *) note "call sites should be repository-rooted, got '${site:-none}'" ;;
esac

# ---------- edges from both languages ----------
for edge in 'GoEntry goHelper' 'tsEntry tsHelper'; do
  set -- $edge
  n=$(q "SELECT count(*) FROM calls WHERE caller_name = '$1' AND callee_name = '$2';")
  [ "${n:-0}" -ge 1 ] || note "missing call edge '$1 -> $2'"
done

# ---------- each language's own visibility rule survives the merge ----------
for pair in 'GoEntry 1' 'goHelper 0' 'tsEntry 1' 'tsIsland 0'; do
  set -- $pair
  got=$(q "SELECT COALESCE(exported, -1) FROM functions WHERE name = '$1';")
  [ "${got:--1}" = "$2" ] || note "'$1' should have exported = $2 in the merged index, got '${got:-missing}'"
done

if [ "$fails" -eq 0 ]; then
  echo "selftest-multilang: PASS"
  exit 0
else
  echo "selftest-multilang: FAIL ($fails)"
  exit 1
fi
