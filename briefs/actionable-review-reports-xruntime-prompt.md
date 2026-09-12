Return only a JSON array of findings that the primary reviewer may have missed.
Each finding must contain severity, confidence, path, line, category, summary,
evidence, fix, fingerprint, and specialist="opencode-xruntime". Use behavioral,
reproducible claims only. Empty array is valid. Review origin/main...HEAD at HEAD
2f42297ed9f0cbf2125da0e0750eb426d863c0cd against
specs/actionable-review-reports.md and briefs/actionable-review-reports-reviewer.md.
Read every modified file in full. Focus on rule evaluator parity, CLI error exits,
producer attribution, old/malformed operand metadata, bounded site/context totals,
SARIF/JSON/HTML parity, and non-vacuous tests. Do not edit files or run Dune; the
architect currently owns the sole build lock. Scope gate already passed.
