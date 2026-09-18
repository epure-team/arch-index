# Research — change-review impact provenance

## Existing source of truth

`Arch_diff.changed_lines` parses the selected Git range once and returns a
path-keyed ordered map.  Each value is either `Lines` (a hash table of the
new-file line numbers) or `Whole` (`--files`).  A deletion-only diff naturally
has an empty `Lines` table: its path still exists in the map, while it has no
new-file line to name.

`arch-impact` already consumes precisely that map for the line-to-function
mapping.  Re-parsing Git or reconstructing line ranges from the briefing would
create an avoidable disagreement between the declared and analysed scopes.

## Implementation choice

The JSON-only `impact_input` object is built immediately after the map is
loaded.  `Arch_diff.SM.bindings` makes file ordering canonical; hash-table
contents are sorted before serialization.  The effective `--diff` default is
read once into `range`, so the provenance names the same range that the parser
received.  In `--files` mode the range is `null`, rather than an unused default
that might imply a Git-derived scope.

This is deliberately provenance, not validation: it supplies no source
digest, commit claim, freshness assertion, reachability verdict, or baseline
comparison.  Those remain a later explicit change-review-consumer step.

## Controls

Authentic Tezt fixtures execute Git commits and the real binaries.  They check
one changed hunk (`[6]`), whole-file input (`"whole"`), and a deleted input
(`[]`).  Existing impact assertions continue to lock the bounded-MAY and TOP
wording.
