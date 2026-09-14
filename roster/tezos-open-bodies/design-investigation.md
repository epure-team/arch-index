# Read-only design investigation — not a passed roster review

Fresh Terra subagent open_target_design examined source and the frozen attempt2
predecessor DB. Main independently queried the same Raw.step node structure.
No product edit, test, or build was performed by this agent. Its output is
planning evidence; intake/spec/plan and independent implementation gates remain.

## Observed body identity

- Raw.step spans637–1713 and has one outgoing parent-to-lambda relation.
- Raw.step.<fun:639:5> spans639–1713 and owns460 outgoing calls.
-181 applications of step are currently callback_param TOP:165 in that body,
  16 in other Raw helpers (agent query). Main native census independently matched
  181 Pident applications to exact binder step_1789 and inner syntactic arity6.
- Targeting the binding parent would not identify the callable body. Peeling the
  root would move existing calls/effects and violate retained relation stability.

## Recommended bounded contract for intake

Consider structural Tstr_value/Tpat_var binders only, with exactly one lexical
Texp_open whose module expression is Tmod_ident and body is Texp_function.
Resolve only actual Pident head applications using that exact compiler binder
to the already-indexed synthetic body. Preserve canonical lambda naming and
collision behavior, parent-to-lambda row, all caller nodes, CFG and channel facts.
Use enumerated targets, never new MUST. Syntactic arity comes from inner function;
do not count omitted labeled argument slots as supplied expressions.

Main refinement of agent alternative: do NOT put wrapped binders into the old
body-only local_fn_stamps table. Although the agent mentioned extending that
builder conditionally, its consumers include aliases/callbacks/letops and would
expand more than the proposed application-only contract. Prefer a separate,
explicitly scoped descriptor/table consumed solely at admitted head applications.
This remains a design candidate until spec and plan are validated.

The flat collector discards synthetic lambda nodes. It must keep legacy output
for these cases, not emit a new dangling synthetic callee spelling. An explicit
rich-only context or empty-by-default optional target table can bound the change.

## Exclusions and checks to freeze

No local Texp_let binder support, callback/escape resolution, letop resolution,
qualified-member expansion, alias-chain expansion, nested-open chains, computed
module opens, arbitrary RHS normalization, root peeling or CFA in this attempt.
No change to point-free edges, returned functions, existing rich effect metadata
or flat output. Missing/rejected body nodes must remain explicit TOP.

Native fixtures should pair recursive structural wrapped function and independent
caller, full/partial/labeled applications, non-vacuous old parent/body rows and
exact unchanged caller/effect/flat snapshots. Include local-let/parameter/alias/
computed-open/nested-open/returned-value refusal decoys and dropped-body control.
Every changed fixed410 occurrence needs independent binder/body/site evidence;
the63/344 documentary census is not an admission witness and includes out-of-scope
local definitions and nested opens. No gain is preclaimed.
