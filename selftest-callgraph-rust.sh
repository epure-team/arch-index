#!/usr/bin/env bash
# selftest-callgraph-rust.sh — the Rust MIR call-graph producer + the
# whole-program dyn-dispatch merge pass, driven end-to-end over hand-built
# multi-crate cargo workspaces.
#
# The property this exists to protect is NOT "the driver compiles" — it is
# the soundness invariant the whole task exists to deliver (FR-002: never
# drop a Call terminator) PLUS the three whole-program safety gates from
# specs/rust-soundcg-whole-program.md:
#   1. a dyn-dispatch site with exactly one non-blanket impl anywhere in a
#      publish=false-defining-crate trait narrows to MAY_ENUMERATED
#   2. a blanket impl for the trait forces MAY_TOP even when concrete impls
#      also exist
#   3. a workspace member absent from the batch forces MAY_TOP for every
#      dyn site (the missing-facts fallback), not just the affected trait
#
# Self-contained: builds its own scratch fixtures under mktemp -d, not
# ~/dev-tree scratch directories. Requires the driver already built (same
# convention as arch-callgraph-rust itself) and the merge pass built via
# `dune build bin/arch_callgraph_rust_merge`.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
DRIVER_HARNESS="$HERE/arch-callgraph-rust"
MERGE="$HERE/../_build/default/bin/arch_callgraph_rust_merge/arch_callgraph_rust_merge.exe"
[ -x "$MERGE" ] || MERGE="$(cd "$HERE" && dune build bin/arch_callgraph_rust_merge 2>/dev/null; echo "$HERE/_build/default/bin/arch_callgraph_rust_merge/arch_callgraph_rust_merge.exe")"

fails=0
note() { echo "FAIL: $*" >&2; fails=$((fails + 1)); }

if [ ! -x "$HERE/callgraph-rust/target/release/arch-callgraph-rust" ] \
  && [ ! -x "$HERE/callgraph-rust/target/debug/arch-callgraph-rust" ]; then
  echo "selftest-callgraph-rust: SKIP — driver not built (cd callgraph-rust && RUSTC_BOOTSTRAP=1 cargo build --release)"
  exit 0
fi
if [ ! -x "$MERGE" ]; then
  echo "selftest-callgraph-rust: SKIP — merge pass not built (dune build bin/arch_callgraph_rust_merge)"
  exit 0
fi

WS="$(mktemp -d)"
trap 'rm -rf "$WS"' EXIT

make_workspace() {  # $1 = scenario dir name, $2 = crate_a/src/lib.rs body
  mkdir -p "$WS/$1/crate_a/src" "$WS/$1/crate_b/src"
  cat >"$WS/$1/Cargo.toml" <<'EOF'
[workspace]
members = ["crate_a", "crate_b"]
resolver = "2"
EOF
  cat >"$WS/$1/crate_a/Cargo.toml" <<'EOF'
[package]
name = "crate_a"
version = "0.1.0"
edition = "2021"
publish = false
EOF
  printf '%s' "$2" >"$WS/$1/crate_a/src/lib.rs"
  cat >"$WS/$1/crate_b/Cargo.toml" <<'EOF'
[package]
name = "crate_b"
version = "0.1.0"
edition = "2021"
publish = false

[dependencies]
crate_a = { path = "../crate_a" }
EOF
  cat >"$WS/$1/crate_b/src/lib.rs" <<'EOF'
pub fn entry(x: &i32) {
    crate_a::use_dyn(x);
}
EOF
}

# ── Scenario 1: sibling non-blanket impls → narrows to 2 MAY_ENUMERATED ──
make_workspace sibling 'pub trait Doer { fn do_it(&self); }
impl Doer for i32 { fn do_it(&self) {} }
pub fn use_dyn(d: &dyn Doer) { d.do_it(); }
'
cat >>"$WS/sibling/crate_b/src/lib.rs" <<'EOF'
pub struct B;
impl crate_a::Doer for B { fn do_it(&self) {} }
EOF
raw="$("$DRIVER_HARNESS" "$WS/sibling" 2>/tmp/selftest-cg-rust-sibling.stderr)"
if [ -z "$raw" ]; then
  note "sibling: producer emitted nothing (see /tmp/selftest-cg-rust-sibling.stderr)"
else
  merged="$(printf '%s\n' "$raw" | "$MERGE" --expected-crates crate_a,crate_b 2>/dev/null)"
  n_enum=$(printf '%s\n' "$merged" | grep -c '"kind":"MAY_ENUMERATED"')
  n_top_dyn=$(printf '%s\n' "$merged" | grep -c '"x_dyn_trait"')
  [ "$n_enum" -ge 1 ] || note "sibling: expected >=1 MAY_ENUMERATED edge, got $n_enum"
  [ "$n_top_dyn" -eq 0 ] || note "sibling: x_dyn_trait/x_dyn_method leaked into merged output (arch-load would reject as unknown fields)"
  printf '%s\n' "$merged" | grep -q '"type":"trait_impl_fact"' && note "sibling: trait_impl_fact record leaked into merged output"
fi

# ── Scenario 2: blanket impl → stays MAY_TOP despite a fact existing ──
make_workspace blanket 'pub trait Doer { fn do_it(&self); }
impl<T: std::fmt::Debug> Doer for T { fn do_it(&self) {} }
pub fn use_dyn(d: &dyn Doer) { d.do_it(); }
'
raw="$("$DRIVER_HARNESS" "$WS/blanket" 2>/tmp/selftest-cg-rust-blanket.stderr)"
if [ -z "$raw" ]; then
  note "blanket: producer emitted nothing (see /tmp/selftest-cg-rust-blanket.stderr)"
else
  merged="$(printf '%s\n' "$raw" | "$MERGE" --expected-crates crate_a,crate_b 2>/dev/null)"
  n_enum=$(printf '%s\n' "$merged" | grep -c '"kind":"MAY_ENUMERATED"')
  [ "$n_enum" -eq 0 ] || note "blanket: expected 0 MAY_ENUMERATED edges (blanket gate must force MAY_TOP), got $n_enum"
fi

# ── Scenario 3: missing-facts fallback — an expected crate absent from the batch ──
if [ -n "${raw:-}" ]; then
  merged="$(printf '%s\n' "$raw" | "$MERGE" --expected-crates crate_a,crate_b,crate_c 2>/tmp/selftest-cg-rust-missing.stderr)"
  n_enum=$(printf '%s\n' "$merged" | grep -c '"kind":"MAY_ENUMERATED"')
  [ "$n_enum" -eq 0 ] || note "missing-facts: expected 0 MAY_ENUMERATED edges under fallback, got $n_enum"
  grep -q "fallback" /tmp/selftest-cg-rust-missing.stderr || note "missing-facts: fallback message not printed to stderr"
fi

# ── Scenario 4 (CHECK-6): trait-defining crate omits publish=false → stays MAY_TOP ──
mkdir -p "$WS/nopublish/crate_a/src" "$WS/nopublish/crate_b/src"
cat >"$WS/nopublish/Cargo.toml" <<'EOF'
[workspace]
members = ["crate_a", "crate_b"]
resolver = "2"
EOF
cat >"$WS/nopublish/crate_a/Cargo.toml" <<'EOF'
[package]
name = "crate_a"
version = "0.1.0"
edition = "2021"
EOF
cat >"$WS/nopublish/crate_a/src/lib.rs" <<'EOF'
pub trait Doer { fn do_it(&self); }
impl Doer for i32 { fn do_it(&self) {} }
pub fn use_dyn(d: &dyn Doer) { d.do_it(); }
EOF
cat >"$WS/nopublish/crate_b/Cargo.toml" <<'EOF'
[package]
name = "crate_b"
version = "0.1.0"
edition = "2021"
publish = false

[dependencies]
crate_a = { path = "../crate_a" }
EOF
cat >"$WS/nopublish/crate_b/src/lib.rs" <<'EOF'
pub fn entry(x: &i32) { crate_a::use_dyn(x); }
EOF
raw_nopub="$("$DRIVER_HARNESS" "$WS/nopublish" 2>/tmp/selftest-cg-rust-nopublish.stderr)"
if [ -z "$raw_nopub" ]; then
  note "nopublish: producer emitted nothing (see /tmp/selftest-cg-rust-nopublish.stderr)"
else
  merged="$(printf '%s\n' "$raw_nopub" | "$MERGE" --expected-crates crate_a,crate_b 2>/dev/null)"
  n_enum=$(printf '%s\n' "$merged" | grep -c '"kind":"MAY_ENUMERATED"')
  [ "$n_enum" -eq 0 ] || note "nopublish: expected 0 MAY_ENUMERATED edges (publish-boundary gate must force MAY_TOP), got $n_enum"
fi

if [ "$fails" -eq 0 ]; then
  echo "selftest-callgraph-rust: OK"
  exit 0
else
  echo "selftest-callgraph-rust: $fails failure(s)" >&2
  exit 1
fi
