# Candidate output contract — guard-division-analysis

For adversarial specification review, not implemented yet.

## CLI

`arch-guard --cmt FILE [--cmt FILE ...] [--format text|json]`.
At least one explicit input. Binary public name arch_guard; root arch-guard only dispatches existing built binary, no build/install side effect.
Default text; help/version0; all usage/input/internal errors2, stderr diagnostic, empty stdout.
All successful classified/empty results0, irrespective semantic statuses; report-only, not policy.

## Closed JSON schema version1

Top-level fields exactly: schema_version, tool, analysis, outcome, inputs, sites, census.

- schema_version: integer1.
- tool: {name:"arch-guard", version:"0.1.0", compiler_version:string, int_bits:31|63}.
- analysis: {mode:"experimental-report-only", fragment:"ocaml-int-acyclic-v1", domain:string, assumptions:string[], limitations:string[]}. Domain name frozen in plan; assumptions expressly trusted same-compiler/target CMT, artifact-only scope, no source freshness certificate. Limitations expressly no whole-program/guaranteed execution/machine-checked proof; unsupported fragment and no interprocedural/heap reasoning.
- outcome: "empty_inventory" iff sites.length0; otherwise "classified".
- inputs: sorted by canonical physical path. Each {path:string,sha256:64lowerhex,module:string,source:string|null,bytes:nonnegative integer}. No timestamps, compiler binder stamps or Git state needed for explicit-content inputs.
- sites: sorted by input path, location.start.offset(null sorts before valid), location.end.offset(null first), primitive, id. Each exact fields:
  {artifact:string,id:positive integer,primitive:string,integer_kind:"int"|"int32"|"int64"|"nativeint",
   operand:{slot:2,category:"integer_literal"|"identifier"|"other"|"missing",representation:string|null},
   location:{file:string|null,start:{line:positive integer|null,column:positive integer|null,offset:nonnegative integer|null},end:{line:positive integer|null,column:positive integer|null,offset:nonnegative integer|null},ghost:boolean},
   status:"NONZERO"|"ZERO"|"MAY_ZERO"|"UNREACHABLE"|"UNSUPPORTED",reasons:string[]}.
- id is one-based inventory preorder ordinal within that artifact; unique per artifact, repeat-run deterministic only, NOT a cross-build finding fingerprint.
- primitive exactly one of %divint,%modint,%int32_div,%int32_mod,%int64_div,%int64_mod,%nativeint_div,%nativeint_mod; integer_kind determined from this mapping.
- representation literal: compiler literal decimal string; identifier: bounded printed long identifier up to256UTF8bytes, otherwise null; other/missing:null. Literal kind metadata remains even if unsupported numerically; no operand evaluation for syntax.
- Source file/location come from full application location. Invalid coordinates null, ghost retained; id still disambiguates duplicates. If start/end filenames differ keep start file and null out end coordinates to avoid falsely projecting a range into one file.
- reasons: sorted unique nonempty strings explaining status. NONZERO/ZERO/MAY_ZERO/UNREACHABLE explain conditional modeled meaning; UNSUPPORTED must name the responsible syntax/arity/integer-family rule. Reasons do not contain absolute timestamps or nondeterministic stamps.
- census exactly {artifacts,total_sites,numeric_covered,nonzero,zero,may_zero,unreachable,unsupported,precision_gain_sites}, allnonnegativeintegers; artifacts=inputs.length,total_sites=sites.length,numeric_covered=nonzero+zero+may_zero+unreachable,total_sites=numeric_covered+unsupported,precision_gain_sites=nonzero+unreachable. Precision gain is classification beyond syntax, not a measured production defect rate.

Text is a human-readable projection of the same result: input count/scope,int width,one line per site with status/primitive/location/reason,then all census counts and report-only/conditional-result warning; empty report states explicit zero inventory. Text/JSON agree semantically, no separate evaluator.

## Whole-invocation fail-closed boundaries

Validate/dedupe/sort inputs before output. Reject absent/unreadable/nonregular/symlink leaf, unsupported CMT annotation, compiler mismatch or changed read, duplicate module/source tuple across distinct artifacts. Explicit no hard process memory/time isolation guarantee; files are trusted local compiler artifacts.
128unique inputs,32MiBperfile,256MiBtotal,100000expression nodes,10000sites,AST recursion512; no truncation. JSON16MiB bound before stdout.
Numeric unsupported does not abort the whole report; malformed input or breached resource limit does.

