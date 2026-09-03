# Verified path inventory for the Tezos profile (2026-09-03)

Method: `scratchpad/cmt_paths_probe.ml` over **all 276** `.cmt` of
`proto_alpha/lib_protocol/.tezos_raw_protocol_alpha.objs/byte`, needle `Error_monad`.
Raw list: `tezos-v17-paths-seen.txt` (54 distinct paths). This is what the producer's validation
will compare the profile against, so a path absent here is a warning the profile should not
provoke without reason.

## Corrections to the profile sketched in `specs/error-channels.md`

| Sketched | Reality in proto_alpha | Action |
|---|---|---|
| `catch`, `catch_s` | **absent** (0 occurrences) | do not declare, or accept the warning |
| `catch_f` | **present exactly once** (`script_repr.ml:264`) | declare — it is the sole converter instance in the whole protocol (see oracle O-5) |
| `protect`, `error_with`, `catch_e` | absent (also absent from the V17 signature) | do not declare |
| `Result_syntax.and*`, `Lwt_result_syntax.and*` | absent | drop or accept the warning |
| `trace_eval` | present (1) | declare, `mode = add` |
| `record_trace_eval` | **present, not in the sketch** | declare, `mode = add` |

## Origins not in the sketch — would have been silently missed

- `Error_monad.Result_syntax.fail`, `…Lwt_result_syntax.fail`, `…Option_syntax.fail` —
  a `fail` alias distinct from `tzfail`, in all three syntaxes.
- `Error_monad.fail_when` / `fail_unless` (alongside `error_when` / `error_unless`) — conditional
  origins whose error literal is at **argument 2**, not 1.

## A second Tezos channel exists

`Error_monad.Option_syntax.{let*, let+, fail, return}` and
`Error_monad.Lwt_option_syntax.{let*, let*?}` are present: the protocol environment has its own
**option** channel with its own binds. The shipped profile should declare it (carrier `option`,
identity `None`) rather than leaving those binds to the built-in `option` channel, whose
`Stdlib.Option.bind` paths never appear here.

## Consequence for oracle row O-5

`Script_repr.force_bytes` is the **only** `catch_f` site in `lib_protocol`. It is therefore the
single real-world exercise of the `converters` role in the acceptance corpus: precious, and worth
keeping even though one instance is a thin sample. The fixture's own `errch_tz` converter case
carries the rest of the weight.
