# Independent domain check — implementation handoff notes

Required deliverable; native oracle passes, separate CHECK-1 wrapper remains. Keep the kernel
private and do not add a public embedding API merely to make tests possible.

One viable native layout is a Dune copy of the exact kernel source/interface
into a standalone test/probe stanza under test/. Move the two existing kernel
inline checks into test_cfa.ml without dropping their assertions, so the copied
kernel has no PPX/compiler-libs/SQLite dependency. The probe must compile the
real source, not a hand-maintained solver copy. Verify the final Dune arrangement
before claiming it works; this note has not run a compilation experiment.

The probe can expose test-only finite operations (fresh cells, target/reason
seeds, copies, solve and read) and normalized JSON results. Native CI exercises
it without Tezos. A separate JS checker compares those results to its own
repeated-scan Set oracle, rather than reusing the kernel's join/worklist.

Include closed small-graph enumeration plus selected cycles/long chains,
duplicate/permuted constraints, mixed known/unknown, unknown-only versus bottom,
and seeds/copies arriving after a previous solve. Check both components and
every requested cell, not just one sink or total count. Diagnostic witnesses
must not participate in convergence/equality.

CHECK1 must distinguish explicit assertion failure (1) from compilation,
execution, malformed output or setup failure (at least2). Native test-runner
exit1 alone is insufficient to make that distinction. Declare precise controls
and output parsing; do not convert a missing probe or malformed JSON into green.

This probe is test-only and does not implement call/return/environment transfer.
Actual CMT identity, metadata and consumer behavior remain CHECK2's obligations.

## Candidate native implementation — 2026-09-16

Root added `test/test_cfa.ml` and an exact Dune source/interface copy stanza.
The two prior kernel inline checks move to this standalone runner; production
solver semantics are unchanged. Its dependencies are Alcotest and Yojson, not
the compiler or database stack. This is post-implementation independent test
coverage, not a claim that these tests preceded the existing kernel.

The native oracle uses sorted lists and repeated complete constraint scans.
It covers all512 directed three-node graphs under forward/reverse/duplicate
operations, mixed values, an unseeded cycle versus unknown, late seeds and
copies, idempotent solve, and a2000-cell chain. Each cell's two sets are checked.

`test_cfa.exe --probe` reads `{cells, operations}` JSON. Operations are arrays
`["target", i, name]`, `["reason", i, kind]`, `["copy", src, dst]`, or `["solve"]`.
Each solve returns a full normalized cell snapshot. Invalid input or no solve
returns2; normal successful output returns0. The separate CHECK-1 JS wrapper
and its independent oracle/exit controls are still required. The literal
implementer subsequently built and ran the native executable: all6 groups
passed. The JSON probe's success/error contract has not yet received the
independent wrapper controls; do not infer CHECK-1 completion from6/6.

Root subsequently exercised the built probe directly using Node `spawnSync`:
the mixed-chain request returned0 with the exact three-cell product snapshot;
out-of-range cell, missing solve, malformed JSON and unknown operation each
returned2 with no successful stdout snapshot. The permanent CHECK-1 script,
its independent JS oracle, and assertion-failure control are still outstanding.
