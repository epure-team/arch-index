# CI and agent guide

Use arch-index in CI to make a review question reproducible. It can publish a
useful briefing on every change, and it can enforce a small set of architectural
rules. Those are different jobs: a report is evidence for review; a gate has an
explicit policy and an exit status.

This guide is language-neutral. Pick an input path supported by the project:
the LSP wrapper for a repository, a native producer, or an NDJSON producer
loaded with `arch-load`. The OCaml CMT path is described in the
[functor catalogue](functor-catalogue.md). Begin with the
[installation guide](install.md), rather than copying a command for another
language.

## A small CI shape

Run the project build first, then create one disposable index and use it for the
rest of the job:

```sh
# Replace this with the producer appropriate to the repository.
./arch-index . "$RUNNER_TEMP/architecture.db" go

# A non-blocking PR briefing. Keep its Markdown/JSON as a review artifact.
./arch-impact "$RUNNER_TEMP/architecture.db" \
  --diff "$BASE_SHA..$HEAD_SHA" --repo . --format md \
  > "$RUNNER_TEMP/impact.md"

# An explicit blocking policy; exit status is the policy result.
./arch-rules "$RUNNER_TEMP/architecture.db" arch-rules.txt \
  --on-vacuous fail
```

`$BASE_SHA` and `$HEAD_SHA` are CI-provider inputs. Resolve them to commits
available in the checkout; a shallow checkout that lacks the base is an input
failure, not an empty change. For a push job without a meaningful diff, omit
the impact step or use `--files` to state the intended whole-file scope.

Keep the database only for the duration of the job unless it is deliberately
published for investigation. It can contain source-derived names, paths and
comments. Publish the small report artifacts that reviewers need, and set a
retention period.

## Read signals honestly

| Signal | What to do | What it does *not* mean |
|---|---|---|
| `MUST` path / `VIOLATION` | Review or fail according to the declared rule. | A vulnerability or a complete attack path. |
| `MAY_ENUMERATED` / `POSSIBLE` | Inspect the finite candidates and choose policy deliberately. | A call that definitely occurs. |
| `MAY_TOP` / `UNKNOWN` | Investigate the frontier or retain it as known uncertainty. | A clean result, or evidence that a hidden target exists. |
| `PASS` | A particular rule was proved unreachable under its documented closed-world contract. | General code safety or full project coverage. |
| `VACUOUS` / `NOT_COMPUTED` / refusal | Fix the selector, producer, inputs or policy before relying on it. | A passing analysis. |

The same caution applies to a PR briefing. `arch-impact` reports reachability
over known `MUST ∪ MAY_ENUMERATED` edges and separately identifies the TOP
frontier. Its counts are lower bounds when that frontier is present. It is not
a generic quality score and should not be converted into one.

## Start with a report, then add one rule

For an AI-assisted ("vibecoded") project, the first useful integration is
usually an artifact on each pull request:

1. Build and index the changed revision.
2. Run `arch-impact --format md` for the PR range and attach the result to the
   CI run or PR.
3. Have the reviewer or agent inspect touched exported functions, candidate
   tests and any uncertainty frontier.
4. Add an `arch-rules` rule only for an invariant the team can state and
   maintain, such as a request handler not reaching a credential sink.

Example `arch-rules.txt` policy:

```text
rule "HTTP handlers must not reach plaintext logging"
  forbid reach from file:src/http/** to fn:log_plaintext
```

Run it with the default policy first and inspect the census. `VIOLATION` and
`POSSIBLE` fail by default; `UNKNOWN` warns by default because failing every
unresolved callback path is rarely sustainable. A team that has deliberately
reduced its uncertainty frontier can choose `--on-unknown fail`. Keep
`--on-vacuous fail`: a selector that stops matching after a rename must not
silently make the rule green. The full verdict and exit-status contract is in
[fitness functions](fitness-functions.md).

Do not gate on: number of indexed functions, fan-in ranking, comment score,
number of `MAY` edges, a coverage percentage, or the disappearance of a report
row after the index scope changed. These can all change without proving an
architectural improvement.

## Give an agent bounded tasks

An agent is most useful when it receives the command, artifact and decision to
make—not an instruction to infer security from a count. Good prompts include:

```text
Read impact.md. For each touched exported function, list the reported bounded
call paths and TOP-frontier holders. Propose review questions. Do not describe
MAY or TOP as definite reachability, and do not call an absent row a fix.
```

```text
Run the named arch-rules policy. If it is VACUOUS, NOT_COMPUTED, UNKNOWN, or
refused, explain the evidence and stop; do not weaken flags or edit the rule to
obtain a pass. For a VIOLATION or POSSIBLE, show the witness before proposing a
change.
```

The JSON formats are appropriate for automation, but consumers must preserve
their producer/version/scope provenance. For repeated reviews, use the
[reporting](reporting.md) package workflow or the dedicated
[change-impact](change-impact.md) consumer; both refuse incompatible inputs
instead of presenting an index/corpus change as a code change.

## A CI failure is not always a finding

Separate the outcome in CI logs and PR comments:

- **Policy failure:** a declared rule or explicitly enabled impact ratchet
  failed. Inspect its witness and policy configuration.
- **Analysis refusal or unavailable data:** the producer did not compute what
  the consumer needs, the index contract is incomplete, or the diff/scope is
  unusable. Repair the pipeline; do not report it as clean.
- **Infrastructure failure:** build, checkout, indexer, database or artifact
  publication failed. Preserve diagnostics and retry/fix the infrastructure;
  it has no architectural verdict.

Never replace a failed/refused invocation with a cached or old artifact while
calling the current revision green. A baseline is something a human promotes
after review, not the latest successful run.

## Next references

- [Change impact](change-impact.md) for PR briefings and its JSON contract.
- [Fitness functions](fitness-functions.md) for rule syntax and gate policy.
- [Reporting](reporting.md) for JSON, SARIF, HTML and recurring packages.
- [MCP server](mcp-server.md) when an agent needs the same bounded queries
  interactively. MCP is optional and a green default CI run may not validate it
  when its private dependency credentials are absent.
