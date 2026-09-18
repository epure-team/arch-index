# Roster intake — analysis report profiles

## Objective

Turn an existing rich index into immediately usable developer analyses by
adding named `arch-report` profiles. Each profile composes existing readers;
it must preserve their availability and MUST/MAY vocabulary rather than invent
a score or treating missing analyses as a clean report.

## Initial profiles

1. `api-review`: exported API surface, escaping origins/effects where those
   producer contracts exist, and unknown frontiers.
2. `architecture`: existing rule evaluation plus report provenance.
3. `change-review`: deferred until a stable semantic diff identity is designed;
   it must not parse Git text or compare SQLite row IDs opportunistically.

## Scope of this stage

Implement `api-review` and `architecture` as explicit `--profile` values,
with one report value rendered consistently to JSON/SARIF/HTML. Profile output
must state selected scope, availability/refusal reason, MAY/TOP limitations and
the command needed to inspect underlying evidence.

## Non-goals

- No new static analysis, producer change, graph traversal variant, severity
  score, gate policy, automatic DB rebuild, or baseline replacement.
- `change-review` is not shipped as a misleading shallow diff.

## Acceptance evidence

- Profile-less invocation retains the current artifact contract.
- Profiled report includes every requested section even when unavailable.
- API roots use only producer-published exported facts; no heuristic export
  inference.
- JSON/SARIF/HTML remain derived from the same report value and are checked on
  complete, partial and absent-contract fixtures.
