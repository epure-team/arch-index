# Reachable crash and unfinished-code sentinel — design v1

## Result meaning

The sentinel produces *review obligations*, not security findings.  A row is:

```text
root --[MUST | MAY_ENUMERATED]*--> origin
```

or a named `MAY_TOP` frontier from a reached caller.  The report preserves the
underlying index and policy provenance; an omitted artefact, unresolved call,
external, callback or FFI edge is visible, not interpreted as a negative.

## Required row fields

`origin_id`, canonical function/source location, `form`, `guard_class`,
`surface`, `reach_kind`, `witness`, `frontier`, and manifest identity.  Surface
is a target-supplied closed vocabulary; unknown mapping is `unclassified`.
Guard classes are `assert_false`, `checked_assert`, `literal_zero_divisor`,
`unknown_divisor`, and `other`; only a producer fact may assign one.

## Compatibility

Existing `escaping-origins` output remains unchanged.  The new report consumes
existing rows plus the prerequisite producer vocabulary; it does not make a
legacy database appear classified.  A database lacking the required contract is
`REFUSED` or `NOT_ANALYSED`, never an empty report.

## Policy boundary

Feature-disabled paths are assessed only by a separate declared entry policy
whose schema and configuration digest are in the manifest.  A late internal
flag test is evidence for review, not sufficient proof that a feature is
unreachable.
