# Independent reviewer round 1

Recommendation: changes required. The native witness admission boundary accepts reused residual evidence; required rich/effectful-open preservation coverage is incomplete. See reviewer-round1-findings.json. No pipeline GO or retention authorization is issued.

Reviewed HEAD: 09b28234d07fa612cdd3f62060dfea434e1bc4fc; product source commit a5ae981. Read the complete origin/main...HEAD diff, complete changed product/test/checker files, reviewer role and briefs, and all 34 FR / 13 AC. The language-pattern directory is absent. Scope gate is owned by main and was reported PASS; this reviewer does not replace it.

## Personally executed gates

All commands were run serially under the exclusive root build/gate lock, with RTK prefixes. Main explicitly froze writes for CHECK3/4. These results describe the reviewed HEAD before subsequent repairs.

| Gate | Actual exit | Result |
|---|---:|---|
| opam exec -- dune build | 0 | Built |
| opam exec -- _build/default/tezt/tests/main.exe --no-color --keep-going | 0 | 336 SUCCESS, no failures; first/last success 21:18:35.261–21:22:40.914 UTC |
| node roster/tezos-open-bodies/check-native.js | 0 | Existing native, identity, arity, flat and four Tezt controls pass; coverage limits above remain |
| node roster/tezos-open-bodies/check-witness-inputs.js | 0 | 316 actual positioned DB pairs, duplicate fixture and existing refusal controls |
| node roster/tezos-open-bodies/check-baseline.js --replay | 0 | 45052 rows, neutral replay, 17 malformed-record refusals, no overwrite |
| node roster/tezos-open-bodies/verify.js --witness improvement/2026-09-14-tezos-resolution/attempt3-reviewed-witness.json | 0 | +316 protocol / +0 Irmin relations, zero losses or unexplained changes; 45052 rows each |
| node roster/tezos-open-bodies/check-self.js | 0 | Exact smoke, policy hashes, source-tree attribution boundary |
| node scripts/review-bundle-verify.js | 0 | 22 SHA-matched files, bundle 1.6.0 |
| git diff --check | 0 | No whitespace errors at verification time |
| node roster/tezos-open-bodies/check-self-parser-test.js | 0 | Existing parser refusals pass |
| Native residual reuse control: ocamlc -bin-annot -c native.ml | 0 | Compiler-produced mixed and full overapplication groups |
| node /tmp/arch-index-owner-residual-5bLLl3/repro.js | 1 | Two positive admission controls pass, then required reuse refusal assertion fails |

Full guard log: improvement/2026-09-14-tezos-resolution/attempt3-review-owner-full.log. CHECK4 evidence: improvement/2026-09-14-tezos-resolution/attempt3-candidate-MIAr1M. Candidate digest: 9ab4e0b13457247fb93dc83bf80323fcc5cec67866a18f56995ac0ec4a20867e. Baseline digest: 00f1769d6db7f6ee91ee51becabccd7b4ce13975acb6610c95ace69a7f620e9b.

## Review dimensions

Correctness: structural admission is narrow; same-CMT compiler stamps, exact physical root identity, canonical name, unique observation and successful insertion govern final enumeration. Known drops outrank availability mismatch. Optional supplied counts and per-application residual emission are consistent with the changed product path. No product defect was confirmed. The independent admission checker nevertheless fails its occurrence-capacity contract as demonstrated above.

Security and trust: no new external-input execution or credential surface was introduced in the product. Native evidence is replayed against pinned artifact hashes, and before/after positioned rows and head identities are checked. The residual reuse defect weakens this evidence boundary; the current fixed410 result contains no residuals and is not itself disproved.

Regression and maintainability: public flat collection keeps an empty new-target context; callback, letop and point-free recognition remain unchanged. Existing canonical formatting is shared, marker finalization clears the private edge form, and full336 passes. The missing preservation fixtures must be filled before the broad AC5/7/8 claims are treated as established.

Self references: the consumer checker changes only its two exact duplicated constants. The sole split_last assertion remains the identical source expression, relocated under the renamed private collector at line1609, with x1 unchanged. Read-only inspection of the golden and origin 2x2 records agrees with source-only attribution; the independent CHECK5 run passes. No guard threshold or allowance count was relaxed.

Unavailable checks: formatter/coverage and language-pattern files are not configured/present. No hook, claims reconciler, specialist tooling or crossruntime pass is invented. Main coordinates those pipeline dispositions separately.

Only this reviewer report/findings were written in the repository. Seven original unrelated paths and main's review trace remain untouched. The temporary reproduction is retained for main to promote into a permanent regression test. Build/gate lock was released after all gates and the native reproduction completed.

Open questions: none requiring user direction. Repair the two findings, preserve the failed native assertion evidence, then independently re-run the affected review gates.
