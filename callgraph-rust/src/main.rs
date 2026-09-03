//! arch-callgraph-rust — Rust Tier-1 call-graph producer for the arch-index edge-kind contract.
//!
//! A GENERAL-PURPOSE producer for ANY cargo workspace, the Rust analogue of
//! `arch-callgraph-go` (go/ssa + CHA) and the OCaml CMT walk.
//!
//! It emits NDJSON function+call records on stdout, one per line:
//!   {"type":"function","name":"krate::path::f","file_path":"x.rs","line_start":10,
//!    "line_end":12,"exported":true}
//!   {"type":"call","caller_name":"…","caller_file":"x.rs","callee_name":"…",
//!    "callee_file":"y.rs"|null,"call_site":"x.rs:42","kind":"MUST|MAY_ENUMERATED|MAY_TOP"}
//!
//! Pipe to `arch-load out.db` → `arch-query out.db unreachable A B` (sound over-approx).
//!
//! ## Mechanism (single-crate walker)
//!
//! A `rustc_private` driver: a `rustc_driver::Callbacks::after_analysis` hook
//! drives the compiler to post-`analysis`, enumerates every reachable
//! monomorphic function instance via the monomorphization collector, walks
//! every `TerminatorKind::Call` in each instance's MIR, and resolves the callee
//! via `Instance::resolve`.
//!
//! ## The load-bearing invariant (FR-002)
//!
//! **Never drop a `Call` terminator.** An unresolvable call site becomes a
//! MAY_TOP edge to the `*TOP*` sentinel — never silently absent. This file was
//! rewritten fresh (not ported) against `roster/rust-soundcg-whole-program`'s
//! own review, which found FOUR independent ways an earlier draft violated
//! this exact invariant. Each is called out at its fix site below.
//!
//! ## Whole-program trait-impl enumeration (not built here)
//!
//! This file emits per-crate MUST/MAY_TOP edges and, for cross-crate whole-
//! program precision, a per-crate trait-impl FACT stream (a separate NDJSON
//! record type) that a later merge pass consumes — see
//! `specs/rust-soundcg-whole-program.md`. `dyn` dispatch sites stay MAY_TOP in
//! this file; the merge pass narrows them to MAY_ENUMERATED post-hoc.

#![feature(rustc_private)]

extern crate rustc_driver;
extern crate rustc_hir;
extern crate rustc_interface;
extern crate rustc_middle;
extern crate rustc_monomorphize;
extern crate rustc_session;
extern crate rustc_span;

use std::collections::HashSet;
use std::io::{self, Write};
use std::process::ExitCode;

use rustc_driver::{Callbacks, Compilation};
use rustc_hir::def_id::DefId;
use rustc_interface::interface;
use rustc_middle::mir::{Body, Operand, TerminatorKind};
use rustc_middle::mono::MonoItem;
use rustc_middle::ty::{self, Instance, InstanceKind, Ty, TyCtxt, TypingEnv};
use rustc_session::config::ErrorOutputType;
use rustc_session::EarlyDiagCtxt;
use rustc_span::Span;

const TOP: &str = "*TOP*";

/// JSON-escape a string for embedding in an NDJSON value.
fn json_escape(s: &str) -> String {
    let mut out = String::with_capacity(s.len() + 2);
    for c in s.chars() {
        match c {
            '"' => out.push_str("\\\""),
            '\\' => out.push_str("\\\\"),
            '\n' => out.push_str("\\n"),
            '\r' => out.push_str("\\r"),
            '\t' => out.push_str("\\t"),
            c if (c as u32) < 0x20 => out.push_str(&format!("\\u{:04x}", c as u32)),
            c => out.push(c),
        }
    }
    out
}

fn json_str_field(name: &str, value: &str) -> String {
    format!("\"{}\":\"{}\"", name, json_escape(value))
}

fn json_opt_str_field(name: &str, value: Option<&str>) -> String {
    match value {
        Some(v) => format!("\"{}\":\"{}\"", name, json_escape(v)),
        None => format!("\"{}\":null", name),
    }
}

fn json_opt_u32_field(name: &str, value: Option<u32>) -> String {
    match value {
        Some(v) => format!("\"{}\":{}", name, v),
        None => format!("\"{}\":null", name),
    }
}

/// Buffered stdout sink for NDJSON records.
///
/// FIX (rust-cg-emitter-flush-ignores-io-errors, MEDIUM): `flush` now returns
/// `io::Result<()>` and `main` propagates a write failure as a non-zero exit —
/// a short write / ENOSPC / EPIPE used to be silently swallowed while the
/// process still exited 0, defeating the loud-fail invariant.
#[derive(Default)]
struct Emitter {
    out: Vec<u8>,
    n_funcs: usize,
    n_must: usize,
    n_may_top: usize,
    n_facts: usize,
    seen: HashSet<String>,
}

impl Emitter {
    fn function(
        &mut self,
        name: &str,
        file: Option<&str>,
        line_start: Option<u32>,
        line_end: Option<u32>,
        exported: bool,
    ) {
        // FIX (rust-cg-missing-line-start-end, HIGH): populate line_start/line_end
        // so arch-impact can map a diff hunk to the functions it touches, matching
        // the Go and OCaml producers' output contract instead of silently
        // degrading Rust to file-granularity impact analysis.
        let _ = writeln!(
            self.out,
            "{{\"type\":\"function\",{},{},{},{},\"exported\":{}}}",
            json_str_field("name", name),
            json_opt_str_field("file_path", file),
            json_opt_u32_field("line_start", line_start),
            json_opt_u32_field("line_end", line_end),
            exported
        );
        self.n_funcs += 1;
    }

    fn call(
        &mut self,
        caller: &str,
        caller_file: Option<&str>,
        callee: &str,
        callee_file: Option<&str>,
        site: &str,
        kind: &str,
    ) {
        let key = format!("{caller}\u{2192}{callee}@{site}");
        if !self.seen.insert(key) {
            return;
        }
        let _ = writeln!(
            self.out,
            "{{\"type\":\"call\",{},{},{},{},{},\"kind\":\"{}\"}}",
            json_str_field("caller_name", caller),
            json_opt_str_field("caller_file", caller_file),
            json_str_field("callee_name", callee),
            json_opt_str_field("callee_file", callee_file),
            json_str_field("call_site", site),
            kind
        );
        match kind {
            "MUST" => self.n_must += 1,
            "MAY_TOP" => self.n_may_top += 1,
            _ => {}
        }
    }

    /// A `dyn Trait` dispatch call site. Emitted as a MAY_TOP edge (this
    /// single-crate walk never resolves it), but carries `dyn_trait`/
    /// `dyn_method` fields so the whole-program merge pass can find and
    /// narrow it — a plain `kind:"MAY_TOP"` edge alone is indistinguishable
    /// from an fn-ptr/FFI/foreign MAY_TOP, which the merge pass must NOT try
    /// to narrow.
    fn call_dyn(&mut self, caller: &str, caller_file: Option<&str>, site: &str, trait_path: &str, method_name: &str) {
        let key = format!("{caller}\u{2192}dyn:{trait_path}::{method_name}@{site}");
        if !self.seen.insert(key) {
            return;
        }
        let _ = writeln!(
            self.out,
            "{{\"type\":\"call\",{},{},\"callee_name\":\"{}\",\"callee_file\":null,{},\"kind\":\"MAY_TOP\",{},{}}}",
            json_str_field("caller_name", caller),
            json_opt_str_field("caller_file", caller_file),
            TOP,
            json_str_field("call_site", site),
            json_str_field("x_dyn_trait", trait_path),
            json_str_field("x_dyn_method", method_name)
        );
        self.n_may_top += 1;
    }

    /// Per-crate trait-impl fact record, consumed by the (separate) whole-program
    /// merge pass. `impl_crate` is the crate PROVIDING this impl (used by the
    /// merge pass's missing-facts fallback, to know which crates' facts are
    /// present in a batch). `publish_false` reflects the TRAIT's OWN DEFINING
    /// crate's Cargo.toml `publish` key (NOT `impl_crate`'s — the safety gate
    /// is about whether the trait itself could be extended by an external,
    /// unseen crate) — see specs/rust-soundcg-whole-program.md's
    /// publish-boundary safety gate. Emitted regardless of whether anything
    /// downstream reads it yet (spec's explicit US-1/US-2 coupling).
    fn trait_impl_fact(
        &mut self,
        trait_path: &str,
        self_type_path: &str,
        method_name: &str,
        impl_crate: &str,
        publish_false: bool,
        is_blanket: bool,
    ) {
        let _ = writeln!(
            self.out,
            "{{\"type\":\"trait_impl_fact\",{},{},{},{},\"publish_false\":{},\"is_blanket\":{}}}",
            json_str_field("trait_path", trait_path),
            json_str_field("self_type_path", self_type_path),
            json_str_field("method_name", method_name),
            json_str_field("impl_crate", impl_crate),
            publish_false,
            is_blanket
        );
        self.n_facts += 1;
    }

    fn flush(&self) -> io::Result<()> {
        let stdout = io::stdout();
        let mut lock = stdout.lock();
        lock.write_all(&self.out)?;
        lock.flush()
    }
}

/// Stable, human-readable qualified name for an instance.
///
/// FIX (rust-cg-shim-name-collapse-drop-glue, MEDIUM): a bare `def_path_str`
/// collapses every monomorphization of a shim InstanceKind (DropGlue, CloneShim,
/// ...) onto ONE name, since `instance.def_id()` returns the shim's *declaring*
/// DefId (e.g. `core::ptr::drop_in_place`), not a per-type identity. That made
/// unrelated `Drop`/`Clone` impls mutually "reachable" through one shared node.
/// This now folds the shim's own discriminating `Ty` into the name so distinct
/// monomorphizations get distinct, injective node identities.
fn instance_name<'tcx>(tcx: TyCtxt<'tcx>, instance: Instance<'tcx>) -> String {
    match instance.def {
        InstanceKind::DropGlue(_, Some(ty)) => format!("<{ty} as Drop>::drop#glue"),
        InstanceKind::DropGlue(_, None) => "core::ptr::drop_in_place#empty".to_string(),
        InstanceKind::CloneShim(_, ty) => format!("<{ty} as Clone>::clone#shim"),
        InstanceKind::FnPtrShim(_, ty) => format!("<{ty} as Fn>::call#shim"),
        InstanceKind::FnPtrAddrShim(_, ty) => format!("<{ty} as FnPtr>::addr#shim"),
        InstanceKind::AsyncDropGlueCtorShim(_, ty) => format!("<{ty}>::async_drop_in_place#shim"),
        InstanceKind::AsyncDropGlue(_, ty) => format!("<{ty}>::async_drop_in_place#poll"),
        InstanceKind::ClosureOnceShim { closure, .. } => {
            format!("{}#call_once_shim", tcx.def_path_str(closure))
        }
        _ => tcx.def_path_str(instance.def_id()),
    }
}

/// Qualified name for a bare DefId (used for the function-universe node pass).
fn def_name<'tcx>(tcx: TyCtxt<'tcx>, def_id: DefId) -> String {
    tcx.def_path_str(def_id)
}

/// A CRATE-INDEPENDENT qualified path for a def: always
/// `"<defining-crate>::<path-within-that-crate>"`, regardless of which
/// crate's compilation is currently rendering it.
///
/// `def_path_str` is unsuitable for anything the whole-program merge pass
/// needs to JOIN across separately-compiled crates: it renders a path
/// relative to the CURRENT crate's own view, so the same trait comes out as
/// bare `"Doer"` when a call site in its OWN defining crate renders it, but
/// as `"crate_a::Doer"` when a DIFFERENT crate's `impl crate_a::Doer for B`
/// renders the same trait — two different strings identifying the same
/// definition. Every field the merge pass matches ACROSS crates (the trait
/// identity in both `trait_impl_fact` and `dyn_trait`) must use this instead.
fn stable_def_path<'tcx>(tcx: TyCtxt<'tcx>, def_id: DefId) -> String {
    format!(
        "{}{}",
        tcx.crate_name(def_id.krate),
        tcx.def_path(def_id).to_string_no_crate_verbose()
    )
}

fn real_path_of(name: &rustc_span::FileName) -> Option<String> {
    match name {
        rustc_span::FileName::Real(real) => real.local_path().map(|p| p.to_string_lossy().into_owned()),
        _ => None,
    }
}

/// Source file of a span (best-effort).
fn span_file<'tcx>(tcx: TyCtxt<'tcx>, span: Span) -> Option<String> {
    if span.is_dummy() {
        return None;
    }
    let sm = tcx.sess.source_map();
    let lo = sm.lookup_char_pos(span.lo());
    real_path_of(&lo.file.name).or_else(|| Some(format!("{:?}", lo.file.name)))
}

/// "file:line" call-site string for an edge.
///
/// FIX (rust-cg-span-site-empty-on-dummy-span, LOW): a dummy `fn_span` (routine
/// in macro-expanded / compiler-synthesized MIR) used to collapse to `""`,
/// merging every such edge from one caller into one dedup'd record regardless
/// of how many distinct call terminators produced them. Falls back to the
/// caller's own def span, which is never dummy for a real caller instance.
fn span_site<'tcx>(tcx: TyCtxt<'tcx>, span: Span, fallback: Span) -> String {
    let use_span = if span.is_dummy() { fallback } else { span };
    if use_span.is_dummy() {
        return "<unknown>:0".to_string();
    }
    let sm = tcx.sess.source_map();
    let lo = sm.lookup_char_pos(use_span.lo());
    let file = real_path_of(&lo.file.name).unwrap_or_else(|| format!("{:?}", lo.file.name));
    format!("{}:{}", file, lo.line)
}

fn def_file<'tcx>(tcx: TyCtxt<'tcx>, def_id: DefId) -> Option<String> {
    span_file(tcx, tcx.def_span(def_id))
}

/// (line_start, line_end) for a def, 1-based, matching the Go/OCaml producers.
fn def_line_range<'tcx>(tcx: TyCtxt<'tcx>, def_id: DefId) -> (Option<u32>, Option<u32>) {
    let span = tcx.def_span(def_id);
    if span.is_dummy() {
        return (None, None);
    }
    let sm = tcx.sess.source_map();
    let lo = sm.lookup_char_pos(span.lo());
    let hi = sm.lookup_char_pos(span.hi());
    (Some(lo.line as u32), Some(hi.line as u32))
}

/// True if a function is part of the crate's public API surface (best-effort).
///
/// FIX (rust-cg-is-exported-false-for-nonlocal-defids, MEDIUM): this used to
/// hard-return `false` for every non-local DefId, even though it is called on
/// monomorphizations of upstream-generic items. `is_reachable_non_generic`
/// reflects the item's own visibility from crate metadata instead of
/// hard-coding an answer we don't actually know.
fn is_exported<'tcx>(tcx: TyCtxt<'tcx>, def_id: DefId) -> bool {
    match def_id.as_local() {
        Some(local) => tcx.effective_visibilities(()).is_exported(local),
        None => tcx.is_reachable_non_generic(def_id),
    }
}

/// Best-effort test for "this non-local def's source is a workspace member or
/// a local path dependency" — i.e. exactly the set `RUSTC_WORKSPACE_WRAPPER`
/// guarantees gets compiled through THIS SAME driver binary (in a separate
/// per-crate process), as opposed to std/core or a registry (crates.io)
/// dependency, which this process cannot verify was ever walked at all.
///
/// Distinguishing these two matters: without it, EVERY cross-crate call
/// (including a plain, non-trait call from one workspace crate to a sibling
/// workspace crate — the exact case whole-program analysis exists to resolve)
/// would be forced to MAY_TOP, which is sound but throws away most of this
/// producer's value. The heuristic: a def's source file path is NOT under the
/// toolchain sysroot and NOT under `~/.cargo/registry` — i.e. it is a real,
/// locally-checked-out `.rs` file, which is what path/workspace dependencies
/// look like and registry/sysroot sources do not.
///
/// This is a heuristic, not a proof (a vendored or git-checkout dependency can
/// also look "local" without being wrapped) — it only ever WIDENS which cases
/// get a chance at MUST; the foreign/registry/sysroot cases it correctly
/// rejects still fall back to the always-safe MAY_TOP path above.
fn is_workspace_analysed_source<'tcx>(tcx: TyCtxt<'tcx>, def_id: DefId) -> bool {
    let span = tcx.def_span(def_id);
    if span.is_dummy() {
        return false;
    }
    let sm = tcx.sess.source_map();
    let lo = sm.lookup_char_pos(span.lo());
    let path = match real_path_of(&lo.file.name) {
        Some(p) => p,
        None => return false,
    };
    let sysroot = tcx.sess.opts.sysroot.path().to_string_lossy().into_owned();
    if path.starts_with(sysroot.as_str()) {
        return false;
    }
    if path.contains("/.cargo/registry/") || path.contains("/.cargo/git/") {
        return false;
    }
    true
}

/// FIX (rust-cg-shim-body-skipped-by-mir-available-guard, CRITICAL): the prior
/// guard tested `is_mir_available(instance.def_id())`. For a shim InstanceKind,
/// `def_id()` names the *declaring* item (e.g. `Clone::clone`'s trait
/// declaration), which has no HIR body and so is never in `mir_keys` — `false`
/// every time, even though `tcx.instance_mir(instance.def)` builds the shim's
/// real synthesized body on demand via `mir_shims`, independent of
/// `is_mir_available`. That silently skipped every field-wise clone call, every
/// indirect fn-pointer call, and every closure `call_once` dispatch — exactly
/// the calls this producer exists to anchor. Only `Intrinsic` (evaluated
/// "magically" by codegen/const-eval, never has real MIR) and `Virtual`
/// (dispatch indirection, not itself a body to walk) have no walkable body.
fn has_walkable_mir<'tcx>(tcx: TyCtxt<'tcx>, instance: Instance<'tcx>) -> bool {
    match instance.def {
        InstanceKind::Intrinsic(_) => false,
        InstanceKind::Virtual(..) => false,
        InstanceKind::Item(def_id) => tcx.is_mir_available(def_id),
        _ => true,
    }
}

/// The classification result for one `Call` terminator.
enum Callee {
    Must { name: String, file: Option<String> },
    Top { name: String },
    /// `dyn Trait` virtual dispatch — MAY_TOP within this single-crate walk,
    /// but carries the (trait_path, method_name) the whole-program merge pass
    /// needs to later narrow it to MAY_ENUMERATED against the union of
    /// `trait_impl_fact` records across the workspace. See
    /// specs/rust-soundcg-whole-program.md.
    DynDispatch { trait_path: String, method_name: String },
}

/// Classify a `Call` terminator's callee operand into MUST or MAY_TOP.
///
/// FIX (rust-cg-instancekind-catchall-defaults-to-must, CRITICAL): the prior
/// `_ => Callee::Must` arm defaulted every InstanceKind this match didn't name
/// explicitly to MUST — including `FnPtrShim`/`ClosureOnceShim`, which is
/// exactly the *indirect* dispatch case this producer exists to anchor as
/// unknown. This match is now exhaustive over every `InstanceKind` variant (a
/// future rustc bump adding a variant is a compile error here, not a silent
/// soundness regression) and each arm's classification is justified below.
///
/// FIX (rust-cg-must-edge-to-unanalysed-crate, CRITICAL): a resolved `Item`
/// callee defined in a crate this process did not itself compile (std/core, or
/// any dependency not wrapped by our own `RUSTC_WORKSPACE_WRAPPER` invocation)
/// used to still get MUST, with no anchor — every transitive call through it
/// silently vanished. Only a LOCAL item (this crate's own compilation) can be
/// trusted to have its own outbound calls walked by THIS process, so only a
/// local item resolution stays MUST; everything else becomes an anchored
/// MAY_TOP frontier.
fn classify_callee<'tcx>(
    tcx: TyCtxt<'tcx>,
    typing_env: TypingEnv<'tcx>,
    instance: Instance<'tcx>,
    func: &Operand<'tcx>,
    body: &Body<'tcx>,
) -> Callee {
    let func_ty = func.ty(body, tcx);
    let func_ty: Ty<'tcx> = instance.instantiate_mir_and_normalize_erasing_regions(
        tcx,
        typing_env,
        ty::EarlyBinder::bind(func_ty),
    );

    match func_ty.kind() {
        ty::FnDef(def_id, args) => {
            if tcx.is_foreign_item(*def_id) {
                return Callee::Top { name: TOP.to_string() };
            }
            if tcx.intrinsic(*def_id).is_some() {
                return Callee::Top { name: TOP.to_string() };
            }
            match Instance::try_resolve(tcx, typing_env, *def_id, args) {
                Ok(Some(callee_inst)) => classify_resolved(tcx, callee_inst),
                Ok(None) => Callee::Top { name: TOP.to_string() },
                Err(_) => Callee::Top { name: TOP.to_string() },
            }
        }
        ty::FnPtr(..) => Callee::Top { name: TOP.to_string() },
        _ => Callee::Top { name: TOP.to_string() },
    }
}

/// Classify an already-resolved `Instance` (post `Instance::try_resolve`).
/// Exhaustive over `InstanceKind` — see `classify_callee`'s doc comment.
fn classify_resolved<'tcx>(tcx: TyCtxt<'tcx>, callee_inst: Instance<'tcx>) -> Callee {
    match callee_inst.def {
        InstanceKind::Item(def_id) => {
            if tcx.is_foreign_item(def_id) {
                Callee::Top { name: TOP.to_string() }
            } else if !def_id.is_local() && !is_workspace_analysed_source(tcx, def_id) {
                // Cross-crate into std/core, a registry (crates.io) dependency,
                // or anything else this process cannot verify was walked by our
                // own driver. Anchor, don't assume. Distinct from a workspace
                // member / path dependency (see is_workspace_analysed_source):
                // RUSTC_WORKSPACE_WRAPPER guarantees those ARE wrapped by this
                // same driver binary, in a separate per-crate process — a real,
                // verifiable MUST target, not a guess.
                Callee::Top { name: TOP.to_string() }
            } else {
                Callee::Must {
                    name: instance_name(tcx, callee_inst),
                    file: def_file(tcx, def_id),
                }
            }
        }
        InstanceKind::Intrinsic(_) => Callee::Top { name: TOP.to_string() },
        InstanceKind::Virtual(method_def_id, _) => match tcx.trait_of_assoc(method_def_id) {
            Some(trait_def_id) => Callee::DynDispatch {
                trait_path: stable_def_path(tcx, trait_def_id),
                method_name: tcx.item_name(method_def_id).to_string(),
            },
            // Not actually a trait method (shouldn't happen for Virtual, but
            // never assume — fall back to the always-safe anchor).
            None => Callee::Top { name: TOP.to_string() },
        },
        // Concrete, deterministic compiler-synthesized bodies: once walked (the
        // has_walkable_mir fix), these have a single fixed target per
        // monomorphization and an injective name (the instance_name fix) — MUST
        // is directionally correct, not a certainty gap.
        InstanceKind::VTableShim(_)
        | InstanceKind::ReifyShim(_, _)
        | InstanceKind::DropGlue(_, _)
        | InstanceKind::CloneShim(_, _)
        | InstanceKind::AsyncDropGlueCtorShim(_, _) => Callee::Must {
            name: instance_name(tcx, callee_inst),
            file: def_file(tcx, callee_inst.def_id()),
        },
        // The shim's OWN body performs the genuinely-unbounded indirect
        // dispatch (an arbitrary fn pointer / closure environment / coroutine
        // continuation) — the call INTO the shim is real, but treating it as a
        // certainty here would be the exact false-confidence bug this producer
        // exists to prevent. Conservative: MAY_TOP.
        InstanceKind::FnPtrShim(_, _)
        | InstanceKind::ClosureOnceShim { .. }
        | InstanceKind::ConstructCoroutineInClosureShim { .. }
        | InstanceKind::ThreadLocalShim(_)
        | InstanceKind::FutureDropPollShim(_, _, _)
        | InstanceKind::FnPtrAddrShim(_, _)
        | InstanceKind::AsyncDropGlue(_, _) => Callee::Top { name: TOP.to_string() },
    }
}

/// Walk one instance's MIR, emitting one edge per `Call` terminator.
/// Never drops a `Call` terminator (FR-002). Returns true if a body was
/// actually walked (used by the caller to track the walked-node set — see
/// `run_analysis`'s unwalked-node fix).
fn walk_instance<'tcx>(tcx: TyCtxt<'tcx>, instance: Instance<'tcx>, emit: &mut Emitter) -> bool {
    if !has_walkable_mir(tcx, instance) {
        return false;
    }
    let body: &Body<'tcx> = tcx.instance_mir(instance.def);
    let typing_env = TypingEnv::fully_monomorphized();

    let caller_name = instance_name(tcx, instance);
    let caller_def_span = tcx.def_span(instance.def_id());
    let caller_file = span_file(tcx, caller_def_span);

    for bb in body.basic_blocks.iter() {
        let term = match &bb.terminator {
            Some(t) => t,
            None => continue,
        };
        if let TerminatorKind::Call { func, fn_span, .. } = &term.kind {
            let site = span_site(tcx, *fn_span, caller_def_span);
            match classify_callee(tcx, typing_env, instance, func, body) {
                Callee::Must { name, file } => {
                    emit.call(&caller_name, caller_file.as_deref(), &name, file.as_deref(), &site, "MUST");
                }
                Callee::Top { name } => {
                    emit.call(&caller_name, caller_file.as_deref(), &name, None, &site, "MAY_TOP");
                }
                Callee::DynDispatch { trait_path, method_name } => {
                    emit.call_dyn(&caller_name, caller_file.as_deref(), &site, &trait_path, &method_name);
                }
            }
        }
    }
    true
}

/// Whether the crate whose source file is at `source_file` sets
/// `publish = false` — the publish-boundary safety gate's input (see
/// specs/rust-soundcg-whole-program.md, "Publish-boundary safety gate").
///
/// FIX: this is keyed on the TRAIT-DEFINING crate's own source location, not
/// on `CARGO_MANIFEST_DIR` (this process's OWN compiling crate). The gate's
/// whole point is "could an external, unseen crate implement THIS trait" —
/// that depends on whether the trait's own defining crate is publishable, not
/// on whether the crate currently providing one particular impl happens to
/// be. Walks up from `source_file`'s directory to find the nearest ancestor
/// `Cargo.toml`, which is that crate's own manifest (or, if `publish =
/// X.workspace = true`, its workspace root's `[workspace.package]`).
///
/// A deliberately conservative, cheap proxy (documented residual, not a
/// strong guarantee): key absent, path undeterminable, or `publish = true`
/// all count as "potentially publishable" — the gate errs toward MAY_TOP,
/// never toward a false MAY_ENUMERATED.
fn source_crate_sets_publish_false(source_file: &str) -> bool {
    let start_dir = match std::path::Path::new(source_file).parent() {
        Some(d) => d,
        None => return false,
    };
    let mut dir = Some(start_dir);
    while let Some(d) = dir {
        let candidate = d.join("Cargo.toml");
        if let Ok(contents) = std::fs::read_to_string(&candidate) {
            if contents.contains("[package]") {
                match toml_publish_false(&contents, "package") {
                    Some(false_flag) => return false_flag,
                    None => {}
                }
                if toml_key_is_workspace_true(&contents, "publish") {
                    // Resolve against the workspace root, found by continuing
                    // to walk up for an ancestor Cargo.toml with [workspace].
                    let mut wsdir = d.parent();
                    while let Some(w) = wsdir {
                        let wscandidate = w.join("Cargo.toml");
                        if let Ok(wc) = std::fs::read_to_string(&wscandidate) {
                            if wc.contains("[workspace]") {
                                if let Some(false_flag) = toml_publish_false(&wc, "workspace.package") {
                                    return false_flag;
                                }
                                break;
                            }
                        }
                        wsdir = w.parent();
                    }
                }
                return false;
            }
        }
        dir = d.parent();
    }
    false
}

/// Best-effort, non-full-TOML-parser scan for `publish = false` (or `= true`)
/// under a `[section]` header (`section` is `"package"` or `"workspace.package"`,
/// matched against `[package]`/`[workspace.package]` respectively). Returns
/// `Some(true)` if `publish = false` is found, `Some(false)` if `publish = true`
/// is found, `None` if the key is absent from that section.
fn toml_publish_false(contents: &str, section: &str) -> Option<bool> {
    let header = format!("[{section}]");
    let mut in_section = false;
    for line in contents.lines() {
        let trimmed = line.trim();
        if trimmed.starts_with('[') {
            in_section = trimmed == header;
            continue;
        }
        if in_section && trimmed.starts_with("publish") {
            if trimmed.contains("false") {
                return Some(true);
            }
            if trimmed.contains("true") {
                return Some(false);
            }
        }
    }
    None
}

fn toml_key_is_workspace_true(contents: &str, key: &str) -> bool {
    for line in contents.lines() {
        let trimmed = line.trim();
        if trimmed.starts_with(key) && trimmed.contains(".workspace") && trimmed.contains("true") {
            return true;
        }
    }
    false
}

/// Emit one trait-impl fact per (impl, method) pair defined LOCALLY in this
/// crate. Consumed by the (separate) whole-program merge pass — see
/// specs/rust-soundcg-whole-program.md. Emitted unconditionally, even though
/// nothing in this file's own single-crate walk reads it back (the spec's
/// explicit US-1/US-2 coupling: US-1 emits the facts, US-2's merge pass is
/// what acts on them).
fn emit_trait_impl_facts<'tcx>(tcx: TyCtxt<'tcx>, emit: &mut Emitter) {
    let impl_crate = tcx.crate_name(rustc_hir::def_id::LOCAL_CRATE).to_string();
    let mut trait_publish_false_cache: std::collections::HashMap<DefId, bool> = std::collections::HashMap::new();
    for (trait_def_id, impl_local_ids) in tcx.all_local_trait_impls(()) {
        let trait_path = stable_def_path(tcx, *trait_def_id);
        // Keyed on the TRAIT's OWN source location (see
        // source_crate_sets_publish_false's doc), not this compiling crate —
        // an impl in crate B of a trait defined in crate A must check A's
        // publish flag, not B's.
        let publish_false = *trait_publish_false_cache.entry(*trait_def_id).or_insert_with(|| {
            let span = tcx.def_span(*trait_def_id);
            match span_file(tcx, span) {
                Some(f) => source_crate_sets_publish_false(&f),
                None => false,
            }
        });
        for impl_local_id in impl_local_ids {
            let impl_def_id = impl_local_id.to_def_id();
            let trait_ref = tcx.impl_trait_ref(impl_def_id).skip_binder();
            let self_ty = trait_ref.self_ty();
            let self_type_path = self_ty.to_string();
            // A blanket impl's Self type is (or is built from) a bare generic
            // type parameter of the impl block (`impl<T> Trait for T`, or
            // `impl<T> Trait for Wrapper<T>` — still unbounded over T). Any
            // impl whose Self type contains a Param is NOT a single concrete
            // type, so the candidate set for this trait can never be proven
            // closed — matching A2's own existing single-crate safety rule,
            // extended here across the whole workspace.
            let is_blanket = matches!(self_ty.kind(), ty::Param(_)) || self_ty.walk().any(|arg| {
                matches!(arg.kind(), ty::GenericArgKind::Type(t) if matches!(t.kind(), ty::Param(_)))
            });
            for assoc_def_id in tcx.associated_item_def_ids(impl_def_id) {
                let assoc = tcx.associated_item(*assoc_def_id);
                if assoc.is_fn() {
                    emit.trait_impl_fact(
                        &trait_path,
                        &self_type_path,
                        assoc.name().as_str(),
                        &impl_crate,
                        publish_false,
                        is_blanket,
                    );
                }
            }
        }
    }
}

/// Drive analysis and walk every collected mono item.
fn run_analysis<'tcx>(tcx: TyCtxt<'tcx>) {
    let mut emit = Emitter::default();

    emit_trait_impl_facts(tcx, &mut emit);

    let partitions = tcx.collect_and_partition_mono_items(());

    let mut fn_seen: HashSet<String> = HashSet::new();
    // FIX (rust-cg-unwalked-node-no-top-anchor, CRITICAL): tracks which emitted
    // node names actually got a `walk_instance` pass. The mono-item collector
    // only yields *reachable* instances, so a local function nothing in this
    // crate calls (dead code, an uncalled generic, an unused public API method)
    // gets a node from the function-universe pass below but is NEVER in this
    // set — meaning its own outbound calls were never walked. The prior code
    // left such a node with zero out-edges, which `arch-query unreachable`
    // reads as a proven-closed leaf: a silently dropped frontier, not an
    // "unknown" one. After the walk, any node not in `walked` gets one MAY_TOP
    // anchor edge to itself's own frontier instead.
    let mut walked: HashSet<String> = HashSet::new();

    for local_def_id in tcx.hir_body_owners() {
        let def_id = local_def_id.to_def_id();
        if !matches!(
            tcx.def_kind(def_id),
            rustc_hir::def::DefKind::Fn | rustc_hir::def::DefKind::AssocFn
        ) {
            continue;
        }
        let name = def_name(tcx, def_id);
        if fn_seen.insert(name.clone()) {
            let (line_start, line_end) = def_line_range(tcx, def_id);
            emit.function(&name, def_file(tcx, def_id).as_deref(), line_start, line_end, is_exported(tcx, def_id));
        }
    }

    for cgu in partitions.codegen_units {
        for (mi, _data) in cgu.items() {
            if let MonoItem::Fn(instance) = mi {
                let def_id = instance.def_id();
                let name = instance_name(tcx, *instance);
                if fn_seen.insert(name.clone()) {
                    let (line_start, line_end) = def_line_range(tcx, def_id);
                    emit.function(&name, def_file(tcx, def_id).as_deref(), line_start, line_end, is_exported(tcx, def_id));
                }
                if walk_instance(tcx, *instance, &mut emit) {
                    walked.insert(name);
                }
            }
        }
    }

    // Anchor every emitted-but-unwalked node so it reads as an open frontier,
    // not a proven-closed leaf.
    for name in fn_seen.iter() {
        if !walked.contains(name) {
            emit.call(name, None, TOP, None, "<unwalked>", "MAY_TOP");
        }
    }

    if let Err(e) = emit.flush() {
        eprintln!("arch-callgraph-rust: fatal: failed to write NDJSON output: {e}");
        std::process::exit(70);
    }
    eprintln!(
        "arch-callgraph-rust: {} functions, MUST={} MAY_TOP={} trait_impl_facts={} (edges emitted)",
        emit.n_funcs, emit.n_must, emit.n_may_top, emit.n_facts
    );
}

struct CallgraphCallbacks;

impl Callbacks for CallgraphCallbacks {
    fn after_analysis<'tcx>(&mut self, _compiler: &interface::Compiler, tcx: TyCtxt<'tcx>) -> Compilation {
        run_analysis(tcx);
        Compilation::Continue
    }
}

fn main() -> ExitCode {
    let early = EarlyDiagCtxt::new(ErrorOutputType::default());
    rustc_driver::init_rustc_env_logger(&early);

    let args: Vec<String> = std::env::args().collect();
    let is_wrapper = args
        .get(1)
        .map(|a| a.ends_with("rustc") || a.ends_with("rustc.exe"))
        .unwrap_or(false);
    let forwarded: Vec<String> = if is_wrapper { args[1..].to_vec() } else { args.clone() };

    rustc_driver::catch_with_exit_code(|| {
        rustc_driver::run_compiler(&forwarded, &mut CallgraphCallbacks);
    })
}
