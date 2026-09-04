<!-- No title. The path roster/<task-slug>/questions.md already identifies this
     file, and a descriptive slug in an H1 briefs the researcher on the very
     thing this skill requires be withheld. -->

_Generated: 2026-09-04_
_DO NOT include the task description in this file or share it with the researcher._

1. In the exception-origin classification function, how are the `raise`/`reraise`/`failwith`/`invalid_arg`/`assert`/`partial_match`/`compare`/`division`/`index`/`inferred_bind` forms each detected, and for which of these forms does the code inspect the call's argument types (or values) before recording an origin, versus recording unconditionally?

2. What is the current implementation of the comparison-primitive refinement — which type predicate determines whether an argument type "could hold a closure", and where in the source is this predicate defined and reused elsewhere?

3. For the division and indexing primitive cases, what are the exact call patterns matched (e.g. `/`, `mod`, array/string indexing operators) and what argument information (literal values, inferred types) is available at the match site but not currently consulted?

4. In the CFG walker, how is an assertion node matched, what is the sequence of operations relative to the check for a literal `false` condition, and what data (if any) is attached to the recorded origin to distinguish an unconditionally-failing assertion from a conditional one?

5. What is the `form` column's CHECK constraint definition and full enum list in the database schema, and which query commands or fixpoint computations over call-graph edges read the origin/`form` fields downstream?

6. Across the existing test corpus and fixtures, what test cases or golden outputs currently assert on `division`, `index`, `compare` or `assert` origin forms, and what code patterns (literals vs variables, ground types vs polymorphic types) do those fixtures use?

7. [ecosystem] How do existing OCaml static-analysis or exception-safety tools (linters, abstract-interpretation frameworks, effect-tracking systems) determine whether a division, array/string indexing, or comparison operation can statically be proven not to raise, and what type or value information do they use to make that determination?
