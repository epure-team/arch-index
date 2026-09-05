#!/usr/bin/env bash
# check-status-provenance.sh — CHECK-7 / AC-10 / FR-013.
#
# No report, view or JSON output may expose an engine status without the selection
# provenance that qualifies it, IN THE SAME RECORD.
#
# Why the record and not the page. A bounded SURVIVED read without its provenance is a
# false accusation against a test that may never have run, and a provenance printed once
# in a header does not travel with the row a reader copies into a bug report. So this
# checks the enclosing record, not the file.
#
# What it inspects, stated so a reader knows what it does NOT cover:
#   (a) JSON emitters — every ``Assoc [ ... ]`` literal in bin/arch_mutants/. If the record
#       carries ("engine_status", …) or ("published_verdict", …) it must also carry
#       ("selection_provenance", …).
#   (b) stdout TEXT emitters — every Printf.printf statement that renders a stored status
#       (status_to_string / engine_status / a run row's o_status or .status). It must name a
#       provenance in the same statement, whose extent is the printf line plus every line
#       indented deeper than it.
#
# Two deliberate exclusions, named rather than left for a reader to discover:
#   * Diagnostics on stderr are refusals, not records. A message naming a status it REFUSES
#     to interpret is not publishing a verdict about it.
#   * `arch-mutants report` emits ("status", …) read straight out of the ENGINE's own report
#     file. That is not a `mutant_runs` row, there is no campaign behind it and therefore no
#     selection_provenance to accompany it — FR-013 constrains `engine_status`, the stored
#     column, which is why the key regex names it rather than any field called "status".
#
# Usage:  scripts/check-status-provenance.sh [dir]     (default: bin/arch_mutants)
# Exit:   0 = no emitter publishes a status without its provenance
#         1 = at least one does (each is named, with file:line)
#         2 = harness error (no directory, no files, no awk)

set -uo pipefail

DIR="${1:-}"
if [ -z "$DIR" ]; then
  ROOT="$(git rev-parse --show-toplevel 2>/dev/null)"
  [ -n "$ROOT" ] || { echo "check-status-provenance: cannot determine tree root" >&2; exit 2; }
  DIR="$ROOT/bin/arch_mutants"
fi
[ -d "$DIR" ] || { echo "check-status-provenance: no such directory: $DIR" >&2; exit 2; }
command -v awk >/dev/null 2>&1 || { echo "check-status-provenance: awk is required" >&2; exit 2; }

FILES=$(find "$DIR" -name '*.ml' -type f | sort)
[ -n "$FILES" ] || { echo "check-status-provenance: no .ml files under $DIR" >&2; exit 2; }

hits=0
records=0
statements=0

for f in $FILES; do
  out=$(awk '
    # Strip OCaml string literals before counting brackets, so a "[" inside a message
    # cannot unbalance a record. Comments are left alone: a status key inside a comment
    # is not an emitter, and the key regexes below require the OCaml tuple syntax.
    function strip(l,   r) { r = l; gsub(/"[^"]*"/, "\"\"", r); return r }

    function indent_of(l,   r) { r = l; sub(/[^ \t].*$/, "", r); return length(r) }

    # Close the statement under construction and judge it.
    function flush(   renders_status, names_prov) {
      if (!instmt) return
      nstmt++
      renders_status = (sbuf ~ /status_to_string/ || sbuf ~ /engine_status/ \
                        || sbuf ~ /m\.status/ || sbuf ~ /o_status/)
      names_prov = (sbuf ~ /provenance/)
      if (renders_status && !names_prov)
        printf "%s:%d: a stdout emitter renders a status without naming its provenance\n", FILENAME, sstart
      instmt = 0; sbuf = ""
    }

    BEGIN { depth = 0; start = 0; buf = ""; nrec = 0; nstmt = 0 }

    {
      raw = $0
      s = strip(raw)

      # ---- (a) JSON records -------------------------------------------------
      if (depth == 0 && raw ~ /`Assoc/) {
        depth = 0; start = NR; buf = ""
        inrec = 1
      }
      if (inrec) {
        buf = buf "\n" raw
        n = gsub(/\[/, "[", s); m = gsub(/\]/, "]", s)
        depth += n - m
        if (depth <= 0 && raw ~ /\]/) {
          nrec++
          has_status = (buf ~ /\("engine_status"/ || buf ~ /\("published_verdict"/)
          has_prov   = (buf ~ /"selection_provenance"/)
          if (has_status && !has_prov)
            printf "%s:%d: a JSON record carries a status without selection_provenance\n", FILENAME, start
          inrec = 0; depth = 0; buf = ""
        }
      }

      # ---- (b) stdout text emitters -----------------------------------------
      # The extent of a statement is INDENTATION, not paren balance. A printf whose
      # first line happens to close its own parens —
      #     Printf.printf "%s" (String.uppercase_ascii m.status)
      #       (MDb.provenance_to_string provenance) ...
      # — balances at the end of line one while its provenance argument is still to
      # come, so a paren-balance rule cuts the statement in half and reports a false
      # hit on correct code. It did, on this very file, before this comment existed.
      if (instmt) {
        if (raw ~ /^[ \t]*$/ || indent_of(raw) <= sindent) {
          flush()
        } else {
          sbuf = sbuf "\n" raw
        }
      }
      if (!instmt && raw ~ /Printf\.printf/) {
        instmt = 1; sstart = NR; sindent = indent_of(raw); sbuf = raw
      }
    }
    END { flush(); printf "#counts\t%d\t%d\n", nrec, nstmt }
  ' "$f")

  counts=$(printf '%s\n' "$out" | grep '^#counts' || true)
  bad=$(printf '%s\n' "$out" | grep -v '^#counts' | grep -v '^$' || true)
  records=$((records + $(printf '%s' "$counts" | cut -f2)))
  statements=$((statements + $(printf '%s' "$counts" | cut -f3)))
  if [ -n "$bad" ]; then
    printf '%s\n' "$bad"
    hits=$((hits + $(printf '%s\n' "$bad" | wc -l)))
  fi
done

echo "check-status-provenance: inspected $records JSON record(s) and $statements stdout emitter(s) under $DIR"
if [ "$hits" -gt 0 ]; then
  echo "check-status-provenance: FAIL — $hits emitter(s) publish a status with no provenance beside it" >&2
  exit 1
fi
# A zero that says what would have made it non-zero: an `Assoc carrying ("engine_status", …)
# or ("published_verdict", …) with no ("selection_provenance", …) in the same brackets, or a
# Printf.printf rendering a run row's status without a provenance in the same call.
echo "check-status-provenance: PASS — 0 offending emitter(s). One would have been an \`Assoc"
echo "  carrying a status key with no selection_provenance key inside the same brackets, or a"
echo "  Printf.printf rendering a stored status with no provenance in the same statement."
exit 0
