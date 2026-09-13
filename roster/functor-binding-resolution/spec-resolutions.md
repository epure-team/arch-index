# Adversarial resolutions — binding provenance

Ten fresh Sol challenges, two stories; all resolved by bounded contract choices
under standing autonomy. User questions0; no formal-verification claim.

| ID | Story | Challenge | Resolution |
|---|---|---|---|
| C-1 | US-1 | Quantified occurrence universe | Exactly every existing functor_applications row whose same-run/input catalogue outcome is collected, including nested head/argument occurrences. Failed catalogue inputs never fabricate ordinals. Complete binding eligibility additionally requires complete catalogue v1. |
| C-2 | US-1 | Declaration traversal closure | Reachability is the pinned5.3 Tast_iterator.default_iterator over Implementation.structure, including module expressions under types/expressions/classes/objects/deferred bodies. Register named module_binding and Texp_letmodule binders, including recursive groups; collect parameter IDs from named module-expression/module-type functor parameters. Only registered module binders with constraint-peeled immediate Tmod_functor RHS become declarations. Untyped attribute/extension payload AST is not traversed as new typed declarations. Never use the narrower graph definition walker. |
| C-3 | US-1 | Exhausted telescope and unresolved head ref | An application-headed row always retains its actual head occurrence ordinal, even when unresolved; only declaration/formal_position are null on refusal. If the next index exceeds the telescope, reason curried_result_not_functor. No body evaluation; synthetic overapplication checks this boundary. |
| C-4 | US-1 | Optional named fields | Named formals permit all four nullability combinations of compiler key/name, each non-null string nonempty. Both-null is an anonymous named formal, not unit. Unit alone requires both null. Application-kind matching uses kind only; position identifies unnamed formals. |
| C-5 | US-1 | Conflicting categories and reason order | Prepass detects duplicate registration of the same Ident.same identity or cross-role binder/parameter collision before any match; input collection_failed, no partial data. Keys are scoped per input. Matching then checks shape (unsupported_path before root), persistent root, parameter membership, missing binder, cycle visited set, and RHS kind. A visited local alias is alias_cycle; failed inner application propagates its reason before outer formal-kind checks. |
| C-6 | US-1 | Failure-row failure and interruption | Separate binding savepoint after successful catalogue persistence/count increment; rollback only new binding entities. Attempt failed-input row outside rolled-back savepoint; if it also fails, leave the input absent and report warning, never fabricate collected status. Any write/rollback uncertainty latches binding eligibility false. Before schema replacement, clear binding marker durably with other central markers. Outer transaction commits data; catalogue finalizes independently; binding marker is the last separate write, never before data commit. Interrupted input/after-data-before-marker cannot yield binding success. No process SIGKILL coverage is claimed unless actually tested; deterministic lifecycle boundaries must be exercised. |
| C-7 | US-2 | Whole validation set | Validate all rows of old catalogue required tables using the same v1 semantic checks plus all three new tables, not only selected/returned rows. Exactly one catalogue run is supported; any foreign-run/orphan binding row or unaccounted input is inconsistent. Old tables outside that catalogue closure (e.g. effects) are not newly validated. Duplicate keys rejected even in hand-crafted unconstrained tables. |
| C-8 | US-2 | Sorting and bytes | Validated unique artifact selection and positive contiguous catalogue ordinals make artifact/ordinal ordering total. Join source/unit solely from same-run catalogue input; order summary first and rows second. Existing renderer semantics, Arch_db.Nul/Int/Text cells and standard escaping are canonical. All fifteen row headers and ten summary headers are frozen in spec-design. Argument remains one JSON-valued string. Construct expected semantic cells independently and explicit byte oracles for all six formats, including null and escaped text; cannot call the producer renderer to compute its own expected output. |
| C-9 | US-2 | Error precedence | Parse command/limit/arity before any DB access -> usage2. Open or begin-snapshot failure -> operational2. In opened snapshot, check complete old/new required-table/column shape and flat discriminator -> UNSUPPORTED_SCHEMA3. Then require exact text v1 for both markers -> NOT_COLLECTED_BINDINGS3 (wrong type/version treated absent). Then full row validation -> INCONSISTENT_BINDINGS3. Actual SQL/connection/commit/rollback failures at any accessed step remain operational2. All error stdout empty; render only after successful snapshot validation/commit. No promise to classify corruption if an earlier required operation fails. |
| C-10 | US-1 | Why not Env/Subst/Shape | matched means the syntactically identified formal at this application, not a concrete module/call target or substituted type. Local Ident.same plus literal telescope order suffices for that narrower claim; cross-unit normalization, environment expansion and body evaluation explicitly decline. Existing wider APIs remain future options, not implicitly exercised. Use no name-only joins or old exposure flag as closure evidence. |

## Additional closed constraints

- An input with one unused direct declaration and zero applications stores counts1/0
  and can earn the marker. No declarations is also valid if the input was collected.
- Declaration location uses existing closed valid-or-null location grammar; ghost
  and same-position declarations never merge keys. Declaration/formal keys are opaque
  nonempty strings, not parsed stamp numbers; no global stability guarantee.
- actual_root_key is nullable/nonempty when present, only permitted for a stripped
  path argument with contains_apply=false. The producer additionally excludes
  Pextra_ty and persistent roots. Persisted display text alone cannot re-establish
  those compiler facts; reader promises structural consistency, not CMT re-execution.
- Declaration/table/formal JSON values are checked before output even for unused
  declarations and limit0. Mismatched run/artifact/producer/module provenance fails.
- The final binding-completion validator must apply the same structural/count/link
  predicates as the reader before granting eligibility. It does not authenticate
  externally rewritten data and does not inspect source freshness.
- SQL names use producer_run_id; scalar integers require SQLite integer storage
  and in-range values. Nullable missing values are actual SQL NULL/JSON null,
  never empty strings or magic0. Closed JSON rejects duplicate/extra keys.
- All nine refusal reasons need real native or explicitly premise-checked synthetic
  tests; no missing tool/fixture may masquerade as a semantic assertion failure.

## Cross-spec audit

Live Entities sections searched across specs/*.md. Existing FunctorCatalogueInput,
FunctorApplicationOccurrence, FunctorExpressionDescriptor and FunctorCatalogueContract
(specs/functor-instance-resolution.md:315-318) stay unchanged. New entities:
FunctorBindingInput, LocalFunctorDeclaration, FunctorFormalSlot, FunctorBindingResult,
FunctorBindingContract. No existing same-name definition conflict found. Existing
module-alias and exception contracts are preserved by no calls/consumer changes.
The guessed specs/schema-versioning.md path was absent; actual schema and catalogue
contracts were read instead. Broad initial grep was truncated; narrow Entities-only
awk scan completed and is the basis of this result, not the truncated output.
