# QA scope — point-free-aliases

## Gates
```bash
eval $(opam env --switch=/home/mathias/dev/arch-index --set-switch)
dune build
dune runtest --force
```
Never `dune exec tezt/tests/main.exe` — it does not rebuild the producer.

## Behaviours to validate
| # | Behaviour | Check |
|---|---|---|
| 1 | Local alias gets an edge | fixture: `let alias = B.raiser`; `may-fail alias --channel exception` names the identity |
| 2 | No alias edge is MUST | `SELECT count(*) FROM calls WHERE edge_form='value_alias' AND kind='MUST'` → 0 |
| 3 | Marker vocabulary closed | `SELECT count(*) FROM calls WHERE edge_form IS NOT NULL AND edge_form<>'value_alias'` → 0 |
| 4 | Non-arrow RHS excluded | `let k = M.pi` → still zero outgoing edges |
| 5 | `let _ = M.g` safe | no orphan call, no crash |
| 6 | Dropped target | `kind='MAY_TOP'`, `top_reason='dropped_node'`, `edge_form='value_alias'` coexist |
| 7 | Legacy database | a database without the column answers every command, reporting no aliases |
| 8 | Flat schema | `fan-in` still works against a flat-schema database |
| 9 | fan-in exclusion | target's caller count unchanged by the alias |
| 10 | Frozen guard | `select count(*) from functions f join modules m on m.id=f.module_id where f.name like '%.%' and f.name not like '%<fun:%'` unchanged on both corpora (octez-manager: 638) |
| 11 | Every channel reported | movement reported for every channel in `comment_db_meta.error_contract`, not only the targeted one |
| 12 | Resolved-edge diff | keyed on `(caller_module, caller_name, call_site, callee_name, kind)`; a reference that stops resolving **or retargets** is a hard stop |

## Corpora
octez-manager and proto_alpha (`--build-dir=/home/mathias/dev/tezos/tezos/_build/default/src/proto_alpha/lib_protocol`, 468 modules / 14452 functions / 73588 calls, ~4 s).
