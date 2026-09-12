_Generated: 2026-09-12T19:54:07.712Z_
_DO NOT include the task description in this file or share it with the researcher._

1. Where are the repository’s OCaml CLI components defined, and how are their binaries, libraries, commands, fixtures, and tests organized?

2. How does the existing code classify OCaml syntax and operands, and where does it consume Typedtree or CMT data, including compiler primitive identities?

3. What integer semantics are currently encoded or assumed, including machine-integer width, overflow behavior, division behavior, and representation of unknown or unsupported expressions?

4. Where are control-flow states represented, and how do existing analyses handle branches, joins, unreachable states, top/bottom values, and unsupported constructs?

5. How are deterministic diagnostics, provenance, coverage scope, rule verdicts, allowances, and coverage references currently produced and tested?

6. [ecosystem] How do existing OCaml compiler APIs expose Typedtree/CMT primitive identities and machine-integer operations across supported compiler versions?

7. [ecosystem] How do established intraprocedural abstract interpreters represent integer division, overflow, branches, joins, top/bottom, and conservative unknown results?
