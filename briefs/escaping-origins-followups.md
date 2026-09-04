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

## Recorded by reference — I could not restate these precisely

Rounds 3–5 accepted further items (numbered MEDIUM-3, MEDIUM-5, LOW-1/2/4/5/6
and LOW-a/c/d in the review reports). **I do not have their text and will not
paraphrase them from memory** — inventing a plausible restatement is worse than
an honest pointer, because it would read as a record while being a guess.

They live in the review reports for PR #71 rounds 3, 4 and 5. Whoever picks this
up should copy the originals in here; until then this section is a marker that
the list is incomplete, not that it is empty.

## Not a follow-up — decided

- `escapes=1` is currently non-discriminating (every recorded origin has it).
  Kept as a guard against a producer that starts computing it, and **said so in
  the usage**, which is the whole of that decision.
- Under `<path>:*` every module member is a root, so an origin in a function
  nothing calls is `MUST`. The semantics are defensible; the round-4 wording
  that promised "definite call path" was not, and was corrected rather than the
  semantics changed.
