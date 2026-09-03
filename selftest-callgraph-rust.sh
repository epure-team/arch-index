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
raw_sibling="$(ARCH_CG_RUST_NO_MERGE=1 "$DRIVER_HARNESS" "$WS/sibling" 2>/tmp/selftest-cg-rust-sibling.stderr)"
if [ -z "$raw_sibling" ]; then
  note "sibling: producer emitted nothing (see /tmp/selftest-cg-rust-sibling.stderr)"
else
  merged="$(printf '%s\n' "$raw_sibling" | "$MERGE" --expected-crates crate_a,crate_b 2>/dev/null)"
  n_enum=$(printf '%s\n' "$merged" | grep -c '"kind":"MAY_ENUMERATED"')
  n_top_dyn=$(printf '%s\n' "$merged" | grep -c '"x_dyn_trait"')
  [ "$n_enum" -ge 1 ] || note "sibling: expected >=1 MAY_ENUMERATED edge, got $n_enum"
  [ "$n_top_dyn" -eq 0 ] || note "sibling: x_dyn_trait/x_dyn_method leaked into merged output (arch-load would reject as unknown fields)"
  printf '%s\n' "$merged" | grep -q '"type":"trait_impl_fact"' && note "sibling: trait_impl_fact record leaked into merged output"
fi

# ── Scenario 2 (CHECK-5, spec US-2 AC-3): a blanket impl living in a crate
# OTHER than the dispatch-site crate → stays MAY_TOP despite a fact existing.
# FIX (test-quality, reviewer finding): this used to put the trait, the dyn
# call site, AND the blanket impl all in crate_a — exercising only the
# single-crate case A2 already handled, not the cross-crate case the merge
# pass exists to protect. The trait + dyn call site are in crate_a; the
# blanket impl is in crate_b (which also holds the direct call into
# crate_a::use_dyn, matching make_workspace's fixed crate_b template). ──
make_workspace blanket 'pub trait Doer { fn do_it(&self); }
pub fn use_dyn(d: &dyn Doer) { d.do_it(); }
'
# Orphan-rule note: `impl<T> crate_a::Doer for T` is not legal in crate_b (a
# bare, uncovered generic Self type in a foreign-trait impl violates
# coherence) — a local wrapper type covers Self while T stays fully generic,
# which is still a blanket impl by is_blanket's own definition (self_ty
# CONTAINS a Param, not just bare-Param), and is the realistic shape a
# blanket impl living in a downstream crate actually takes.
cat >"$WS/blanket/crate_b/src/lib.rs" <<'EOF'
pub struct Wrapper<T>(pub T);
impl<T: std::fmt::Debug> crate_a::Doer for Wrapper<T> { fn do_it(&self) {} }
pub fn entry(x: i32) {
    let w = Wrapper(x);
    crate_a::use_dyn(&w);
}
EOF
raw="$(ARCH_CG_RUST_NO_MERGE=1 "$DRIVER_HARNESS" "$WS/blanket" 2>/tmp/selftest-cg-rust-blanket.stderr)"
if [ -z "$raw" ]; then
  note "blanket: producer emitted nothing (see /tmp/selftest-cg-rust-blanket.stderr)"
else
  merged="$(printf '%s\n' "$raw" | "$MERGE" --expected-crates crate_a,crate_b 2>/dev/null)"
  n_enum=$(printf '%s\n' "$merged" | grep -c '"kind":"MAY_ENUMERATED"')
  [ "$n_enum" -eq 0 ] || note "blanket: expected 0 MAY_ENUMERATED edges (blanket gate must force MAY_TOP), got $n_enum"
fi

# ── Scenario 3: missing-facts fallback — an expected crate absent from the batch.
# FIX (test-quality, reviewer finding): this used to reuse the BLANKET scenario's
# raw output, whose trait already has is_blanket=true — the blanket gate alone
# forces n_enum=0 regardless of whether global_fallback is computed correctly,
# so a broken/inverted/removed fallback check would have passed silently. Reuse
# the SIBLING scenario instead: a genuinely narrowable trait that WOULD produce
# >=1 MAY_ENUMERATED edge without the fallback (as scenario 1 itself proves),
# so this assertion actually falsifies a broken fallback. ──
if [ -n "${raw_sibling:-}" ]; then
  merged="$(printf '%s\n' "$raw_sibling" | "$MERGE" --expected-crates crate_a,crate_b,crate_c 2>/tmp/selftest-cg-rust-missing.stderr)"
  n_enum=$(printf '%s\n' "$merged" | grep -c '"kind":"MAY_ENUMERATED"')
  [ "$n_enum" -eq 0 ] || note "missing-facts: expected 0 MAY_ENUMERATED edges under fallback (this same input narrows to >=1 without it — scenario 1), got $n_enum"
  grep -q "fallback" /tmp/selftest-cg-rust-missing.stderr || note "missing-facts: fallback message not printed to stderr"
fi

# ── Scenario 3b (CHECK-4, the spec's "hard requirement from intake"): a 3-crate
# flat-union case — impl_crate implements trait_crate's trait, but caller_crate
# NEVER depends on impl_crate at all. The merge pass must still find the impl,
# because the whole point of the flat-union architecture (vs. dependency-graph-
# aware merging, explicitly deferred) is that it does not care about the
# caller's own dependency edges — only about which crates were in the batch. ──
mkdir -p "$WS/flatunion/trait_crate/src" "$WS/flatunion/impl_crate/src" "$WS/flatunion/caller_crate/src"
cat >"$WS/flatunion/Cargo.toml" <<'EOF'
[workspace]
members = ["trait_crate", "impl_crate", "caller_crate"]
resolver = "2"
EOF
cat >"$WS/flatunion/trait_crate/Cargo.toml" <<'EOF'
[package]
name = "trait_crate"
version = "0.1.0"
edition = "2021"
publish = false
EOF
cat >"$WS/flatunion/trait_crate/src/lib.rs" <<'EOF'
pub trait Doer { fn do_it(&self); }
pub fn use_dyn(d: &dyn Doer) { d.do_it(); }
EOF
cat >"$WS/flatunion/impl_crate/Cargo.toml" <<'EOF'
[package]
name = "impl_crate"
version = "0.1.0"
edition = "2021"

[dependencies]
trait_crate = { path = "../trait_crate" }
EOF
cat >"$WS/flatunion/impl_crate/src/lib.rs" <<'EOF'
pub struct Widget;
impl trait_crate::Doer for Widget { fn do_it(&self) {} }
EOF
cat >"$WS/flatunion/caller_crate/Cargo.toml" <<'EOF'
[package]
name = "caller_crate"
version = "0.1.0"
edition = "2021"
publish = false

[dependencies]
trait_crate = { path = "../trait_crate" }
EOF
cat >"$WS/flatunion/caller_crate/src/lib.rs" <<'EOF'
pub fn entry(d: &dyn trait_crate::Doer) { trait_crate::use_dyn(d); }
EOF
raw_fu="$(ARCH_CG_RUST_NO_MERGE=1 "$DRIVER_HARNESS" "$WS/flatunion" 2>/tmp/selftest-cg-rust-flatunion.stderr)"
if [ -z "$raw_fu" ]; then
  note "flatunion: producer emitted nothing (see /tmp/selftest-cg-rust-flatunion.stderr)"
else
  merged="$(printf '%s\n' "$raw_fu" | "$MERGE" --expected-crates trait_crate,impl_crate,caller_crate 2>/dev/null)"
  n_enum=$(printf '%s\n' "$merged" | grep -c '"kind":"MAY_ENUMERATED"')
  printf '%s\n' "$merged" | grep -q '"callee_name":"impl_crate::{impl#0}::do_it"' \
    || note "flatunion: expected the MAY_ENUMERATED edge to include impl_crate's candidate despite caller_crate never depending on impl_crate; merged output: $merged"
  [ "$n_enum" -ge 1 ] || note "flatunion: expected >=1 MAY_ENUMERATED edge, got $n_enum"
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
raw_nopub="$(ARCH_CG_RUST_NO_MERGE=1 "$DRIVER_HARNESS" "$WS/nopublish" 2>/tmp/selftest-cg-rust-nopublish.stderr)"
if [ -z "$raw_nopub" ]; then
  note "nopublish: producer emitted nothing (see /tmp/selftest-cg-rust-nopublish.stderr)"
else
  merged="$(printf '%s\n' "$raw_nopub" | "$MERGE" --expected-crates crate_a,crate_b 2>/dev/null)"
  n_enum=$(printf '%s\n' "$merged" | grep -c '"kind":"MAY_ENUMERATED"')
  [ "$n_enum" -eq 0 ] || note "nopublish: expected 0 MAY_ENUMERATED edges (publish-boundary gate must force MAY_TOP), got $n_enum"
fi

# ── Scenario 6 (FR-002 regression): `become f()` (explicit_tail_calls,
# reachable since the harness always sets RUSTC_BOOTSTRAP=1) is a DISTINCT
# TerminatorKind::TailCall the walk once silently skipped — never drop a
# Call terminator. ──
mkdir -p "$WS/tailcall/src"
cat >"$WS/tailcall/Cargo.toml" <<'EOF'
[package]
name = "tailcall_test"
version = "0.1.0"
edition = "2021"
publish = false
EOF
cat >"$WS/tailcall/src/lib.rs" <<'EOF'
#![feature(explicit_tail_calls)]
pub fn helper() {}
pub fn caller() {
    become helper();
}
EOF
raw_tc="$(ARCH_CG_RUST_NO_MERGE=1 "$DRIVER_HARNESS" "$WS/tailcall" 2>/tmp/selftest-cg-rust-tailcall.stderr)"
if [ -z "$raw_tc" ]; then
  note "tailcall: producer emitted nothing (see /tmp/selftest-cg-rust-tailcall.stderr)"
else
  printf '%s\n' "$raw_tc" | grep -q '"caller_name":"tailcall_test::caller".*"kind":"MUST"' \
    || note "tailcall: expected a MUST edge from caller through the become-tailcall site, none found: $raw_tc"
fi

# ── Scenario 7 (CHECK-3, spec US-1 AC-4): a named `extern "C"` call site must
# be MAY_TOP with the real symbol recorded, never the anonymous *TOP* sentinel
# alone — distinguishes "target named but body unanalyzable" from "target
# truly unknown". ──
mkdir -p "$WS/ffi/src"
cat >"$WS/ffi/Cargo.toml" <<'EOF'
[package]
name = "ffi_test"
version = "0.1.0"
edition = "2021"
publish = false
EOF
cat >"$WS/ffi/src/lib.rs" <<'EOF'
extern "C" { fn my_external_symbol(x: i32) -> i32; }
pub fn caller() {
    unsafe { my_external_symbol(1); }
}
EOF
raw_ffi="$(ARCH_CG_RUST_NO_MERGE=1 "$DRIVER_HARNESS" "$WS/ffi" 2>/tmp/selftest-cg-rust-ffi.stderr)"
if [ -z "$raw_ffi" ]; then
  note "ffi: producer emitted nothing (see /tmp/selftest-cg-rust-ffi.stderr)"
else
  printf '%s\n' "$raw_ffi" | grep -q '"callee_name":"\*TOP\*"' \
    && note "ffi: extern \"C\" call site emitted the anonymous *TOP* sentinel instead of the real symbol name: $raw_ffi"
  printf '%s\n' "$raw_ffi" | grep -q 'my_external_symbol.*"kind":"MAY_TOP"' \
    || note "ffi: expected a MAY_TOP edge naming my_external_symbol, none found: $raw_ffi"
fi

# ── Scenario 5: the documented direct-pipe usage ("arch-callgraph-rust <dir>
# | arch-load out.db") must actually work — regression test for the CRITICAL
# where the harness's raw per-crate output (trait_impl_fact/x_dyn_* records)
# broke arch-load's strict contract, since nothing ran the merge pass by
# default. The harness now always merges unless ARCH_CG_RUST_NO_MERGE=1. ──
ARCH_LOAD="$HERE/_build/default/bin/arch_load/arch_load.exe"
if [ ! -x "$ARCH_LOAD" ]; then
  ARCH_LOAD="$(command -v opam >/dev/null 2>&1 && opam exec --switch=/home/mathias/dev/arch-index -- dune build --root="$HERE" bin/arch_load 2>/dev/null; echo "$HERE/_build/default/bin/arch_load/arch_load.exe")"
fi
if [ -x "$ARCH_LOAD" ]; then
  DB="$(mktemp --suffix=.db)"
  rm -f "$DB"
  if ! "$DRIVER_HARNESS" "$WS/sibling" 2>/tmp/selftest-cg-rust-directpipe.stderr | "$ARCH_LOAD" "$DB" >/tmp/selftest-cg-rust-directpipe.load.stderr 2>&1; then
    note "direct-pipe: arch-callgraph-rust <dir> | arch-load <db> failed (see /tmp/selftest-cg-rust-directpipe.stderr and .load.stderr) — the documented usage in arch-callgraph-rust's own header must work by default"
  fi
  rm -f "$DB"
else
  echo "selftest-callgraph-rust: skipping direct-pipe scenario — arch_load.exe not built (dune build bin/arch_load)"
fi

# ── Scenario 9 (CHECK-6 inheritance variant, QA-round regression): a root
# `[workspace.package] publish = false` + a member's `publish.workspace =
# true` must resolve to publish_false=true. This was DEAD CODE — the
# workspace-inheritance branch in source_crate_sets_publish_false could never
# execute, because toml_publish_false matched the literal substring "true" in
# "publish.workspace = true" and returned before the inheritance-walk logic
# ever ran. Caught by roster-qa testing the exact case its own scope brief
# named, missed by every implement/review round before it. ──
mkdir -p "$WS/wsinherit/crate_a/src" "$WS/wsinherit/crate_b/src"
cat >"$WS/wsinherit/Cargo.toml" <<'EOF'
[workspace]
members = ["crate_a", "crate_b"]
resolver = "2"

[workspace.package]
publish = false
EOF
cat >"$WS/wsinherit/crate_a/Cargo.toml" <<'EOF'
[package]
name = "crate_a"
version = "0.1.0"
edition = "2021"
publish.workspace = true
EOF
cat >"$WS/wsinherit/crate_a/src/lib.rs" <<'EOF'
pub trait Doer { fn do_it(&self); }
impl Doer for i32 { fn do_it(&self) {} }
pub fn use_dyn(d: &dyn Doer) { d.do_it(); }
EOF
cat >"$WS/wsinherit/crate_b/Cargo.toml" <<'EOF'
[package]
name = "crate_b"
version = "0.1.0"
edition = "2021"
publish = false

[dependencies]
crate_a = { path = "../crate_a" }
EOF
cat >"$WS/wsinherit/crate_b/src/lib.rs" <<'EOF'
pub fn entry(x: &i32) { crate_a::use_dyn(x); }
EOF
raw_wsinherit="$(ARCH_CG_RUST_NO_MERGE=1 "$DRIVER_HARNESS" "$WS/wsinherit" 2>/tmp/selftest-cg-rust-wsinherit.stderr)"
if [ -z "$raw_wsinherit" ]; then
  note "wsinherit: producer emitted nothing (see /tmp/selftest-cg-rust-wsinherit.stderr)"
else
  printf '%s\n' "$raw_wsinherit" | grep -q '"publish_false":true' \
    || note "wsinherit: expected publish_false:true (inherited from [workspace.package]), got: $raw_wsinherit"
fi

# ── Scenario 10 (comment-parsing false-positive, review-round regression):
# `publish = true  # was false during beta` must NOT be misread as
# publish=false — the naive scanner used to match "false" inside the trailing
# comment before ever checking for "true" on the real value. ──
mkdir -p "$WS/pubcomment/crate_a/src" "$WS/pubcomment/crate_b/src"
cat >"$WS/pubcomment/Cargo.toml" <<'EOF'
[workspace]
members = ["crate_a", "crate_b"]
resolver = "2"
EOF
cat >"$WS/pubcomment/crate_a/Cargo.toml" <<'EOF'
[package]
name = "crate_a"
version = "0.1.0"
edition = "2021"
publish = true  # was false during beta, now released
EOF
cat >"$WS/pubcomment/crate_a/src/lib.rs" <<'EOF'
pub trait Doer { fn do_it(&self); }
impl Doer for i32 { fn do_it(&self) {} }
pub fn use_dyn(d: &dyn Doer) { d.do_it(); }
EOF
cat >"$WS/pubcomment/crate_b/Cargo.toml" <<'EOF'
[package]
name = "crate_b"
version = "0.1.0"
edition = "2021"
publish = false

[dependencies]
crate_a = { path = "../crate_a" }
EOF
cat >"$WS/pubcomment/crate_b/src/lib.rs" <<'EOF'
pub fn entry(x: &i32) { crate_a::use_dyn(x); }
EOF
raw_pubcomment="$(ARCH_CG_RUST_NO_MERGE=1 "$DRIVER_HARNESS" "$WS/pubcomment" 2>/tmp/selftest-cg-rust-pubcomment.stderr)"
if [ -z "$raw_pubcomment" ]; then
  note "pubcomment: producer emitted nothing (see /tmp/selftest-cg-rust-pubcomment.stderr)"
else
  printf '%s\n' "$raw_pubcomment" | grep -q '"publish_false":false' \
    || note "pubcomment: expected publish_false:false (crate_a is actually publish=true; the comment must not fool the scanner), got: $raw_pubcomment"
fi

if [ "$fails" -eq 0 ]; then
  echo "selftest-callgraph-rust: OK"
  exit 0
else
  echo "selftest-callgraph-rust: $fails failure(s)" >&2
  exit 1
fi
