(** OCaml Tier-1 effects extractor — CMT typedtree walk.

    Implements [Extractor_intf.S] for OCaml.  Walks [Tast_iterator] over
    the typedtree in each [.cmt] file and classifies mutations:

    | OCaml construct                          | value_kind  |
    |------------------------------------------|-------------|
    | [:= e] (ref assign)                      | HeapRef     |
    | [t.field <- v] (mutable record field)    | FieldAccess |
    | [a.(i) <- v] (array element)             | ArrayElem   |
    | [Hashtbl.*] mutating ops                 | HashTbl     |
    | [Bytes.set], [Buffer.add_*]              | BytesBuf    |
    | [print_*], [Printf.printf], [output_*]   | IoSideEffect|
    | module-level [let x = ref …]             | GlobalVar   |
    | [Sys.putenv], [Unix.putenv]              | EnvVar      |
    | [open_out / write / Unix.write …]        | FileSystem  |
    | [Unix.send / recv / connect …]           | Network     |

    Soundness: [Sound] — the typedtree covers all syntactic mutations that
    survive type-checking.  External/C-stub mutations are NOT detected here
    (they would require MIR/LLVM analysis); those emit [UnknownMut] only
    when a C primitive is called whose name pattern suggests mutation.

    This extractor IS NOT responsible for:
    - transitive mutations (computed by arch-query at query time)
    - dead-code analysis (Capability C, driven by arch-query)
*)

include Extractor_intf.S
