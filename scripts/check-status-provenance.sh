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
    # Judge one record: the keys that appear inside ITS OWN brackets, at its own nesting
    # level. Nested records are their own frames and their keys are theirs alone, which is
    # the whole point of the stack below.
    function judge_record(   b) {
      b = rbuf[top]
      nrec++
      if ((b ~ /\("engine_status"/ || b ~ /\("published_verdict"/) && b !~ /"selection_provenance"/)
        printf "%s:%d: a JSON record carries a status without selection_provenance\n", FILENAME, rstart[top]
    }

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

    BEGIN { top = 0; brdepth = 0; pending = 0; instr = 0; cdepth = 0; nrec = 0; nstmt = 0 }

    {
      raw = $0

      # ---- (a) JSON records -------------------------------------------------
      # A STACK, not a single record. The previous version opened a record only at bracket
      # depth 0, so a nested `Assoc never became a record of its own and the whole outermost
      # blob was judged as ONE. An inner record therefore inherited any selection_provenance
      # key appearing anywhere in the outer one — and deleting the provenance key from the
      # per-run record, the row a reader copies into a bug report and the exact case FR-013
      # exists for, still produced PASS. So: open a frame at EVERY `Assoc, and judge each
      # frame against the keys between its own brackets, at its own level. Keys inside a
      # nested record belong to that record and to no other.
      #
      # Strings and comments are consumed by the same scan, so a "[" in a message and a
      # "[" in a doc comment cannot unbalance the stack, and a status key written in prose
      # is not an emitter.
      i = 1; n = length(raw)
      while (i <= n) {
        c = substr(raw, i, 1); two = substr(raw, i, 2)
        if (instr) {
          if (cdepth == 0 && top > 0) rbuf[top] = rbuf[top] c
          if (c == "\\") {
            if (cdepth == 0 && top > 0) rbuf[top] = rbuf[top] substr(raw, i + 1, 1)
            i += 2; continue
          }
          if (c == "\"") instr = 0
          i++; continue
        }
        if (cdepth > 0) {
          if (two == "(*") { cdepth++; i += 2; continue }
          if (two == "*)") { cdepth--; i += 2; continue }
          if (c == "\"") { instr = 1; i++; continue }
          i++; continue
        }
        if (two == "(*") { cdepth = 1; i += 2; continue }
        if (c == "\"") { instr = 1; if (top > 0) rbuf[top] = rbuf[top] c; i++; continue }
        if (substr(raw, i, 6) == "`Assoc") {
          pending = 1; pstart = NR
          if (top > 0) rbuf[top] = rbuf[top] "`Assoc"
          i += 6; continue
        }
        if (c == "[") {
          if (pending) { top++; rstart[top] = pstart; rbuf[top] = ""; rlevel[top] = brdepth; pending = 0 }
          else if (top > 0) rbuf[top] = rbuf[top] c
          brdepth++
          i++; continue
        }
        if (c == "]") {
          brdepth--
          if (top > 0 && rlevel[top] == brdepth) { judge_record(); top-- }
          else if (top > 0) rbuf[top] = rbuf[top] c
          i++; continue
        }
        if (top > 0) rbuf[top] = rbuf[top] c
        i++
      }
      if (top > 0) rbuf[top] = rbuf[top] "\n"

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
    END {
      flush()
      # An unclosed record means the scanner lost its place; it must not be reported as
      # coverage. Judge what is left and say so, rather than dropping it silently.
      while (top > 0) {
        printf "%s:%d: UNCLOSED `Assoc record at end of file — the record scanner lost its place\n", FILENAME, rstart[top]
        judge_record(); top--
      }
      printf "#counts\t%d\t%d\n", nrec, nstmt
    }
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
