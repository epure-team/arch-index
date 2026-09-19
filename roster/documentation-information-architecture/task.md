# Roster intake — documentation information architecture

## Objective

Prepare a small, language-agnostic documentation architecture before rewriting
the README. It must make arch-index understandable to a first-time reviewer or
AI-assisted project maintainer without hiding its explicit soundness limits.

## Observed problem

The README mixes three ingestion paths, OCaml/CMT specifics, advanced functor
contracts and more than a dozen use cases before giving a minimal outcome or
CI integration path. The individual docs are valuable but discovery is flat;
the product therefore reads as OCaml-shaped despite supported LSP/NDJSON paths.

## Approved staged plan

1. **Entry point:** concise product definition, capability boundary, three
   outcome-oriented quickstarts, and a use-case router. No removal of detail.
2. **CI/agent guide:** practical vibecoded-project integration, honest
   structural-slop signals, command examples, artifacts and non-claims.
3. **Language/capability pages:** a language-neutral matrix plus focused OCaml,
   Go/Rust/LSP/NDJSON pages. OCaml receives deeper CMT/functor material rather
   than defining the global navigation.

Each stage gets its own Roster review, tests for links/examples where possible,
and PR. This intake writes only the architecture and does not rewrite README.
