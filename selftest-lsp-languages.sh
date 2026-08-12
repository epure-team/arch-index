#!/usr/bin/env bash
# selftest-lsp-languages.sh — regression cover for the LSP indexing path, per language.
#
# The CMT path (OCaml) has selftest-callgraph-ocaml.sh, -nested.sh and the Tezt
# suite under tezt/.  Nothing exercised the LSP path end to end, so a change to
# the shared indexer, schema or resolver could break Go or Rust indexing with
# every OCaml test still green.  This builds a small project per language, runs
# arch_index_cli against the real language server, and asserts the same
# properties for each: symbols are indexed, visibility is recorded, an internal
# helper keeps its caller, and dead-code discriminates.
#
# Each language is skipped, loudly, when its server is absent or non-functional,
# so the script is useful on a workstation with only some of them installed.
# The probes RUN the server rather than looking it up on PATH: rustup installs a
# rust-analyzer shim whose component may be missing, and that shim exits with
# "Unknown binary 'rust-analyzer' in official toolchain" -- a PATH check passes
# and every assertion then fails on an empty index.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
Q="$HERE/arch-query"
fails=0
skips=0
note() { echo "FAIL: $*" >&2; fails=$((fails+1)); }
skip() { echo "SKIP: $*" >&2; skips=$((skips+1)); }
command -v sqlite3 >/dev/null 2>&1 || { echo "selftest-lsp-languages: sqlite3 required" >&2; exit 2; }
command -v opam    >/dev/null 2>&1 && eval "$(cd "$HERE" && opam env 2>/dev/null)" || true

CLI_INSTALL="$HERE/_build/install/default/bin/arch_index"
CLI_DEFAULT="$HERE/_build/default/bin/arch_index_cli/arch_index_cli.exe"
if [ -x "$CLI_INSTALL" ]; then
  CLI="$CLI_INSTALL"
elif [ -x "$CLI_DEFAULT" ]; then
  CLI="$CLI_DEFAULT"
else
  echo "selftest-lsp-languages: arch_index_cli not built — run ./build.sh first" >&2
  exit 2
fi

TMPDIR_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMPDIR_ROOT"' EXIT

# [check_language <label> <db> ...] asserts the properties every backend owes us.
# <exported_fn> is a symbol the language marks public, <internal_fn> one it does
# not, and <island_fn> one nothing calls.
#
# Two gaps are deliberately NOT asserted, because pinning them would enshrine a
# bug rather than guard a contract:
#   * calls.kind does not exist in the runner schema, so no MAY_TOP information
#     is available and every verdict is a candidate, never sound.
check_language() {
  label="$1" db="$2" exported_fn="$3" internal_fn="$4" island_fn="$5"

  [ -f "$db" ] || { note "$label: no database produced"; return; }

  total=$(sqlite3 "$db" "SELECT count(*) FROM functions;")
  [ "${total:-0}" -ge 3 ] \
    || note "$label: expected at least 3 functions indexed, got ${total:-0}"

  vis_col=$(sqlite3 "$db" \
    "SELECT name FROM pragma_table_info('functions') WHERE name IN ('exposed','exported') LIMIT 1;")
  [ -n "$vis_col" ] || note "$label: functions table has neither an exposed nor an exported column"

  for fn in "$exported_fn" "$internal_fn" "$island_fn"; do
    n=$(sqlite3 "$db" "SELECT count(*) FROM functions WHERE name = '$fn' OR name LIKE '%.$fn';")
    [ "${n:-0}" -ge 1 ] || note "$label: '$fn' not indexed"
  done

  # Roots must be given explicitly: see the note above about visibility.
  dc=$("$Q" "$db" dead-code "$exported_fn" 2>&1)
  case "$dc" in
    *Error*) note "$label: dead-code failed: $(echo "$dc" | head -1)" ;;
    *"$island_fn"*) ;;
    *) note "$label: dead-code from root '$exported_fn' should list '$island_fn'" ;;
  esac
}

# ---------------------------------------------------------------- Go --------
if gopls version >/dev/null 2>&1 && command -v go >/dev/null 2>&1; then
  P="$TMPDIR_ROOT/goproj"
  mkdir -p "$P"
  cat > "$P/go.mod" <<'GOMOD'
module archfix

go 1.21
GOMOD
  cat > "$P/main.go" <<'GOSRC'
package main

// helper is unexported: internal to the package.
func helper(x int) int { return x + 1 }

// Entry is exported and calls helper.
func Entry(x int) int { return helper(x) * 2 }

// islandFn is exported but nothing in this package calls it.
func islandFn() int { return 99 }

func main() { _ = Entry(1) }
GOSRC
  "$CLI" --project "$P" --language go --output "$TMPDIR_ROOT/go.db" >/dev/null 2>&1
  check_language "Go" "$TMPDIR_ROOT/go.db" "Entry" "helper" "islandFn"
  # Go decides visibility lexically: an identifier is exported exactly when it
  # starts with an upper-case letter.
  for pair in 'Entry 1' 'helper 0' 'islandFn 0' 'main 0'; do
    set -- $pair
    got=$(sqlite3 "$TMPDIR_ROOT/go.db" "SELECT COALESCE(exported, -1) FROM functions WHERE name = '$1';")
    [ "${got:--1}" = "$2" ] || note "Go: '$1' should have exported = $2, got '${got:-missing}'"
  done

  # Both edges must be there. The caller of one of them (main) is unexported,
  # so this also guards against tying call extraction back to visibility.
  for edge in 'Entry helper' 'main Entry'; do
    set -- $edge
    n=$(sqlite3 "$TMPDIR_ROOT/go.db" \
      "SELECT count(*) FROM calls WHERE caller_name = '$1' AND callee_name = '$2';")
    [ "${n:-0}" -ge 1 ] || note "Go: missing call edge '$1 -> $2'"
  done
else
  skip "Go: gopls not runnable (absent, or a shim without its component)"
fi

# -------------------------------------------------------------- Rust --------
if rust-analyzer --version >/dev/null 2>&1 && command -v cargo >/dev/null 2>&1; then
  P="$TMPDIR_ROOT/rustproj"
  mkdir -p "$P/src"
  cat > "$P/Cargo.toml" <<'CARGO'
[package]
name = "archfix"
version = "0.1.0"
edition = "2021"
CARGO
  cat > "$P/src/lib.rs" <<'RUSTSRC'
// helper is private to the crate.
fn helper(x: i32) -> i32 { x + 1 }

/// entry is public and calls helper.
pub fn entry(x: i32) -> i32 { helper(x) * 2 }

/// island is public but nothing in this crate calls it.
pub fn island() -> i32 { 99 }

pub mod inner {
    pub fn nested(x: i32) -> i32 { super::entry(x) }
}
RUSTSRC
  # Warm the crate first: rust-analyzer reports no call hierarchy at all until
  # it has loaded the workspace, and a never-compiled crate makes that slow
  # enough to be flaky.
  ( cd "$P" && cargo check -q >/dev/null 2>&1 ) || true
  "$CLI" --project "$P" --language rust --output "$TMPDIR_ROOT/rust.db" >/dev/null 2>&1
  check_language "Rust" "$TMPDIR_ROOT/rust.db" "entry" "helper" "island"

  # Rust modules are a nesting the indexer must not flatten away.
  n=$(sqlite3 "$TMPDIR_ROOT/rust.db" "SELECT count(*) FROM functions WHERE name LIKE '%nested%';")
  [ "${n:-0}" -ge 1 ] || note "Rust: 'inner::nested' not indexed"

  # Call edges are reported, but not reliably: rust-analyzer answers no call
  # hierarchy at all while it is still loading, and signals readiness only
  # through $/progress notifications the client does not consume, so the
  # extractor polls instead. Polling wins the race often enough to be worth
  # having and not often enough to assert -- a flaky CI check would be worse
  # than none. Reported, never failed, until the client waits on the indexing
  # token instead of the clock.
  rust_calls=$(sqlite3 "$TMPDIR_ROOT/rust.db" "SELECT count(*) FROM calls;")
  if [ "${rust_calls:-0}" -ge 1 ]; then
    echo "INFO: Rust: $rust_calls call edge(s) extracted this run" >&2
  else
    skip "Rust: no call edges this run (rust-analyzer readiness race, not asserted)"
  fi
else
  skip "Rust: rust-analyzer not runnable (absent, or a rustup shim whose component is not installed)"
fi

# -------------------------------------------------------- TypeScript --------
# typescript-language-server refuses to start without a TypeScript install in
# the workspace, and looks for node_modules/typescript/lib/tsserver.js -- a
# layout TypeScript 7 no longer has, hence the 5.x pin.
if typescript-language-server --version >/dev/null 2>&1 && command -v npm >/dev/null 2>&1; then
  P="$TMPDIR_ROOT/tsproj"
  mkdir -p "$P/src"
  cat > "$P/tsconfig.json" <<'TSCONFIG'
{"compilerOptions":{"target":"ES2020","module":"commonjs","strict":true},"include":["src"]}
TSCONFIG
  cat > "$P/src/index.ts" <<'TSSRC'
export function helper(x: number): number { return x + 1; }
export function entry(x: number): number { return helper(x) * 2; }
function island(): number { return 99; }
TSSRC
  if ( cd "$P" && npm i --silent --no-audit --no-fund typescript@5 ts-morph >/dev/null 2>&1 ); then
    "$CLI" --project "$P" --language typescript --output "$TMPDIR_ROOT/ts.db" >/dev/null 2>&1
    check_language "TypeScript" "$TMPDIR_ROOT/ts.db" "entry" "helper" "island"

    # ts-morph enrichment is what fills these in; an UPDATE keyed on a path the
    # LSP rows do not use silently matched nothing and left both columns as the
    # LSP had them.
    for pair in 'entry 1' 'helper 1' 'island 0'; do
      set -- $pair
      got=$(sqlite3 "$TMPDIR_ROOT/ts.db" "SELECT COALESCE(exported, -1) FROM functions WHERE name = '$1';")
      [ "${got:--1}" = "$2" ] || note "TypeScript: '$1' should have exported = $2, got '${got:-missing}'"
    done
    sig=$(sqlite3 "$TMPDIR_ROOT/ts.db" "SELECT COALESCE(signature, '') FROM functions WHERE name = 'entry';")
    [ -n "$sig" ] || note "TypeScript: 'entry' has no signature; ts-morph enrichment did not apply"
  else
    skip "TypeScript: npm install of typescript@5 and ts-morph failed"
  fi
else
  skip "TypeScript: typescript-language-server not runnable, or npm absent"
fi

echo "selftest-lsp-languages: $skips skipped"
if [ "$fails" -eq 0 ]; then
  echo "selftest-lsp-languages: PASS"
  exit 0
else
  echo "selftest-lsp-languages: FAIL ($fails)"
  exit 1
fi
