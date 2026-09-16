# Stage 3 self-reference calibration

The read-only 2×2 diagnostic reused the audited Stage-2 calibrator with frozen
base `60cc88be2db717b0c4727b1206ab666570585df1`, the Stage-3 ownership
manifest, independently built engines, and independently built CMT corpora.
The two post-round-2-correction runs are bit-for-bit identical on totals and
call/origin digests. They are recorded at:

- `improvement/2026-09-16-cfa-propagation/self-2x2-2263057-1789571761339/report.json`
- `improvement/2026-09-16-cfa-propagation/self-2x2-2279103-1789571807970/report.json`

| Cell | Engine | Corpus | Modules | Functions | Calls | Origins |
|---|---|---|---:|---:|---:|---:|
| A | base | base | 27 | 1082 | 6808 | 603 |
| B | Stage 3 | base | 27 | 1082 | 6810 | 603 |
| C | base | Stage 3 | 27 | 1142 | 7056 | 614 |
| D | Stage 3 | Stage 3 | 27 | 1142 | 7061 | 614 |

The Stage-3 engine changes the old corpus by two additive calls and the current
corpus by one removed/six added calls. It changes no origin on either fixed
corpus. Source growth accounts for 60 functions and eleven origins; the current
origin groups are `compare +2`, `index +1` and `option/raise +8`, with all other group
counts unchanged. The committed self-index and origin-reference observations
were refreshed to cell D; no semantic gate or ceiling was weakened.

The round-2 `Texp_let` marker correction leaves all four totals unchanged. Its
one added source line shifts later source coordinates, so its current-corpus
digests differ from the pre-correction reports; the two fresh runs above agree
exactly with each other and retain the same semantic multiset counts.

The one allowlisted assertion moved from anonymous path/line
`1708/1719:1722` to `1725/1736:1739`. The complete surrounding `split_last`
block is byte-identical at the frozen base and current source: the impossible
empty case remains under the same preceding `Some (_ :: _ as segs)` proof.
Only that existing x1 exemption coordinate was moved; no exemption was added.

After a full rebuild (required so the self-index corpus cannot reuse stale
CMTs), the exact self-index smoke passes at `27/1142/7061`, and the authentic
origin consumer is held at `27/1142/7061/614` with zero reference delta and its
unchanged `UNKNOWN` policy verdict.
