# Independent measurement verification

2026-09-13. Research instrumentation only; not product roster-review/QA GO.

Root copied both sources into a fresh owned /tmp/arch-index-binder-verify.*
directory and compiled with OCaml5.3 via the explicit arch-index opam switch.
Compile/link exit0, fixture read exit0. Exact fixture observation:4 ordinary,
0 unit;4 bound-functor heads; arguments2 structure/1 alias/1 named parameter.
Fresh410-manifest read validates every CMT hash, then output compared by cmp
to run-2026-09-13.tsv: exit0, byte-identical. Captured tool message:
ROOT_REPLAY_EXACT_MATCH=PASS. Temp directory removed by the owned-directory trap.

Probe source SHA256:
815af8472c78023739c86894e5313a76c283580bddc1cc144f27c5553cfdae5f.

Independent Sol reviewed the source/fixture/captures without editing them:
no blocking issue in measured scope. The one documentary limitation (ellipsis
in the fixture compile command) was corrected to a complete command. Root also
added cleanup to the reproduction shell example to avoid unused build artifacts.
These documentation edits do not change probe source or captured results.

Known limits remain: root category is not declaration/target resolution;
single-pass forward binders can be unknown; no whole-program closure, graph
delta, fresh-source consistency, or generative exception identity proof follows.
The input artifact hashes bind the410-CMT selection, not all Tezos inputs.

The name-key mutant captured by the implementer retains Ident.same and therefore
loses a match rather than cross-binding; the recorded fixture is sensitive to
identity-key removal, not a claimed end-to-end target-substitution test.
