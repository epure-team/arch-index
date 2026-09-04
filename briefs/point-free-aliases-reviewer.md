# Reviewer brief — point-free-aliases

**Status: VALIDATED**

## Audit these first, in this order
1. **Does any `edge_form='value_alias'` row carry `kind='MUST'`?** This is the designed
   trap: `Head_qualified` defaults to `MUST` when not demoted, and an alias is never
   demoted. FR-005b. One SQL query settles it.
2. **Is `partial` set on any non-application pending call?** Setting it would produce the
   right kind by putting a false claim in the data. Read the emission site, not the test.
3. **Is the `fan-in`/`god-modules` filter gated on column presence?** The flat schema has
   no `edge_form`; an unconditional predicate errors there. Test against a flat database.
4. **Was the golden re-measured or adjusted?** It is checked only by CI. Demand the 2×2
   attribution (A=B and C=D), not a recomputed number.
5. **Does `Arch_exn` actually see the edge?** It is a *separate* loader from `Arch_graph`;
   passing tests in the producer and in `arch-query` prove nothing about it.

## Expected behaviours
- Local alias: one `calls` row, `kind='MAY_ENUMERATED'`, `edge_form='value_alias'`,
  `call_site` = the binding's own location.
- `may-fail` on the alias node no longer answers `BOUNDED: {}`.
- `fan-in` for the target is unchanged by the presence of the alias.
- Legacy database (no `edge_form` column): every command still answers, reporting no
  aliases rather than failing.

## Known residuals — do not report as findings
- `reaches` does not traverse alias edges (a consequence of `MAY_ENUMERATED`, tracked).
- ~~Multi-hop chains do not resolve (resolution is a single pass, not a fixpoint).~~
  **No longer a residual — chains ship and resolve** (FR-005c). No fixpoint was needed:
  each binder emits its own edge to its immediate predecessor, so an n-hop chain is n
  ordinary edges. A chain that fails to resolve IS a finding.
- Arrow-type detection may under-detect on `.cmt`-restored aliased arrow types; it fails
  to today's zero-edge behaviour, the safe direction.
- Pre-existing `MAY_TOP`/`MAY_ENUMERATED` inflation of `fan-in` — real, but out of scope.
