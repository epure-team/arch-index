# Independent native pair review — attempt4

Technical GO for the181 pair mappings only, not implementation/roster/QA/ship.
Independent Sol reviewer open_review_spec inspected181/181 transitions with no
validator failure and consumed exact before/after positioned capacities.

Coverage:179 caller/site groups,177 singleton groups and both two-member groups
(Irmin Store.ml1179 native789/790; protocol storage_description.ml158 native33/34).
All four duplicate members have distinct native indices and full offsets.
All181 target owner links, compiler Ident/UID, full ranges, RHS containment and
deepest caller correspondence agree. Candidate root ordinals are all1; native
fixture controls separately cover actual same-position ordinal2 collisions.

Native410 evidence SHA256:
6f6597c16935959dd5349f756ff6a294e73d9f93e6f8ffdf2a6da2b205fc45ec.
Root additionally reran the compiler-only probe in verify.js; all410 records
reproduced and the complete comparison passed with no unexplained facts.

Irmin Tree.ml1881–1932 independently inspected: occurrence1058 at1920 has
aux_6562/Irmin__Tree.1667, owner566 Make.update_tree#1.<fun:1881:17>, arity3 and
three supplied arguments. The old returned-call TOP is preserved unchanged;
only the auxiliary head changes. Thus no new residual witness is required.

Root replay output: attempt4-candidate-HSz8MD,45052rows each side,181paired
replacements,+68Irmin/+111protocol relations,0loss/0errors. Candidate digest:
082bdce92c6cab7b654f87a90db59ca9979d7004f45a42997a33718f6cd7c67a.

The original mechanical draft remains unchanged. A separately generated reviewed
witness records this automated independent review; no human review is claimed.
Full guards, calibrated references, roster review/QA and exact-headCI remain open.
