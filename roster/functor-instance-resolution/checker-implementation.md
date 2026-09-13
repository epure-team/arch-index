# Checker implementation evidence

`scripts/check-functor-catalogue.js` is a direct Node assertion runner. It
returns 0 only after its named group passes, 1 for an assertion failure, and 2
for missing tools/probes, compilation, SQLite, or operational setup failures.
It owns its expected CMT census and crafted SQLite data; it neither imports the
collector nor query implementation.

Implemented groups:

- `inventory`: independent native census (`18 apply`, `1 apply_unit`), required
  child-context premises, direct SQL occurrence validation, closed descriptor/
  location/diagnostic grammar, forward references, and Papply/ghost/invalid/
  same-position artifact probes that are each re-indexed and inspected.
- `lifecycle`: exact-string selection, real storage rollback/lifecycle
  finalization, and native producer checks for `unsupported_annotation` and
  `missing_source`. It does not claim the four remaining outcomes, reindex,
  copy/symlink, or interruption coverage from these checks.
- `query`: a hand-authored complete v1 SQLite database, success rendering across
  all six existing formats, strict limits before DB open, byte-unchanged reads,
  marker/schema precedence, and 19 one-fault-at-a-time consistency corruptions
  (run/header/count/provenance/ordinal/JSON/reference/orphan cases). The
  remaining AC-11 null/type and missing-column variants are still being added;
  this is not yet a claim of complete query coverage.
- `compatibility`: compiles an owned two-module fixture, indexes it, and compares
  canonical semantic tables with the versioned rich baseline after excluding
  run metadata. The constant-false branch is checked only for its actual empty
  stored condition population.

Observed during implementation (with the root-approved rebuilt binaries):

| Command | Result |
|---|---|
| `node scripts/check-functor-catalogue.js inventory` | pass |
| `node scripts/check-functor-catalogue.js query` | initial red: JSON limit 0 omitted second `[]`; current partial matrix passes after product fix |
| `node scripts/check-functor-catalogue.js compatibility` | pass |
| `node scripts/check-functor-catalogue.js lifecycle` | pass for its current direct native premises; not full AC-5/6/7/10 coverage |

No Dune command was run by this checker implementation task; root owns serial
build and suite gates. The shipped checker does not use the temporary baseline
directories or preserved old binaries.
