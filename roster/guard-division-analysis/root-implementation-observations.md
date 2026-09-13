# Root observations during implementation (not roster review verdict)

These are in-flight checks before implementation is declared complete. Independent roster review/QA remain required.

1. Scope: initial helper added to tezt/lib/arch_tezt.ml was outside the manifest. Implementer removed only its delta and defined the helper in the new test module. Root git diff confirmed no remaining arch_tezt.ml change.
2. Existing effect exclusion: linked effect.ml shows %perform/%resume/%runstack/%reperform as primitives. Root clarified C-11/FR-027 and reason vocabulary before semantic classification; effect semantics are still excluded.
3. Initial inventory scaffold classifies all native sites MAY_ZERO, even where final eligibility/ancestry exclusions are required. This is not the completed inventory contract; implementer instructed to test and fence exclusions before enabling NONZERO or UNREACHABLE. Pending final implementation and independent checks.
4. Initial operand metadata handles only Const_int and prints Path.name. Final contract requires all integer literal families and printed Longident. Pending final implementation and independent checks.
5. Initial domain restrict_ne_zero changes Const2 into Nonzero: sound as an overapproximation but not a reductive intersection; loses known constant precision and violates the selected restriction operation/domain-law requirement. Root now inspected Const n -> Const n fix; ocaml-tdd.md records actual restriction RED and scoped GREEN. Later independent checker/review still required.
6. Probe malformed widths/out-of-range constants must be execution errors, not host-dependent shift behavior or spurious domain facts. Pending validation/tests.

Do not mark an observation resolved from narration alone; inspect the actual diff and terminal test evidence. No semantic precision gain or completed implementation claimed here.
