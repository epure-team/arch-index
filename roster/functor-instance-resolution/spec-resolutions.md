# Challenge resolutions — functor-instance-resolution

All fourteen challenges resolved by the operator within the bounded intake.
No direction change, no human-only policy decision; zero user questions asked.
This file supersedes ambiguous wording in spec-design-input, retaining its two
stories and scenarios. Exact public contract below is input to formalization.

| Challenge | Resolution |
|---|---|
| C-1 | Traverse every Typedtree child reachable from the accepted `Implementation structure` through the OCaml5.3 default Tast_iterator, including expression, class/object, unpack, module-type-of and local-module children. No exclusion by execution/deferred/opaque context. Only immediate Tmod_apply/Tmod_apply_unit nodes are occurrences. Traversal never expands external artifacts, Env, Types signatures or Shape. |
| C-2 | Assign parent application ordinal before traversing either operand; visit functor before argument. Referenced applications in descriptors have strictly greater ordinals in the same input and must exist. Application-only ordinals are contiguous1..n per input. Applications inside shallow descriptor bodies are separately inventoried, not embedded in the descriptor. |
| C-3 | Selection is the existing producer's discovered `.cmt` path list, sorted and deduplicated by exact path string for catalogue accounting. Artifact key is that discovered path string, not realpath/inode/digest. Distinct symlink/copy paths remain distinct input selections, never advertised as unique physical programs. A duplicate source/module insertion rejected by the existing producer makes that input dropped_module, not collected via a previously inserted module. No changes to existing producer discovery or symlink policy. |
| C-4 | Persist producer-run linkage in SQL but exclude surrogate ids, run ids, timestamps and compiler stamps from the public report. Stable output applies only to identical selected path strings and artifacts under the same source mapping. No cross-build, moved-worktree or freshness guarantee. |
| C-5 | Selected is fixed before per-CMT processing. Outcome precedence: read exception/no CMT info -> unreadable; non-Implementation -> unsupported_annotation; unresolved source -> missing_source; own module insertion rejected -> dropped_module; collector/insertion/provenance error -> collection_failed; otherwise collected. Accumulate one input's occurrences completely before publishing; failure leaves zero application rows for that input. Per-input expected counts and selected count are persisted for consistency checks. |
| C-6 | Diagnostics attach to an occurrence as a sorted unique list; several codes can coexist. Closed derivation is defined below. Neither diagnostics nor an empty list express target resolution. |
| C-7 | On the same accepted fixture inputs, preserve functions identity/name/exposure/spans and calls' caller/callee identity, display/site, kind, TOP reason/anchor, conditional/dead semantics, scope/edge-form data, dependencies, exception/error facts, existing markers and query verdicts. Preserve three-list process_cmt return and existing head taxonomy. Additive schema/version/new catalogue provenance/rows and extra catalogue diagnostics are intentional differences. Catalogue failures cannot discard graph facts previously produced or promote edges; their new rejection accounting may report an additional problem. New source files can legitimately change self-index totals; calibrate with attribution, never weaken semantic tests. |
| C-8 | Clear catalogue eligibility marker via the central lifecycle before rebuilding. Persist header/input outcomes/application rows transactionally, with no partial application set for a failed input. Commit data before a separate final marker write. Earn v1 only with nonempty selection, all collected, required provenance present and exact counts stored. Interruption before marker leaves no eligible catalogue even if SQL rows survive; interruption before schema drop may leave old rows, but never an old authoritative marker. Reindex drops all new producer tables. |
| C-9 | Validate the whole catalogue before output or limit: required tables/columns, exactv1 marker, one run header linked to an existing producer, positive selected count, exact input count, every input collected with valid nonnull module/source/unit provenance, per-input expected row counts, contiguous positive ordinals and unique artifact keys, valid closed JSON descriptor/location/diagnostic schemas, forward same-input references, and no orphan rows. Marker is collection evidence, not tamper resistance; no assertion about malicious coordinated rewriting or source freshness. |
| C-10 | Usage/limit validation first => exit2. Open/operational DB failure => existing exit2. Then fixed exit3 precedence: `UNSUPPORTED_SCHEMA` (flat/missing schema), `NOT_COLLECTED` (absent/unrecognized marker), `INCONSISTENT_CATALOGUE` (header/count/outcome/provenance/descriptor/ref failure). Markerless partial runs use NOT_COLLECTED, with available failed-input outcome counts in diagnostic. No stdout before validation finishes. |
| C-11 | Freeze exact summary/application headers and JSON-valued text grammars below. Validate all data before computing total/returned; total is all validated application rows, not a filtered count. Existing renderer owns format escaping/null encoding. JSON emits exactly summary-array then application-array separated by newline; zero rows still emits `[]`. |
| C-12 | Adopt local5.3 Typedtree occurrence structure, not entire typed bodies. Shallow structure/unpack/functor descriptors deliberately omit declarations/expressions/types; only application topology and immediate operand category are promised. This is sufficient for syntax coverage, not parameter substitution. Future resolution must recover additional binder/body facts from artifacts; catalogue is not asserted sufficient alone. Installed interfaces were read, so no5.5 field is assumed. |
| C-13 | Papply is a static access path, not an observed module-expression evaluation. A Tmod_ident containing Papply remains a path descriptor with contains_apply=true and rendered compiler/source strings; it creates no extra occurrence. Distinct syntactic occurrences retain ordinal identities even for equal paths. Explicitly disclose omitted structural Path reduction and no alias/target identity guarantee. |
| C-14 | Shape definition reduction serves a different question than syntactic occurrence inventory. No Shape/UID-derived target, exactness flag, approximation or closure claim appears. Scope/limitations in every report state no target resolution and no runtime/closed-world interpretation. This deliberately bounded slice does not claim to complete defunctorization or enable substitution without further work. |

## Closed observable contract

Summary columns, in order:
`contract, selected_inputs, collected_inputs, total, returned, truncated, scope, limitations`.
contract=`v1`; counts are nonnegative integers; selected_inputs>0;
truncated is integer0or1 and equals returned<total. scope=`selected_cmt_syntax_only`.
limitations is the fixed text:
`not_runtime_instances;not_closed_world;no_target_resolution;no_source_freshness_check;paths_are_artifact_selections`.

Application columns, in order:
`artifact, source, compiler_unit, ordinal, application_kind, location, head, argument, diagnostics`.
application_kind is `apply` or `apply_unit`. The last five fields except
application_kind are: location/head/argument/diagnostics JSON-valued text,
while ordinal is an integer. No extra public fields in this version.

Location JSON has exactly
`{file,start_line,start_col,end_line,end_col,ghost}`.
Valid locations require nonempty matching start/end filenames, lines>=1,
columns>=0 and lexicographically ordered (line,column) range. Columns are compiler
byte columns, not Unicode display columns. Ghost alone does not make a location
invalid. Invalid locations set file and all coordinates to null, retain ghost,
and add unusable_location. Source path remains independently recorded.

Descriptor JSON has exactly one of these closed tagged forms:

- `{kind:"path",compiler:string,source:string,contains_apply:boolean}`;
- `{kind:"structure"}`;
- `{kind:"functor",parameter:"unit"|"named",name:string|null}` (unit => name null);
- `{kind:"unpack"}`;
- `{kind:"constraint",expression:descriptor}`;
- `{kind:"application",ordinal:positive_integer}`;
- `{kind:"unit"}` only as the argument of apply_unit.

No application-level nested body is serialized. Application descriptor references
may be under constraints. Strip constraints for the following code derivation:

- `opaque_functor_head` iff head kind is neither path nor application;
- `anonymous_argument` iff argument kind is structure;
- `unpacked_expression` iff head or argument kind is unpack;
- `unusable_location` iff location fails the rules above.

Diagnostics JSON is an ascending lexicographic unique array of applicable codes.
Named paths remain display provenance even when diagnostics is empty.

Limit is an optional strict ASCII decimal fitting nonnegative OCaml int, default50.
Overflow (including digits beyond the platform range) and any extra argument are
exit2. Limit0 produces summary and empty application table. Existing table renderers
own text escaping and headers; in JSON each descriptor is a JSON string cell (not
an unannounced nested JSON object). Two tables are rendered only after all reads and
validations succeed, preserving empty stdout for refusals.

## Edge-case resolution index

EC-1 => C-1/C-2; EC-2 => C-3; EC-3 => C-5/C-8; EC-4 => location contract;
EC-5 => C-13; EC-6 => C-9/C-10; EC-7 => C-8; EC-8 => C-10;
EC-9 => limit contract; EC-10 => summary/output contract.

The original story scenarios and runnable groups remain valid. Tests must add
structural missing-data, count mismatch, bad/forward reference, malformed descriptor,
same-position/ghost location and real typedtree Papply-path cases with premise
checks. Do not label an unexercised case passed if a compiler fixture cannot produce it;
use an explicit native artifact probe or report the gap before validation.
