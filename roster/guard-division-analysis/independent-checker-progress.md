# Independent checker — implementation in progress

2026-09-13, owned guard worktree. No review/QA verdict or implementation completion claimed.

- `node scripts/check-arch-guard.js domain`: exit 0, 276192 probe responses checked against independently defined JavaScript BigInt concretization. Exhaustive concrete arithmetic at widths 3–8, selected extrema at 31/63; non-singleton containment, restriction and initial join laws included. Not a formal proof; complete monotonicity/associativity coverage remains to add.
- `opam exec --switch=/home/mathias/dev/arch-index -- node scripts/check-arch-guard.js numeric`: exit 0; all 12 original fixture sites checked by line/status, census 3 NONZERO / 1 ZERO / 2 MAY_ZERO / 1 UNREACHABLE / 5 UNSUPPORTED. Broader semantic cases remain to add.
- Same toolchain, checker `inventory`: exit 0; eight primitive families plus partial application, original slot 2, indirect/shadow exclusion, repeat determinism, canonical deduplication and copied-identity rejection.
- Checker `report`: authentic RED, exit 1, assertion “text must expose application source location”. All preceding metadata probes completed. The JSON carried the source location but the text projection omitted it. Rendering fix added after this RED; rerun pending.
- Test-only fixture helper built and exercised by Terra subagent: ghost metadata, long identifier omission, Interface rejection. Missing build target was setup evidence, not behavioral RED. Root checker additionally exercised invalid/cross-file/backward/max-column locations before the text assertion.

Report rendering fix: scoped build exit 0, report checker GREEN exit 0, six metadata cases.

Owned mode: exit 0, actual 23 selected lib/arch_index artifacts, zero sites (not evidence of absence of defects or Tezos improvement).

Inputs mode authentic RED: missing input produced Cmdliner exit 124 rather than specified 2, with empty stdout. CLI changed to defer path validation to the frontend and normalize nonzero Cmdliner returns to 2; verification pending.

Checker is not finished: full boundary coverage remains. Inputs deliberately exits 2 after its partial checks until mandatory missing cases are implemented, not a false pass. No PR created. Existing full-suite success predates the latest checker/render changes.

## Later verification in this continuation

- CLI exit normalization rebuilt successfully; all implemented input checks now pass before the explicit incomplete-verification exit 2.
- Numeric coverage expanded to 26 additional single-site fixtures plus the original 12. Annotated parameter initially expected NONZERO was a **checker expectation error**: actual `ocamlc -dtypedtree` showed `Tpat_alias(Tpat_any, d)`, expressly excluded by the spec. Expected UNSUPPORTED corrected on compiler evidence, not to weaken the product.
- Separate local alias literal `type integer = int; let f () = 10 / (2 : integer)` produced an authentic product RED (`unsupported_operand_type`). Root restored CMT environment summaries with `Envaux`, restricted the load path to the linked compiler's standard library, and reset the reconstruction cache per artifact. First Envaux-only attempt still failed; adding the restricted standard-library path made all 26 cases GREEN. Arbitrary artifact include paths remain unused; unresolved types stay unsupported.
- Exact JSON size: a test-only CMT mutation and fixed 32 MiB artifact padding calibrated 16777216/16777217-byte serialized reports. One-over rejected atomically in JSON and text. Inclusive first triggered checker execution failure 2/ENOBUFS because CLI appended an unchecked newline (not an assertion RED). Changed JSON output to `print_string`; inclusive full stdout now exactly 16777216 bytes, one-over rejection remains GREEN. Report mode includes this boundary check and six metadata mutations; exit 0.
- Traversal limits exercised through genuinely compiled source, independently counted by a private Typedtree inspector: 100000 nodes accepted / 100001 rejected; 10000 sites accepted / 10001 rejected; depth 512 accepted / 513 rejected. The initial inspector assertion wrongly excluded its informational fields (checker setup/expectation issue), corrected to compare measured counts.
- File/input boundaries: 128 inputs accepted / 129 rejected, 33554432 bytes accepted / 33554433 rejected, 268435456 aggregate bytes accepted / plus exactly one byte rejected. Four unsupported annotation classes, missing/nonregular/symlink/collision/usage cases tested. Scratch directories are uniquely created and removed by each checker invocation.
- Full `dune test --root . --force`, explicit project switch, session 96296: terminal exit 0, 247/247 Tezt and 64 Alcotest. Tezt displayed 23:14:11.550–23:16:27.225 UTC (not full command elapsed time). Tool output truncated; this note is a summary, not a claimed complete retained log. This full suite includes the latest CLI/interpreter fixes but does not yet register the independent JS modes.
- `git diff --check`: exit 0.

Still required before phase completion: deterministic changed-read verification, complete domain algebra/monotonicity coverage, Tezt wiring for six modes and checker negative controls, documentation integration, independent roster review/QA/ship. Inputs remains deliberately non-green. No PR or merged implementation claim.

## Resume 2026-09-13, following the CFA clarification

The preceding remaining-work paragraph is historical, superseded for the following items:

- Fresh roster preflight READY: canonical ledger schema valid (Full, latest completed plan), bundle 22 SHA verified, @install + Tezt executable build 0, nonexecuting collection 0. No unrelated temporary files cleaned.
- Domain laws completed: standalone domain exit 0, 640734 probe responses and 23219242 algebra assertions. Full finite abstract state sets at widths 3–8; selected 31/63 extrema. Includes join associativity/commutativity/leastness and unary/binary transfer monotonicity. This is testing, not formal verification.
- Sol subagent extracted the existing digest/read/digest sequence into internal Guard_input, without changing the public Arch_guard interface or introducing runtime test flags. Private probe uses a real Implementation CMT read, stable SHA positive control, deterministic mismatched digest negative control, and digest/read call counts. A temporary missing-comparison seam was a **test-sensitivity mutation**, not a discovered product defect or missing production behavior. Installed CLI error atomicity remains separately tested; no real filesystem race claim.
- Inputs mode now exits 0: all documented inclusive/one-over counts/byte/depth boundaries, incompatible compiler magic, annotation classes, canonical identity/error cases, and private changed-read seam covered.
- Six independent modes and two exit controls registered in Tezt; helper executable build dependencies added. README/CHANGELOG and component docs integrated. Full integrated suite running; not yet claimed green here.
- Existing origin recurring consumer authentic/failures/package modes each exit 0. Failure mode prints intentional injected cleanup/write diagnostics.
- Fresh self-index at /tmp/arch-guard-self-M0NAlT/self.db: 23 modules / 828 functions / 5223 calls, exactly equal to unchanged golden. Existing architecture rules exit 0: one proved, three UNKNOWN, zero failures, not four proofs. Fresh origin consumer held and evidence package validator 0. Pre-commit impact command 0 only covered committed range 77c7691..HEAD; it does not include uncommitted implementation and must be rerun after checkpoint commit.

No review, QA, PR or merge claimed. Fresh recalibration and final implementation handoff remain.

Integrated full suite completed: session14879 terminal0;255/255Tezt plus64Alcotest.
All six JS checker modes and both exit controls executed successfully inside Tezt.
Complete collected command output retained in integrated-suite.log (initial and terminal
chunks, neither truncated). Scope gate and git diff --check both0. Product checkpoint
commit will precede fresh recalibration so it measures the actual committed implementation.
