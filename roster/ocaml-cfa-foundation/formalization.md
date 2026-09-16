# Stage-2 CFA foundation — formalization draft

2026-09-15. Formalized from `spec-input.md`, `spec-challenges.md`, and
`cross-spec.md`. This is a requirements draft, not a validated specification.

Trace labels use `US1-Sn` / `US2-Sn` for story scenarios, `Cn` for resolved
challenges, and `CHECK1-domain`, `CHECK2-authentic-CMT`, or
`CHECK3-pinned-Tezos` for planned verification domains.

## US1 — trustworthy finite value propagation

- **FR-001 MUST** model each cell value as a pair of a finite target-identity set
  and a finite unknown-reason-kind set. `[US1-S1–S4, C1, CHECK1-domain]`
- **FR-002 MUST** order cell values componentwise by subset, compare both
  semantic sets, and join by componentwise union. `[US1-S2/S3, C1/C16/C17,
  CHECK1-domain]`
- **FR-003 MUST** represent bottom only as `(empty, empty)` and **MUST NOT**
  equate it with an unknown-only value. `[US1-S4, C1/C2, EC1, CHECK1-domain]`
- **FR-004 MUST** support target seeds, unknown-reason seeds, and inclusion/copy
  constraints; branch joins MUST be multiple copies into a result cell.
  `[US1-S1–S3, C3, CHECK1-domain]`
- **FR-005 MUST** propagate target and unknown components independently; neither
  component may absorb the other. `[US1-S2, C1/C17, CHECK1-domain]`
- **FR-006 MUST** compute the least fixed point, terminate on finite copy cycles,
  reschedule a visited cycle when a new seed reaches it, and return results
  invariant under constraint ordering and duplication. `[US1-S1/S3, C3/C15/C16,
  EC3, CHECK1-domain]`
- **FR-007 MUST** match an independent repeated-scan finite-set saturation oracle
  for both components. `[C3/C14/C16, CHECK1-domain]`
- **FR-008 MUST NOT** include diagnostic witnesses in semantic equality, joins,
  scheduling, or closure; witnesses sharing one reason kind MUST join to one
  semantic reason. `[C1/C18, EC2, CHECK1-domain]`
- **FR-009 MUST NOT** claim call, return, argument, environment, capture,
  recursive value transfer, or partial-closure transfer. This exclusion **MUST
  NOT** exclude the required pure-solver copy cycles. `[C3/C15,
  CHECK1-domain]`
- **FR-010 MUST NOT** let a consumer interpret an invoked bottom cell as a closed
  impossible callable. `[US1-S4, C2, CHECK1-domain/CHECK2-authentic-CMT]`
- **FR-011 MUST** make CHECK1 exit 0 on pass, 1 only for an explicit assertion
  failure, and at least 2 for an environment, load, or build failure. `[C14,
  CHECK1-domain]`

### US1 acceptance criteria

- **AC-1:** Given `a -> b -> c` and target `f` seeded at `a`, CHECK1 observes
  `c = ({f}, empty)`.
- **AC-2:** Given target `f` and opaque reason `r` copied into one result, CHECK1
  observes `({f}, {r})`.
- **AC-3:** A finite seeded cycle terminates and every ordering/duplication agrees
  with the independent oracle, including a seed arriving after the cycle was
  first visited.
- **AC-4:** An unseeded cycle returns bottom in CHECK1, while CHECK2 shows that an
  invocation of that result remains an explicit unknown occurrence.
- **AC-5:** Unknown-only remains distinct from bottom, and multiple witnesses for
  one reason kind produce one semantic reason.
- **AC-6:** CHECK1 implements the exit-status contract in FR-011.

## US2 — authentic CMT targets without lost facts

- **FR-012 MUST** analyze an entire CMT as one batch and finalize only after all
  actual literal names have been observed. `[US2-S1/S2/S5, C8,
  CHECK2-authentic-CMT]`
- **FR-013 MUST** use resolved compiler `Ident` identity for binders and physical
  expression identity for literals and applications within one OCaml 5.3 CMT
  session; positions are display/provenance only. `[C4/C6/C10/C19,
  CHECK2-authentic-CMT]`
- **FR-014 MUST NOT** claim identity equality across sessions, compiler versions,
  reparses, or independently compiled variants. `[C6/C19,
  CHECK2-authentic-CMT/CHECK3-pinned-Tezos]`
- **FR-015 MUST** newly support nonrecursive single-variable root bindings and
  same-callable nonrecursive single-variable lets, including branch-valued
  top-level bindings. `[US2-S1, C4, CHECK2-authentic-CMT]`
- **FR-016 MUST NOT** add substitution or value transfer for recursive groups,
  destructured pattern bindings, another callable's captures,
  nested-module/include/open syntax, call results, returned functions, arguments,
  or partial closures. `[US2-S3, C4/C5/C9, EC14, CHECK2-authentic-CMT]`
- **FR-017 MUST** preserve established direct/static and owned-module handling;
  an already resolved static occurrence wins and MUST NOT receive a duplicate CFA
  replacement. `[C4/C9/C12, CHECK2-authentic-CMT]`
- **FR-018 MUST** resolve aliases by binder identity so later shadowing cannot
  retarget an earlier alias. `[C4, EC4, CHECK2-authentic-CMT]`
- **FR-019 MUST** conservatively join every normally returning RHS value of
  `if`, `match`, and result-valued sequence expressions without assuming branch
  feasibility or match exhaustiveness. `[US2-S2/S3, C5,
  CHECK2-authentic-CMT]`
- **FR-020 MUST** include normally returning exception-case RHS values while
  preserving error channels, and **MUST NOT** invent a returned function value
  for an unhandled exception. `[C5, EC6, CHECK2-authentic-CMT]`
- **FR-021 MUST** preserve calls, effects, and channels from guards, scrutinees,
  and sequence prefixes while propagating only a sequence's result value.
  `[C5, EC13, CHECK2-authentic-CMT]`
- **FR-022 MUST** seed pattern-bound values as unknown for new transfer while
  retaining independently known constant RHS candidates. `[C5, EC7,
  CHECK2-authentic-CMT]`
- **FR-023 MUST** allow visible unit-level binders in nested callable bodies, but
  a binder owned by another callable MUST remain an unsupported capture
  contribution. `[US2-S3, C9, EC8, CHECK2-authentic-CMT]`
- **FR-024 MUST** reconcile a physical literal only through the authoritative
  collector notification for its actual assigned name and owner; a missing,
  rejected, or wrong-owner notification MUST NOT create a bounded target.
  `[US2-S2/S5, C8, CHECK2-authentic-CMT]`
- **FR-025 MUST** preserve distinct actual literal identities despite equal or
  ghost positions and MUST preserve collector-assigned collision ordinals.
  `[US2-S2, C6/C8, EC5, CHECK2-authentic-CMT]`
- **FR-026 MUST** refine only the unresolved supported head contribution. In main,
  every CFA candidate MUST be classified `MAY_ENUMERATED`, never `MUST`; flat
  remains kind-less and **MUST NOT** claim that classification contract.
  `[US2-S1, C7/C12, CHECK2-authentic-CMT]`
- **FR-027 MUST** deduplicate candidates only by actual target identity within one
  occurrence; separate occurrences, residuals, alias rows, and escape facts MUST
  remain separate. `[US2-S4, C10/C12/C18, CHECK2-authentic-CMT]`
- **FR-028 MUST** preserve immediate-predecessor `value_alias` provenance and its
  caller-query exclusion independently of transitive application refinement.
  `[US2-S1, C20, CHECK2-authentic-CMT]`
- **FR-029 MUST** copy each occurrence's applicable caller, call-site, original
  partiality, conditional, deadness, scope, channel, and independent residual
  facts to expansion outputs; distinct raw occurrences MUST NOT deduplicate.
  Bounded rows MUST keep `top_reason` and `top_anchor` NULL. TOP-only anchors stay
  only on applicable unknown rows. Deadness MUST NOT erase an occurrence.
  `[US2-S4, C2/C10, EC10, CHECK2-authentic-CMT]`
- **FR-030 MUST** preserve two physical applications on one source line as
  distinct occurrences. `[US2-S4, C10, EC10, CHECK2-authentic-CMT]`
- **FR-031 MUST** take authoritative known candidate arity from the existing
  `fn_arity` contract: recursively count `Texp_function` parameters,
  `Tfunction_cases` contributes one, a tuple parameter counts one, two curried
  parameters count two, and each labeled formal counts one. Candidate arity at
  most zero MUST be treated as unknown. `[C11, CHECK2-authentic-CMT]`
- **FR-032 MUST** count supplied arguments for new CFA handling as the OCaml 5.3
  application argument slots whose expression option is `Some`. It MUST preserve
  original partiality and additionally mark a candidate partial when supplied
  count is below its known arity. Any omitted labeled slot or unknown arity MUST
  retain an explicit unknown contribution and MUST NOT guess saturation. The
  existing static path MUST remain unchanged. `[C11, EC9,
  CHECK2-authentic-CMT]`
- **FR-033 MUST** add or retain exactly one returned-function residual for an
  original known overapplication occurrence, not one per candidate. `[US2-S4,
  C11, CHECK2-authentic-CMT]`
- **FR-034 MUST** preserve an opaque-head frontier and independent residual
  causes separately even if persisted TOP reason text coincides. `[US2-S3/S4,
  C11/C18, EC11, CHECK2-authentic-CMT]`
- **FR-035 MUST** translate an invoked unresolved bottom head in main to explicit
  `callback_param` unknown and MUST NOT emit zero rows. `[C2/C13,
  CHECK2-authentic-CMT]`
- **FR-036 MUST** map unsupported capture, unsupported pattern value, opaque
  value, and bottom to `callback_param`; known dropped/unobserved bodies to
  `dropped_node`; and preserve established `module_param` and `ambiguous_unit`
  causes. `[US2-S3/S5, C13, CHECK2-authentic-CMT]`
- **FR-037 MUST** retain flat's bare caller namespace and kind-less schema. For a
  newly generated flat unknown it MUST emit `callee_name='*TOP*'`,
  `callee_file=None`, and retain the original `caller_name`, caller file,
  call-site, and `edge_form=NULL`. It MUST NOT globally rename existing non-CFA
  unknown displays. `[C2/C7/C13, CHECK2-authentic-CMT]`
- **FR-038 MUST** require a unique faithful same-file mapping before flat emits a
  newly bounded candidate. A missing, ambiguous, or unrepresentable mapping MUST
  emit the FR-037 unknown tuple, MUST NOT use `name_to_file` or any homonym to
  resolve it, and MUST NOT set a callee file. `[US2-S5, C7, EC5/EC12,
  CHECK2-authentic-CMT]`
- **FR-039 MUST** suppress newly bounded flat CFA facts at an ambiguous caller
  namespace and emit the FR-037 unknown at that existing caller. `[C7, EC12,
  CHECK2-authentic-CMT]`
- **FR-040 MUST** have main resolve actual ordinal-qualified target identities. A
  missing main caller MUST retain existing extraction failure/drop behavior and
  MUST NOT fabricate a caller row. `[C7/C13, CHECK2-authentic-CMT]`
- **FR-041 MUST NOT** add a new kind token, `edge_form` token, proof-chain schema,
  fabricated callee file, or non-NULL CFA `edge_form`. Flat MUST NOT be advertised
  as having main's proof/query contract. `[C7/C13/C20, cross-spec,
  CHECK2-authentic-CMT]`
- **FR-042 MUST** make CHECK2 exercise real compiled main and flat fixtures,
  including bottom, collisions, metadata, candidate arity, ambiguous identities,
  and consumer queries; its exit-status contract MUST match CHECK1. `[C14,
  CHECK2-authentic-CMT]`
- **FR-043 MUST** make CHECK3 separately report exact gains and losses against the
  frozen pinned Tezos corpus plus resource observations. An unavailable corpus
  MUST return at least 2 and MUST NOT be reported green or fail native CI.
  `[C14, CHECK3-pinned-Tezos]`
- **FR-044 MUST NOT** alter the frozen stage-1 baseline or claim stage-3
  application/environment semantics or stage-4 variant reuse. `[C14/C15/C19,
  CHECK3-pinned-Tezos]`

### US2 acceptance criteria

- **AC-7:** An authentic CMT containing `f`, `a = f`, `b = a`, and `run x = b x`
  emits main target `f` as `MAY_ENUMERATED`, preserves immediate-predecessor alias
  rows, and does not duplicate resolved static facts.
- **AC-8:** Selection between distinct collector-promoted literals preserves both
  actual identities despite equal/ghost positions and preserves collision
  ordinals.
- **AC-9:** Selection between visible `f` and an opaque parameter emits `f` plus
  unknown; combining a visible top-level target with an unsupported capture does
  the same.
- **AC-10:** Match and sequence fixtures preserve guard/scrutinee/prefix effects
  and channels; normal exception-case RHS values join; unhandled exceptions do
  not fabricate targets; pattern-bound values remain unknown beside independent
  known RHS candidates.
- **AC-11:** Shadowing proves main resolves the earlier binder identity, while a
  recursive alias remains unsupported.
- **AC-12:** Two same-line applications with different conditional, dead, scope,
  or channel facts remain distinct. Bounded rows preserve applicable facts but
  have NULL TOP reason/anchor; unknown anchors and independent residuals survive
  only where applicable.
- **AC-13:** Known candidate arities from tuple, curried, labeled, and
  `Tfunction_cases` fixtures obey FR-031. Under one supplied expression,
  candidates of arity one and two receive conservative per-candidate partiality;
  omitted labeled slots, arity at most zero, and unknown arity retain explicit
  unknown without changing the static path.
- **AC-14:** A known overapplication with multiple candidates emits exactly one
  returned-function residual for the original occurrence alongside any
  independent opaque frontier.
- **AC-15:** Rejected, unobserved, missing-notification, and wrong-owner literal
  bodies never become bounded and map to the prescribed unknown cause.
- **AC-16:** Flat emits a candidate only for a unique faithful same-file mapping.
  Ambiguous or unrepresentable caller/target identity emits the exact FR-037
  tuple, never uses a `name_to_file` homonym, and creates no newly bounded fact;
  main emits the actual ordinal-qualified identity.
- **AC-17:** Invoked bottom remains an occurrence: main emits `callback_param`,
  while flat emits the FR-037 kind-less unknown tuple without claiming main's
  proof contract.
- **AC-18:** CHECK2 observes both producer outputs and consumer verdicts and
  implements the stated exit statuses.
- **AC-19:** CHECK3 reports frozen-corpus gains and losses separately; unavailable
  corpus returns at least 2.

## Coherence and scope finding

The resolved requirements are internally coherent. Candidate-specific
partiality is conservative: preserved original partiality may mark more rows
partial, but no requirement promotes any candidate to `MUST`; independent
residuals remain distinct. Flat's kind-less contract is explicitly weaker than
main's query-proof contract and fails open rather than binding a homonym.

No material contradiction remains in the supplied resolutions. This draft does
not expand into stage 3.
