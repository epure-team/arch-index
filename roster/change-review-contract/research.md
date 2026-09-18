# Research — change-review semantic contract

## Existing facts

`arch-impact --format json` already exposes a single JSON object with:

- `resolved_edge_kinds: [MUST, MAY_ENUMERATED]` and
  `resolved_cone: possible_bounded`;
- touched functions (`name`, `file`, `exported`, mapping `how`), exported
  bounded-upstream candidates, bounded and TOP-upstream counts, tests, the
  forward TOP frontier and line-level decision findings;
- `contract_ok`, which is the exact shared edge-kind contract check.

`docs/change-impact.md` explicitly says these are lower bounds.  A resolved
path that traverses `MAY_ENUMERATED` is not definite; a forward `MAY_TOP`
frontier names where the calculation stops, not a list of hidden targets.

The Stage8 `analysis-report-consumer` is intentionally narrower: it compares
only `api_surface|file|function`, stores an explicit scope manifest, and
refuses schema/profile/producer-identity/coverage/scope mismatch.  Its scope
manifest is necessary because reports do not publish a corpus fingerprint.

## Design implication

A change-review baseline cannot compare two unrelated diffs and call an
addition/removal a code regression.  The changed-line mapping is itself a
first-class input.  Its semantic key must include a stable file path plus
function identity, not an index row id or a display line; an optional line
range can explain the map but cannot define identity alone.

The minimal contract should therefore be a separate, versioned JSON sidecar
emitted by an explicit runner:

```text
arch-impact DB --diff BASE...HEAD --repo REPO --format json
node scripts/change-review-consumer.js --impact impact.json --scope scope.json --out RUN
```

It stores the raw current impact JSON and a normalized comparison view.  A
future producer enhancement may supply stronger corpus input digests, but this
runner must not invent one from `db_path` or source text.

## Candidate normalized identities

| Surface | Identity | Meaning |
|---|---|---|
| touched | `file:function` | changed indexed function; mapping mode recorded, not key |
| bounded upstream/API/test | rendered graph label from report plus declared kind `bounded_possible` | candidate over MUST ∪ MAY_ENUMERATED, not a definite caller |
| TOP frontier | `function` plus `escapes` count | observed escape holder, not hidden target set |
| decision finding | `file:line:form` | current line-attached observation, valid only under same changed-line scope |

Candidate status names are `new`, `unchanged`, `absent` and `unavailable`.
`absent` remains descriptive.  A changed `contract_ok`, `resolved_cone`, scope
manifest, impact input range, unavailable decision analysis, unmatched files,
or malformed/partial package must refuse a baseline comparison rather than
classifying observations.
