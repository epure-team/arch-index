# escaping-origins — accepted follow-ups

**Date:** 2026-09-05
**Status:** open. Registered rather than closed — the round-4 GO condition was
that these be *written down*, not merely called follow-ups.

This file exists because a follow-up that lives only in a review comment is not
a follow-up: the review is archived, the reader is not, and the item disappears
with the round that named it.

## Recorded from my own knowledge of the code

- **`--forms` and `--channel` share the flag parser but not the vocabulary
  source.** `--forms` validates against a hard-coded whitelist in the command;
  `--channel` validates against the channels the DATA reports. A channel the
  `error_contract` declares but the corpus happens not to exercise is refused
  as if it were a typo. `channels_of_contract` already exists at
  `arch_query.ml:169` and is the right source.
- **`--channel all` renders the channel column into the SQL rather than binding
  it.** Safe today because the accepted set is exactly what the index reports,
  so no caller text reaches the query — but a bound parameter would remove the
  need to argue that.
- **The degraded coverage arm is unreachable dead code** (`Arch_db.rows` on a
  fixed-column SELECT always returns one row of that width). Kept deliberately,
  documented as unreachable; it should either become reachable or go.
- **`escaping-origins` is the only command in its family without a `--limit`.**
  On a whole-tree root the table is unbounded.
- **The closure follows every resolved edge regardless of `kind`,** so a MAY_TOP
  edge with a `callee_id` (there are none today) would be traversed as if
  resolved. Stated because the invariant is currently accidental.

## Copied verbatim from the round 4 and 5 review reports

Transcribed, not restated. The earlier version of this section said I could not
reproduce these and refused to paraphrase them; the reviewer supplied the
originals and they are below unchanged.

- **MEDIUM-3** — the in-comment figures (241/1287 nodes, 37-versus-38 origins,
  30526 rows, the 21-versus-37 discrepancy) now carry granularity, corpus and
  producer, **but still no reproduction command**, so nobody can re-derive them.
  §10.3 asks for the scope *and* the command, or no number.
- **MEDIUM-5a** — `--forms` with no value silently falls back to the default
  set: `--roots X --forms` → a full answer with the four default forms,
  **exit 0, no diagnostic**. `flag_val`'s `x :: y :: tl` cannot see a flag at
  end-of-line and falls through to `_ :: tl`.
- **MEDIUM-5b** — `--forms --roots X` swallows the following flag as its value →
  `unknown origin form(s): --roots`, exit 2. A misleading message for a genuine
  caller error.
- **LOW-1** — `ORDER BY o.form, m.path, o.line` is not a total order. Measured
  **40** colliding groups on the self-index (23 then 127 on other corpora —
  build-dependent). Row order is at the planner's mercy. Fix: add
  `, f.name, o.id`.
- **LOW-2** — exit codes 0/2/3 are documented nowhere in the usage, and **an
  ambiguous root and a non-existent root both exit 3**, so a script cannot tell
  "qualify your root" from "your root does not exist".
- **LOW-4** — ⊤ is a **strict subset** of unresolved, rendered as though the two
  were disjoint. Measured: `MAY_TOP = 1130`, of which **0** have a resolved
  callee; `callee_id IS NULL = 8313`. "`N edges unresolved · M ⊤`" invites
  adding them. Fix: "… · **of which** M ⊤".
- **LOW-a** — the duplicate-flag refusal works (`--roots A --roots B` → exit 2,
  good message) but **M-DUP survives**: nothing tests it.
- **LOW-c** — `known_forms` omits `inferred_bind`, which
  `architecture-schema.sql:421` permits. `--forms inferred_bind` → exit 2
  "unknown origin form(s)".
- **LOW-d** — the JSON preamble does not carry the verdict **word**; it carries
  `nodes_beyond_root` (`0` for NOTHING TRAVERSED, `1` for LOWER BOUND), so a
  machine consumer can derive it, but the readable sentence is list-format only.
- **LOW-5** — the `:*` sigil collides with a function literally named `*`: the
  `root` CTE tests `? = '*'` against the caller's string, so `mymath.ml:*` on a
  module defining `let ( * )` silently means "whole module". No such name in
  this corpus; the root echo makes it legible.
- **LOW-6** — the dead `| _ ->` arm builds a 3-field text while `preamble ~h`
  still passes the full column-name list against a short `~cells`, and
  `preamble` (`arch_query.ml:150-153`) **does not check arity**. The comment
  keeps the arm for "a future edit to the column list" — but as written, that
  edit would produce a silently misaligned JSON preamble.
- **LOW-e** — `resolved_out_edges` is not "out": it reads 8 for a root whose
  banner says NOTHING TRAVERSED and whose `nodes_beyond_root` is 0, because it
  counts every resolved edge from a `reach` node, intra-root included. The name
  promises the very proxy round 3 blocked on. Rename to
  `resolved_edges_from_closure`.

## Not a follow-up — decided

- `escapes=1` is currently non-discriminating (every recorded origin has it).
  Kept as a guard against a producer that starts computing it, and **said so in
  the usage**, which is the whole of that decision.
- Under `<path>:*` every module member is a root, so an origin in a function
  nothing calls is `MUST`. The semantics are defensible; the round-4 wording
  that promised "definite call path" was not, and was corrected rather than the
  semantics changed.
