# Spec inputs — root synthesis after fresh Sol/ Terra passes

## Research constraints

Sol source research: body-only invariant arch_index_cmt.ml:877–898,963–993 and
1116–1133; alias arity0/MUST hazard pinned point_free_aliases.ml:138–155,216–232.
Owned member mask/exports at1000–1102. Shared module_target participates in
callbacks1548–1558, add_path_call1564–1595, applications2150–2257, point-free
walk_function_root2769–2797. FR005c immediate-predecessor requirement is at
specs/point-free-aliases.md:297–302; exact chain tests at199–215. Iteration1's
alias refusal is a scoped capability boundary being extended, not a changed
meaning of body identity. Flat same-file target contract at
call_graph_extractor.ml:339–360 remains unchanged.

## Clarifications

Fresh Terra returned8 Q/A items, all resolved from brief/source. Root records
two wording corrections: bare identifier aliases are function-valued, so only
computed/function-producing RHSs are excluded; dropped_node applies only to
storage-rejected targets, not every unresolved head.

| Q | A |
|---|---|
| Which consumers gain? | Qualified applied heads, callback candidates and letops only. |
| What target/arity? | Actual directly named same-CMT function body, existing stored name and syntactic arity. |
| Which provenance? | One bare arrow-typed Pident RHS to body; no chain, persistent/qualified RHS, parameter, computation or module alias. |
| Point-free effects? | Existing outputs unchanged; no shortcut of immediate-predecessor edges, no new point-free resolution. |
| Identity/masks? | Compiler identity, complete owner chain, existing source-order masks and ordinal names. |
| Kinds/refusals? | New targets MAY_ENUMERATED, never MUST; absent identities retain old refusal, storage rejection is dropped_node TOP. |
| Shared helper required? | Implementation detail, but consumer distinction must be representable. |
| User decision needed? | No; conservative one-hop scope matches delegated goal. |

## Draft User Stories

### US-1: Follow qualified calls through known local value aliases (P0)

As an index consumer I want an invocation of Owned.alias to reach its concrete
body so I can follow that call chain. P0: explicit aliases occur in both corpus
slices. Scope excludes module-alias/functor/value-flow closure and unqualified
alias calls. Independent test: native fixture queries exact targets and metadata.

1. Given Owned.alias = base and base x=x in an owned literal structure, when
   run invokes Owned.alias 1, then its exact body target is MAY_ENUMERATED, same
   file, no TOP fields or edge_form.
2. Given base shadowed later and alias bound to the earlier base, when invoked,
   then target is the earlier body's actual #N name, never later homonym.
3. Given parameter, multi-hop alias, computed RHS or opaque owner, when invoked,
   then its previous TOP refusal remains despite a same-named decoy.
4. Given a 3-ary body's one-hop alias with omitted labels or only2 arguments,
   when invoked, then partial metadata reflects supplied expressions and real
   body arity; no invented return residual. Overapplication preserves exact TOP.
5. Given callback/letop/dead/conditional uses and a point-free qualified alias,
   when indexed, then invocation sites resolve with existing metadata and every
   point-free output stays unchanged. A rejected body yields dropped_node TOP;
   missing flat same-file symbol cannot use a foreign homonym.

### US-2: Compare the next candidate against the delivered state (P0)

As maintainer I want an exact retained-state corpus comparison so previous gains
cannot masquerade as a new iteration. P0: sequential keep requires incremental
measurement. Scope excludes a general benchmark CLI. Independent test: neutral
replay plus altered-input/multiset controls exercise verification without product
changes.

1. Given merged producer and unchanged410 CMTs, when preparing the baseline,
   then fresh DB exactly matches45052 rows/SHA90e76d6... and4772/11615 relations;
   repeat production and self comparison are neutral.
2. Given a new supported change, when verified, then exact compiler alias-binder
   to-body source witnesses justify each changed endpoint/return row; compare
   multisets and separate Irmin/protocol relation gains with zero losses.
3. Given changed inputs, wrong predecessor, missing/duplicate/foreign run inputs,
   wrong witness, duplicate deletion, new MUST, changed point-free facts or
   unrelated TOP loss, when verified, then assertion/refusal or setup error is
   reported, never a keep. Existing task1 evidence remains unchanged.
4. Given neutral or unreviewed candidate, when reporting, then no retained gain
   is claimed; keep needs positive incremental gain, native/full gates, roster
   review/QA and exact-head CI/rebase merge before attempt3.
