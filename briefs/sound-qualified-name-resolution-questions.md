# Research questions — sound-qualified-name-resolution

> DO NOT include the task description in this file, or share it with the researcher.
> Answer each question from the code alone, blind to the intended change.

## Q1 — How does the OCaml producer map a qualified reference's module component to a source path today?
Locate every place a module name is turned into a path or an id. For each: what is the key, how is the table built, and what happens when two entries would share that key? Cite file:line.

## Q2 — What identity information does the CMT/Typedtree path actually carry for a call?
For a call written `Api.run` inside a dune-wrapped library, what exactly does the extracted `Path.t` contain? Is the owning library recoverable? What survives `include`, module alias, and functor application? Answer by inspecting the extractor and, if possible, by extracting a real `.cmt`.

## Q3 — What does the repository's own soundness contract require of an edge whose target cannot be uniquely determined?
Read the edge-kind contract and the callgraph spec. Enumerate the legal edge kinds, the exact obligation for each, and what a producer MUST do when it cannot guarantee uniqueness. Quote the normative lines.

## Q4 — Which modules end up in the index that are not real source modules?
Are dune-generated wrappers/alias modules indexed? What filter exists, what shape does it match, and what shapes does it miss? Cite the filter and give a concrete example of something that slips through.

## Q5 — What test infrastructure exists for multi-library OCaml fixtures?
Can the current test harness build a fixture project with two or more `(library ...)` stanzas? List the existing OCaml callgraph fixtures and state, for each, whether it is single- or multi-library.

## Q6 — Where else does the same keying pattern appear?
Beyond the call-resolution path, find every other site that resolves names through the same kind of table (module dependencies, type usages, queries). Are they independent instances of one pattern? Cite file:line for each.
