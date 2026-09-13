# Existing supplemental package metadata lint debt — corrected classification

Root initially treated this as a new blocking specialist gate before searching
the existing roadmap and shipped task records. That conclusion was wrong:
`briefs/actionable-review-reports-preflight.md:23` explicitly classifies it as
non-gating debt; its intake/implementer/QA and
`briefs/report-verdict-absence-qa.md:57` retain the failure without calling it
green. The roadmap's existing baseline observation records the same decision.
This task's validated project gates do not include opam lint. No new waiver or
maintainer authority is inferred. Continue the approved task gates and preserve
this supplemental failure, rather than invent a new block or package metadata.

Root independently ran `rtk proxy opam lint arch-index.opam` in the active task
worktree after OCaml specialist handoff. Exit1, raw output:

```text
/home/mathias/dev/arch-index-worktrees/guard-division-analysis/arch-index.opam: Errors.
             error 23: Missing field 'maintainer'
           warning 25: Missing field 'authors'
           warning 35: Missing field 'homepage'
           warning 36: Missing field 'bug-reports'
           warning 68: Missing field 'license'
```

`git diff 77c7691436a716bfec503e22f1649a4303179fcc -- dune-project arch-index.opam`
exited0 with empty output: both files are unchanged from the baseline. This is not
an arch-guard regression. The selected OCaml specialist did run and surface the
lint failure; it is not a passing check or an implicitly waived project gate.

The frozen implementation manifest does not include either file. `dune-project`
declares `(generate_opam_files true)`; a correction must edit that source and let
Dune regenerate `arch-index.opam`, never hand-edit the generated file. Neither file
nor README currently declares a maintainer. Repository origin is
`git@github.com:epure-team/arch-index.git`; ownership alone is not a verified
maintainer declaration. Do not invent a maintainer contact, author or license.

Package metadata remains outside this slice; any future fix needs a verified
maintainer declaration and a dedicated scope. Optional odoc absence is separate
and is not represented as a build-docs success. No new blocker event is emitted.
