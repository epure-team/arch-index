# QA Scope — rust-soundcg-whole-program

**Date:** 2026-09-03

## Quality Gates (exact commands)

```bash
# From within callgraph-rust/
RUSTC_BOOTSTRAP=1 cargo build --release

# End-to-end selftest (extended with multi-crate fixtures per plan step 14)
./selftest-callgraph-rust.sh
```

Pinned toolchain `nightly-2026-06-20` (`rustc-dev`, `llvm-tools`, `rust-src`) — confirmed already
installed locally; QA should re-confirm with `rustup toolchain list` before running gates, since
toolchain drift was flagged as a real risk during planning.

Also run the full repo's existing quality gates (`dune build`, `dune test --force`) to confirm the
new producer's `arch_load.ml` change (if any) doesn't regress the OCaml/Go paths.

## Behaviors to validate (the 9 runnable checks from the spec + plan)

1. **CHECK-1**: 2-crate fixture, `dyn Trait` call site + direct call site — assert `MAY_TOP` and
   `MUST` respectively.
2. **CHECK-2**: workspace fixture with one crate (inside the requested build target) that fails to
   compile — assert non-zero exit, no complete-graph claim.
3. **CHECK-3**: named `extern "C"` call — assert the emitted edge carries the symbol name, not the
   anonymous sentinel.
4. **CHECK-4** (the hard requirement): 3-4 crate fixture (trait crate, sibling-impl crate,
   downstream-impl crate not depended on by the caller, caller crate depending only on the trait
   crate) — assert `MAY_ENUMERATED` includes both the sibling's and the downstream's candidate.
   Independently re-verify this by querying the resulting DB directly (don't just trust the
   fixture's own assertions), the same way this session's earlier #41 QA pass independently
   re-verified behaviors with fresh SQL queries rather than re-running the existing test suite.
5. **CHECK-5**: blanket impl in a crate *other than* the dispatch-site crate — assert `MAY_TOP`.
6. **CHECK-6**: trait-defining crate's `Cargo.toml` omits `publish = false` — assert `MAY_TOP`
   regardless of how closed the impl set looks. Also test the `[workspace.package] publish =
   false` inheritance case specifically (flagged during planning as an easy-to-miss variant).
7. **CHECK-7**: simulate a missing/excluded crate's facts in the merge input — assert every trait
   touched by that crate falls back to `MAY_TOP`.
8. **CHECK-8** (scope guard): `git diff` over the shipped PR must not touch
   `lib/arch_index/call_graph_extractor.ml` or `tezt/tests/lsp_languages.ml`.
9. **CHECK-9** (new, cross-producer naming): a function visible via both the new MIR producer and
   the existing LSP path — assert no silent misattribution between the two producers' rows.

## Accepted-residual documentation check (not a gate failure, but must be verified present)

Per the human's explicit planning decision, confirm the producer's README/docs plainly state:
- `MAY_ENUMERATED` precision depends on a full workspace rebuild; incremental re-indexing
  conservatively degrades to `MAY_TOP` via the missing-facts fallback.
- The `publish = false` gate is a weak, gameable proxy, not a strong guarantee.
- The producer analyzes one resolved feature/cfg graph per invocation; feature-gated impls behind
  a disabled feature are invisible.

Absence of this documentation is a legitimate NO-GO — the plan requires these residuals be stated
plainly, not silently accepted.

## Out of scope for this QA pass

- Non-`dyn` generic trait-bound narrowing, sealed-trait detection, dependency-graph-aware merge
  precision, feature-powerset analysis — all explicitly deferred, do not test for their absence
  as if it were a defect.
- CI wiring itself — only the existence of a properly-owned follow-up ticket (step 17) is in scope
  to verify, not actual CI YAML changes.
- The 4 previously-undocumented CRITICAL findings' exact original content — `/roster-review`'s
  fresh pass is what substitutes for them; QA verifies the review happened and was GO, not the
  archaeology itself.

## Verdict criteria

GO requires: all repo-wide gates pass, all 9 checks pass (independently re-verified for CHECK-4 at
minimum, per the #41 precedent of not just trusting the test suite's own assertions), the scope
guard is clean, and the three accepted-residual disclosures are actually present in shipped docs.
A test suite that passes only single-crate cases, or a merge pass with no visible completeness-
manifest mechanism, is NOT sufficient evidence for GO — per the plan's own risk table, the
multi-crate fixture axis and the missing-facts fallback are the parts most likely to hide a
regression.
