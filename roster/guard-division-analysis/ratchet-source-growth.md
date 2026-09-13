# Ratchet source-growth attribution

2026-09-13. Baseline77c7691436a716bfec503e22f1649a4303179fcc; product68e77df61c68f811331180abfc25293911b2f955 (current4d71800 differs only in evidence/docs). Same current extractor used to index both full-build corpora. Previous pristine 2×2 independently gave A=B396, C=D430. Existing lib/arch_index and lib/arch_tools diff is empty.

## Measured delta

Base396 → head430. All34 added rows are in newly introduced source files; every pre-existing (module path,callee name) group has the same multiplicity. No disappearing group.33 calls target compiler-libs, Unix, Digestif or Yojson; one Arch_tezt.Temp.dir call is the Tezt.Temp re-export (tezt/lib/arch_tezt.ml:20, installed tezt/tezt.ml:156 and temp.mli:50). No dependency implementation is in this indexed corpus. This is source-growth attribution, not proof all existing unresolved edges are sound.

The old pin383 already lagged the measured main baseline396 by13. Recalibration to430 retains headroom25 and the exact query. No exclusion of new files or callee families and no query/resolver changes.

## Group changes

| New source | Callee | Added rows |
| --- | --- | --- |
| lib/arch_guard/arch_guard.ml | Cmt_format.read | 1 |
| lib/arch_guard/arch_guard.ml | Digestif.SHA256.digest_string | 1 |
| lib/arch_guard/arch_guard.ml | Digestif.SHA256.to_hex | 1 |
| lib/arch_guard/arch_guard.ml | Unix.lstat | 1 |
| lib/arch_guard/arch_guard.ml | Unix.realpath | 1 |
| lib/arch_guard/arch_guard.ml | Unix.stat | 2 |
| lib/arch_guard/arch_guard.ml | Yojson.Safe.Util.to_int | 2 |
| lib/arch_guard/arch_guard.ml | Yojson.Safe.Util.to_list | 3 |
| lib/arch_guard/arch_guard.ml | Yojson.Safe.Util.to_string | 3 |
| lib/arch_guard/arch_guard.ml | Yojson.Safe.to_string | 2 |
| lib/arch_guard/guard_domain.ml | Yojson.Safe.Util.to_string | 1 |
| lib/arch_guard/guard_interpreter.ml | Envaux.reset_cache | 1 |
| lib/arch_guard/guard_interpreter.ml | Ident.same | 1 |
| lib/arch_guard/guard_interpreter.ml | Load_path.init | 1 |
| lib/arch_guard/guard_interpreter.ml | Types.get_desc | 1 |
| tezt/tests/guard_division_analysis.ml | Arch_tezt.Temp.dir | 1 |
| tezt/tests/guard_division_analysis.ml | Yojson.Safe.Util.to_int | 2 |
| tezt/tests/guard_division_analysis.ml | Yojson.Safe.Util.to_list | 1 |
| tezt/tests/guard_division_analysis.ml | Yojson.Safe.Util.to_string | 3 |
| tezt/tests/guard_division_analysis.ml | Yojson.Safe.Util.to_string_option | 2 |
| tezt/tests/guard_division_analysis.ml | Yojson.Safe.from_string | 3 |

## Individual added rows

| Call site | Caller | Callee |
| --- | --- | --- |
| lib/arch_guard/arch_guard.ml:202 | render_json | Yojson.Safe.to_string |
| lib/arch_guard/arch_guard.ml:207 | render_text | Yojson.Safe.to_string |
| lib/arch_guard/arch_guard.ml:209 | render_text | Yojson.Safe.Util.to_list |
| lib/arch_guard/arch_guard.ml:210 | render_text | Yojson.Safe.Util.to_list |
| lib/arch_guard/arch_guard.ml:221 | render_text.<fun:216:13> | Yojson.Safe.Util.to_string |
| lib/arch_guard/arch_guard.ml:221 | render_text.<fun:216:13> | Yojson.Safe.Util.to_string |
| lib/arch_guard/arch_guard.ml:222 | render_text.<fun:216:13> | Yojson.Safe.Util.to_int |
| lib/arch_guard/arch_guard.ml:222 | render_text.<fun:216:13> | Yojson.Safe.Util.to_string |
| lib/arch_guard/arch_guard.ml:225 | render_text.<fun:216:13> | Yojson.Safe.Util.to_list |
| lib/arch_guard/arch_guard.ml:226 | render_text.<fun:226:13> | Yojson.Safe.Util.to_int |
| lib/arch_guard/arch_guard.ml:66 | digest.<fun:65:62> | Digestif.SHA256.digest_string |
| lib/arch_guard/arch_guard.ml:66 | digest.<fun:65:62> | Digestif.SHA256.to_hex |
| lib/arch_guard/arch_guard.ml:72 | canonicalize.<fun:71:14> | Unix.lstat |
| lib/arch_guard/arch_guard.ml:76 | canonicalize.<fun:71:14> | Unix.realpath |
| lib/arch_guard/arch_guard.ml:82 | canonicalize.<fun:81:26> | Unix.stat |
| lib/arch_guard/arch_guard.ml:92 | read_artifact.<fun:91:15> | Unix.stat |
| lib/arch_guard/arch_guard.ml:94 | read_artifact.<fun:91:15> | Cmt_format.read |
| lib/arch_guard/guard_domain.ml:55 | of_yojson | Yojson.Safe.Util.to_string |
| lib/arch_guard/guard_interpreter.ml:111 | analyze | Load_path.init |
| lib/arch_guard/guard_interpreter.ml:113 | analyze | Envaux.reset_cache |
| lib/arch_guard/guard_interpreter.ml:19 | has_type.<fun:19:15> | Types.get_desc |
| lib/arch_guard/guard_interpreter.ml:87 | lookup.<fun:87:23> | Ident.same |
| tezt/tests/guard_division_analysis.ml:12 | register.<fun:11:6> | Arch_tezt.Temp.dir |
| tezt/tests/guard_division_analysis.ml:23 | register.<fun:11:6> | Yojson.Safe.from_string |
| tezt/tests/guard_division_analysis.ml:24 | register.<fun:11:6> | Yojson.Safe.Util.to_int |
| tezt/tests/guard_division_analysis.ml:26 | register.<fun:11:6> | Yojson.Safe.Util.to_list |
| tezt/tests/guard_division_analysis.ml:28 | register.<fun:11:6>.<fun:28:17> | Yojson.Safe.Util.to_string |
| tezt/tests/guard_division_analysis.ml:32 | register.<fun:11:6>.<fun:32:14> | Yojson.Safe.Util.to_int |
| tezt/tests/guard_division_analysis.ml:51 | register_domain.<fun:44:6> | Yojson.Safe.from_string |
| tezt/tests/guard_division_analysis.ml:53 | register_domain.<fun:44:6> | Yojson.Safe.Util.to_string |
| tezt/tests/guard_division_analysis.ml:54 | register_domain.<fun:44:6> | Yojson.Safe.Util.to_string_option |
| tezt/tests/guard_division_analysis.ml:63 | register_domain.<fun:44:6> | Yojson.Safe.from_string |
| tezt/tests/guard_division_analysis.ml:64 | register_domain.<fun:44:6> | Yojson.Safe.Util.to_string |
| tezt/tests/guard_division_analysis.ml:65 | register_domain.<fun:44:6> | Yojson.Safe.Util.to_string_option |

## Authorization and scope

Independent Terra read-only cross-check confirmed the delta at individual row
identity (source,caller,call_site,callee):0baseline-only rows,34new rows,33distinct
keys because two calls share arch_guard.ml:221. All396baseline rows preserved.
This was an implementation attribution check, not formal roster-review or QA.
After the pin-only amendment, full dune build0 and targeted ratchet test0.

User was explicitly asked whether to permit the excluded pin-file recalibration after examining the34 additional calls, retaining margin25. After asking separately about Tezos benefit (answered no measured benefit), user said « okok continue ». Resume is treated as agreement to that bounded recalibration, not permission to change the extractor, query, headroom or reference corpus. No human quiz or formal acceptance of unresolved behavior claimed. Independent review/QA and full-build gates remain required.
