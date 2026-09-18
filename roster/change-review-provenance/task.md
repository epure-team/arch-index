# Roster intake — change-review impact provenance

## Objective

Publish the exact, canonical input scope of `arch-impact --format json` so a
future recurring change-review consumer can refuse incomparable briefs before
it compares their semantic observations.

## Contract

Add a versioned `impact_input` object to JSON only:

- `version: 1`;
- `mode: "diff" | "files"`;
- `range: string | null` (the effective Git range only in diff mode);
- `changed_files`: path-sorted entries containing the canonical changed-line
  representation: `"whole"` for `--files`, an ascending integer list for a
  normal diff, including `[]` for a deletion-only file.

It is a description of the exact input consumed by this invocation, not a
source freshness proof, a content digest, a Git commit assertion, or a gate.
The existing text/markdown output and all reachability semantics remain
unchanged.

## Acceptance

1. Diff and `--files` forms are explicit and deterministic under input-order
   changes.
2. Deletion-only and empty diffs are distinguishable.
3. Paths and lines derive from the already parsed `Arch_diff` value; no second
   Git parse or text heuristic is introduced.
4. Existing JSON fields and text wording remain compatible.
5. Authentic Tezt controls cover mode/range, sorted lines, whole files,
   deletion-only entries and unchanged MAY/TOP labels.
