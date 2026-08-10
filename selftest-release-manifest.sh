#!/usr/bin/env bash
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"; suffix=test-platform
stage="$(mktemp -d)"; trap 'rm -rf "$stage" "$stage"-*.tar.gz' EXIT
names='arch_body_compare arch_callgraph_ocaml arch_coverage arch_coverage_load arch_curate arch_impact arch_index_cli arch_load arch_mutants arch_query arch_rules arch_serve'
for name in $names; do printf x >"$stage/$name-$suffix"; chmod 755 "$stage/$name-$suffix"; done
"$HERE/scripts/package-release" "$stage" "$suffix" "$stage-ok.tar.gz"
"$HERE/scripts/check-release-manifest" "$stage-ok.tar.gz" "$suffix"
python3 - "$stage-ok.tar.gz" "$stage" <<'PY'
import io,sys,tarfile
src_path,prefix=sys.argv[1:]
with tarfile.open(src_path) as src:
 records=[(m,src.extractfile(m).read()) for m in src.getmembers()]
def write(kind, records):
 with tarfile.open(prefix+f"-{kind}.tar.gz","w:gz") as out:
  for m,d in records: out.addfile(m,io.BytesIO(d))
write("missing",records[1:])
extra=tarfile.TarInfo("extra-test-platform"); extra.size=1; extra.mode=0o755
write("extra",records+[(extra,b"x")])
mcp=tarfile.TarInfo("arch_mcp-test-platform"); mcp.size=1; mcp.mode=0o755
write("mcp",records+[(mcp,b"x")])
mode=[(m,d) for m,d in records]
mode[0][0].mode=0o644
write("mode",mode)
PY
! "$HERE/scripts/check-release-manifest" "$stage-missing.tar.gz" "$suffix" >/dev/null 2>&1
! "$HERE/scripts/check-release-manifest" "$stage-extra.tar.gz" "$suffix" >/dev/null 2>&1
! "$HERE/scripts/check-release-manifest" "$stage-mode.tar.gz" "$suffix" >/dev/null 2>&1
! "$HERE/scripts/check-release-manifest" "$stage-mcp.tar.gz" "$suffix" >/dev/null 2>&1
echo 'selftest-release-manifest: PASS'
