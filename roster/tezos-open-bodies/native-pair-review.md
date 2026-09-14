# Native pair review — attempt 3

The main agent independently read the compiler-only probe and admission code,
then checked the generated proposal against the native records. The actual
identity/capacity check passed: 316 transitions, 316 singleton unanimous
caller/site/head groups, 43 root bodies, 10 pinned CMT records, no residuals.
This is permission to compare these exact pairs, not a KEEP or roster GO.

Evidence SHA-256:
`5184618340dc8e55c3bc5ce7d9310cce8715232742df3615d5b3d22e302698e8`.
The evidence is in the loop directory as
`attempt3-native-candidate-evidence.json`; the source proposal is
`attempt3-unreviewed-witness.json`, deliberately rejected without review fields.
Main emitted `attempt3-reviewed-witness.json` only after the independent check.

Checks bind compiler Ident and UID, literal-body cardinality and canonical name,
caller ownership/range, application location rather than head location, and
one-use native occurrence capacity. The admission path also replays the probe
against the SHA-256-pinned CMT files. MD5 values emitted by compiler-libs are
explicitly labeled and are not substituted for the pinned SHA-256 checks.

Two mistakes in the initial witness interpretation were corrected before
acceptance: treating promoted roots as ordinary binding functions, and ignoring
calls in a non-function structural binding RHS. The latter is supported only
with native enclosing-binding identity and RHS containment, not a name/span
fallback. Nested owners use the independently derived full lambda chain.

The 316 proposed transitions are protocol-only: script_interpreter 187
(including 181 Raw.step calls), script_ir_translator 70, script_ir_unparser 17,
ticket_scanner 14, sc_rollup_operations 9, apply 9, zk_rollup_storage 4,
lazy_storage_diff 3, storage_description 2, michelson_v1_primitives 1.
There is no gain for Irmin in this attempt's category.

Main subsequently ran CHECK4 against all410 fixed inputs: exit0,316 protocol
gains,0 Irmin gains,0 relation losses,0 unexplained changes,45052 rows.
The candidate digest remains
`9ab4e0b13457247fb93dc83bf80323fcc5cec67866a18f56995ac0ec4a20867e`.
The immutable run report is in `attempt3-candidate-mV2SB6/` in the loop directory.
Its `retention_authorized` field remains false, as intended.

Complete paired preservation tests, exact self attribution,
roster review/QA and exact-head CI remain separate required gates. No general
0CFA, functor-instance analysis or whole-program soundness is claimed.
