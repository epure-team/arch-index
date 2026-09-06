#!/usr/bin/env bash
# checks/binary-provenance-invokes-driver.sh — runnable directly.
#
# Ratchet check for review-round-1's HIGH against scripts/check-binary-provenance.sh
# (CHECK-15 / AC-24 / FR-030).
#
# The defect. That guard probed four HARDCODED `_build` paths from the tree root and never
# invoked arch-mutants at all. It therefore exited 0 on a tree where the refusal it claims to
# enforce had never been written — and it had not been: locate_wrapper
# (bin/arch_mutants/arch_mutants.ml:787) and locate_impact (:875) both walk ancestor
# directories with no tree-boundary check.
#
# What this pins. Handed a tree whose DRIVER does not refuse — here a stub that exits 0 on
# every invocation, standing for exactly the pre-FR-030 driver — check-binary-provenance.sh
# must exit 1. A guard that only looks at file paths never notices, and exits 0.
#
# The stub is the point: this check does not depend on whether FR-030 is implemented in the
# real driver, only on whether the guard is capable of observing its absence.
#
# Exit: 0 = the guard invokes the driver and fails on a non-refusing one;
#       1 = it does not (the guard is vacuous again); >=2 = setup error.
set -uo pipefail

here="$(cd "$(dirname "$0")" && pwd -P)"
repo="$(cd "$here/.." && pwd -P)"
guard="$repo/scripts/check-binary-provenance.sh"
[ -x "$guard" ] || { echo "binary-provenance-invokes-driver: $guard is not executable" >&2; exit 2; }
command -v sqlite3 >/dev/null 2>&1 || { echo "binary-provenance-invokes-driver: sqlite3 is required" >&2; exit 2; }
command -v git >/dev/null 2>&1 || { echo "binary-provenance-invokes-driver: git is required" >&2; exit 2; }
for f in architecture-schema.sql mutants-schema-migration.sql; do
  [ -f "$repo/$f" ] || { echo "binary-provenance-invokes-driver: missing $repo/$f" >&2; exit 2; }
done

fake="$(mktemp -d "${TMPDIR:-/tmp}/binprov-fake-root.XXXXXX")" || { echo "binary-provenance-invokes-driver: mktemp failed" >&2; exit 2; }
trap 'rm -rf "$fake"' EXIT

mkdir -p "$fake/_build/default/bin/arch_mutants" || { echo "binary-provenance-invokes-driver: cannot lay out the fake root" >&2; exit 2; }
# A driver with no tree-boundary check: it accepts everything, exactly like the pre-FR-030 one.
cat > "$fake/_build/default/bin/arch_mutants/arch_mutants.exe" <<'STUB'
#!/bin/sh
# Stands in for a driver that has no FR-030 refusal. `plan --format json` must still
# produce a file the guard's fixture builder can write; everything else simply succeeds.
exit 0
STUB
chmod +x "$fake/_build/default/bin/arch_mutants/arch_mutants.exe"
cp "$repo/architecture-schema.sql" "$repo/mutants-schema-migration.sql" "$fake/" \
  || { echo "binary-provenance-invokes-driver: cannot copy the schemas" >&2; exit 2; }
[ -x "$fake/_build/default/bin/arch_mutants/arch_mutants.exe" ] \
  || { echo "binary-provenance-invokes-driver: the stub driver is not executable" >&2; exit 2; }

# Run the guard AGAINST the fake root, from inside it, so a path-only guard sees a tree whose
# own _build is the one it resolves and reports a clean zero.
out="$(cd "$fake" && "$guard" "$fake" 2>&1)"; code=$?
if [ "$code" -eq 1 ]; then
  echo "binary-provenance-invokes-driver: PASS — the guard ran the driver and refused a non-refusing one."
  exit 0
fi
echo "binary-provenance-invokes-driver: FAIL — expected exit 1 against a driver with no FR-030 refusal; got exit $code" >&2
printf '%s\n' "$out" | sed 's/^/  | /' >&2
if [ "$code" -eq 0 ]; then
  echo "  The guard passed a tree whose driver never refuses, which means it is not invoking the" >&2
  echo "  driver at all — the vacuity this check exists to prevent." >&2
fi
exit 1
