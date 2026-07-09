// arch-callgraph-go — Go Tier-1 call-graph producer for the arch-index edge-kind contract.
//
// Emits NDJSON function+call records on stdout, one per line:
//   {"type":"function","name":"pkg.Fn","file_path":"x.go","exported":true}
//   {"type":"call","caller_name":"pkg.Fn","caller_file":"x.go","callee_name":"pkg.Gn",
//    "callee_file":"y.go","call_site":"x.go:42","kind":"MUST|MAY_ENUMERATED|MAY_TOP"}
//
// Pipe to `arch-load out.db` → `arch-query out.db unreachable A B` (sound over-approx).
//
// Kind assignment (FR-004 of SPEC-sound-callgraph.md):
//   MUST           — static call with uniquely-resolved callee (edge.Site.Common().StaticCallee()!=nil)
//   MAY_ENUMERATED — dynamic call (interface/func-value) where CHA enumerated a finite candidate set
//   MAY_TOP        — soundiness hole: reflect.Value.Call*, cgo/external, plugin.Open, or any dynamic
//                    call CHA resolves to 0 candidates. Emitted as synthetic edge to "*TOP*".
//
// Soundiness caveats (Livshits CACM 2015 — "soundy not sound"):
//   Anchored (caught): reflect.Value.Call*, reflect.MakeFunc, plugin.Open, cgo/external.
//   NOT anchored (undetected): //go:linkname (hidden incoming edges from out-of-scope callers),
//   asm blocks, RawSyscall (kernel, not Go), unsafe.Pointer fn-pointer tricks, plugin.Lookup.
//   For modules that rely on go:linkname for inter-package dispatch, unreachability verdicts
//   should be treated as best-effort, not ground truth.
package main

import (
	"bufio"
	"encoding/json"
	"flag"
	"fmt"
	"go/token"
	"go/types"
	"os"
	"path/filepath"
	"sort"
	"strings"

	"golang.org/x/tools/go/callgraph"
	"golang.org/x/tools/go/callgraph/cha"
	"golang.org/x/tools/go/packages"
	"golang.org/x/tools/go/ssa"
	"golang.org/x/tools/go/ssa/ssautil"
)

func die(format string, args ...any) {
	fmt.Fprintf(os.Stderr, "arch-callgraph-go: "+format+"\n", args...)
	os.Exit(2)
}

// wellKnownTop: keys are in funcName() format (shortPkg.(Recv).Method or shortPkg.Func).
// These are known soundiness holes — even when CHA resolves them statically, the call could
// invoke arbitrary code at runtime; reclassify to MAY_TOP so downstream UNKNOWN propagates.
var wellKnownTop = map[string]bool{
	"reflect.(Value).Call":         true,
	"reflect.(Value).CallSlice":    true,
	"reflect.(Value).Method":       true,
	"reflect.(Value).MethodByName": true,
	"reflect.MakeFunc":             true,
	"plugin.Open":                  true,
}

type funcRecord struct {
	Type     string `json:"type"`
	Name     string `json:"name"`
	FilePath string `json:"file_path"`
	Exported bool   `json:"exported"`
}

type callRecord struct {
	Type       string  `json:"type"`
	CallerName string  `json:"caller_name"`
	CallerFile string  `json:"caller_file,omitempty"`
	CalleeName string  `json:"callee_name"`
	CalleeFile *string `json:"callee_file"`
	CallSite   string  `json:"call_site,omitempty"`
	Kind       string  `json:"kind"`
}

// Records are buffered and emitted in a deterministic sorted order at the end,
// so the NDJSON output is reproducible regardless of Go map iteration order
// (which is randomised). The DB content was always order-independent, but a
// stable byte stream is required for reproducible producers and goldens.
type bufferedRec struct {
	key  string
	line string
}

var outBuf []bufferedRec

func recSortKey(v any) string {
	switch r := v.(type) {
	case funcRecord:
		return "0\x00" + r.Name
	case callRecord:
		return "1\x00" + r.CallerName + "\x00" + r.CalleeName + "\x00" + r.CallSite
	default:
		return "2"
	}
}

func emit(v any) {
	b, err := json.Marshal(v)
	if err != nil {
		die("JSON encode: %v", err)
	}
	outBuf = append(outBuf, bufferedRec{key: recSortKey(v), line: string(b)})
}

// flushOut writes all buffered records to stdout in a stable order (functions
// before calls, then by name/edge), producing deterministic NDJSON.
func flushOut() {
	// Sort by key, then by the full marshaled line as a tie-breaker, so records
	// that share a key (e.g. two same-named functions in different files) still
	// have a deterministic order — a stable sort alone would preserve the
	// randomised map insertion order for equal keys.
	sort.Slice(outBuf, func(i, j int) bool {
		if outBuf[i].key != outBuf[j].key {
			return outBuf[i].key < outBuf[j].key
		}
		return outBuf[i].line < outBuf[j].line
	})
	w := bufio.NewWriter(os.Stdout)
	defer w.Flush()
	for _, r := range outBuf {
		w.WriteString(r.line)
		w.WriteByte('\n')
	}
}

func posStr(fset *token.FileSet, pos token.Pos) string {
	if !pos.IsValid() {
		return ""
	}
	p := fset.Position(pos)
	return fmt.Sprintf("%s:%d", p.Filename, p.Line)
}

// funcName returns a stable qualified name: shortPkg.(Recv).Method or shortPkg.Func.
// "short" = last path component, e.g. "reflect" from "golang.org/x/tools/go/...".
func funcName(fn *ssa.Function) string {
	if fn.Package() == nil {
		return fn.Name()
	}
	pkgPath := fn.Package().Pkg.Path()
	parts := strings.Split(pkgPath, "/")
	shortPkg := parts[len(parts)-1]

	recv := ""
	if fn.Signature.Recv() != nil {
		t := fn.Signature.Recv().Type()
		if ptr, ok := t.(*types.Pointer); ok {
			t = ptr.Elem()
		}
		if named, ok := t.(*types.Named); ok {
			recv = "(" + named.Obj().Name() + ")."
		}
	}
	return shortPkg + "." + recv + fn.Name()
}

// filePath returns the source file of an SSA function (best-effort).
func filePath(fset *token.FileSet, fn *ssa.Function) string {
	if fn.Pos().IsValid() {
		return fset.Position(fn.Pos()).Filename
	}
	for _, b := range fn.Blocks {
		for _, instr := range b.Instrs {
			if p := instr.Pos(); p.IsValid() {
				return fset.Position(p).Filename
			}
		}
	}
	return ""
}

func isExternalCGO(callee *ssa.Function) bool {
	return callee != nil && callee.Package() != nil &&
		callee.Package().Pkg.Path() == "C"
}

func isWellKnownTop(callee *ssa.Function) bool {
	return callee != nil && wellKnownTop[funcName(callee)]
}

// alwaysExec returns the set of basic blocks that lie on EVERY execution path
// from the function entry to a terminal (return/panic) block — i.e. the blocks
// that post-dominate the entry. A call in such a block runs on every execution
// of the function (dominance); a call in an if/switch/loop arm does not.
//
// This makes the Go producer's MUST edges execution-sound, matching the OCaml
// backend: a uniquely-resolved static call is MUST only when it always runs,
// otherwise it is demoted to MAY_TOP (recorded, never dropped, never a false
// MUST). MUST = block post-dominates entry (Ferrante-Ottenstein-Warren control
// dependence; post-dominators = dominators on the reversed CFG).
//
// Computed by the standard iterative post-dominance fixpoint over a CFG whose
// terminal blocks (no successors: return/panic) flow to one virtual exit node.
// If the function has no terminal block (e.g. `for {}`), nothing is guaranteed
// to complete, so the result is empty (all calls demote — sound, conservative).
func alwaysExec(fn *ssa.Function) map[*ssa.BasicBlock]bool {
	result := make(map[*ssa.BasicBlock]bool)
	n := len(fn.Blocks)
	if n == 0 {
		return result
	}
	idx := make(map[*ssa.BasicBlock]int, n)
	for i, b := range fn.Blocks {
		idx[b] = i
	}
	exit := n // virtual exit node index
	succ := make([][]int, n)
	hasExit := false
	for i, b := range fn.Blocks {
		if len(b.Succs) == 0 { // terminal (return/panic) → virtual exit
			succ[i] = []int{exit}
			hasExit = true
		} else {
			for _, s := range b.Succs {
				succ[i] = append(succ[i], idx[s])
			}
		}
	}
	if !hasExit {
		return result
	}
	// pdom[i]: set of nodes (0..n, where n = exit) that post-dominate block i.
	// Backward dataflow: pdom[i] = {i} ∪ (∩_{s ∈ succ[i]} pdom[s]); pdom[exit] = {exit}.
	pdom := make([][]bool, n+1)
	for i := 0; i < n; i++ {
		pdom[i] = make([]bool, n+1)
		for k := range pdom[i] {
			pdom[i][k] = true // initialise to full set, then intersect down
		}
	}
	pdom[exit] = make([]bool, n+1)
	pdom[exit][exit] = true
	for changed := true; changed; {
		changed = false
		for i := 0; i < n; i++ {
			next := make([]bool, n+1)
			for k := range next {
				next[k] = true
			}
			for _, s := range succ[i] {
				for k := 0; k <= n; k++ {
					next[k] = next[k] && pdom[s][k]
				}
			}
			next[i] = true
			for k := 0; k <= n; k++ {
				if next[k] != pdom[i][k] {
					changed = true
					break
				}
			}
			pdom[i] = next
		}
	}
	// Blocks post-dominating the entry (block 0) are always executed.
	for j := 0; j < n; j++ {
		if pdom[0][j] {
			result[fn.Blocks[j]] = true
		}
	}
	return result
}

// alwaysExecCache memoises alwaysExec per function.
type alwaysExecCache struct {
	m map[*ssa.Function]map[*ssa.BasicBlock]bool
}

func newAlwaysExecCache() *alwaysExecCache {
	return &alwaysExecCache{m: make(map[*ssa.Function]map[*ssa.BasicBlock]bool)}
}

// runsAlways reports whether the given call site block runs on every execution
// of fn. A nil block or unknown function is treated as NOT always-run (sound).
func (c *alwaysExecCache) runsAlways(fn *ssa.Function, blk *ssa.BasicBlock) bool {
	if fn == nil || blk == nil {
		return false
	}
	set, ok := c.m[fn]
	if !ok {
		set = alwaysExec(fn)
		c.m[fn] = set
	}
	return set[blk]
}

// scanForTopAnchors scans SSA instructions directly for calls to wellKnownTop functions.
// Belt-and-suspenders for cases where the CHA traversal might miss a static call.
// Uses emitted (shared with the edge visitor) so duplicates are suppressed.
func scanForTopAnchors(fset *token.FileSet, prog *ssa.Program, emitted map[string]bool) {
	var null *string
	// Wrap AllFunctions call to recover from TypeParam panics (generics in x/tools v0.46+).
	allFns := func() (m map[*ssa.Function]bool) {
		defer func() {
			if r := recover(); r != nil {
				fmt.Fprintf(os.Stderr, "arch-callgraph-go: scanForTopAnchors AllFunctions panic (generics): %v — skipping top-anchor scan\n", r)
				m = make(map[*ssa.Function]bool)
			}
		}()
		return ssautil.AllFunctions(prog)
	}()
	for fn := range allFns {
		if fn.Package() == nil {
			continue
		}
		callerName := funcName(fn)
		for _, b := range fn.Blocks {
			for _, instr := range b.Instrs {
				call, ok := instr.(ssa.CallInstruction)
				if !ok {
					continue
				}
				c := call.Common()
				if c.IsInvoke() {
					continue
				}
				static := c.StaticCallee()
				if static == nil || (!isWellKnownTop(static) && !isExternalCGO(static)) {
					continue
				}
				site := posStr(fset, instr.Pos())
				key := callerName + "→*TOP*@" + site
				if emitted[key] {
					continue
				}
				emitted[key] = true
				emit(callRecord{
					Type:       "call",
					CallerName: callerName,
					CallerFile: filePath(fset, fn),
					CalleeName: "*TOP*",
					CalleeFile: null,
					CallSite:   site,
					Kind:       "MAY_TOP",
				})
			}
		}
	}
}

func main() {
	flag.Usage = func() {
		fmt.Fprintln(os.Stderr, "usage: arch-callgraph-go [-tests] <pattern> [patterns...]")
		fmt.Fprintln(os.Stderr, "  patterns: Go import patterns (./..., pkg/path, /abs/module/root...)")
		fmt.Fprintln(os.Stderr, "  Emits NDJSON to stdout. Pipe to arch-load.")
		os.Exit(2)
	}
	withTests := flag.Bool("tests", false, "include test functions")
	flag.Parse()

	patterns := flag.Args()
	if len(patterns) == 0 {
		flag.Usage()
	}

	// If patterns is a single absolute directory path (module root), set cfg.Dir to it
	// and use "./..." as the load pattern — packages.Load resolves patterns relative to Dir.
	loadDir := ""
	expanded := make([]string, 0, len(patterns))
	for _, p := range patterns {
		if filepath.IsAbs(p) {
			// Strip trailing /... if user typed it; we re-add it below.
			base := strings.TrimSuffix(strings.TrimRight(p, "/"), "...")
			base = strings.TrimRight(base, "/")
			if loadDir == "" {
				loadDir = base
			}
			expanded = append(expanded, "./...")
		} else {
			expanded = append(expanded, p)
		}
	}

	cfg := &packages.Config{
		Dir: loadDir, // empty string = CWD, which is correct for relative patterns
		Mode: packages.NeedName | packages.NeedFiles | packages.NeedCompiledGoFiles |
			packages.NeedImports | packages.NeedDeps | packages.NeedTypes |
			packages.NeedSyntax | packages.NeedTypesInfo | packages.NeedTypesSizes |
			packages.NeedModule,
		Tests: *withTests,
	}

	pkgs, err := packages.Load(cfg, expanded...)
	if err != nil {
		die("packages.Load: %v", err)
	}

	packages.Visit(pkgs, nil, func(p *packages.Package) {
		for _, e := range p.Errors {
			// Warn but don't abort: partial programs give soundy (over-approximate) graphs.
			fmt.Fprintf(os.Stderr, "arch-callgraph-go: load warning: %s\n", e)
		}
	})
	if len(pkgs) == 0 {
		die("no packages loaded from %v — check the module root / pattern", expanded)
	}

	prog, ssaPkgs := ssautil.AllPackages(pkgs, ssa.InstantiateGenerics)
	prog.Build()
	fset := prog.Fset

	// Index loaded (user) package paths to filter function records.
	loadedPkgPaths := make(map[string]bool)
	for _, p := range ssaPkgs {
		if p != nil {
			loadedPkgPaths[p.Pkg.Path()] = true
		}
	}

	// allFunctionsRecovering wraps ssautil.AllFunctions to recover from panics caused by
	// uninstantiated generic types (ForEachElement *types.TypeParam assertion in x/tools).
	// Falls back to iterating pkg.Members when RuntimeTypes() panics.
	allFunctionsRecovering := func(prog *ssa.Program) (fns map[*ssa.Function]bool, panicVal any) {
		defer func() { panicVal = recover() }()
		return ssautil.AllFunctions(prog), nil
	}

	allFns, panicVal := allFunctionsRecovering(prog)
	if panicVal != nil {
		fmt.Fprintf(os.Stderr, "arch-callgraph-go: AllFunctions panic (generics/TypeParam): %v — falling back to package-member walk\n", panicVal)
		// Fallback: collect functions by walking all package members directly.
		// This misses some reflection-reachable methods but avoids the panic.
		allFns = make(map[*ssa.Function]bool)
		for _, pkg := range prog.AllPackages() {
			for _, mem := range pkg.Members {
				if fn, ok := mem.(*ssa.Function); ok {
					allFns[fn] = true
				}
			}
		}
	}

	nFuncs := 0
	for fn := range allFns {
		nFuncs++
		if fn.Package() == nil || !loadedPkgPaths[fn.Package().Pkg.Path()] {
			continue // skip stdlib / transitive deps
		}
		emit(funcRecord{
			Type:     "function",
			Name:     funcName(fn),
			FilePath: filePath(fset, fn),
			Exported: fn.Object() != nil && fn.Object().Exported(),
		})
	}
	if nFuncs == 0 {
		fmt.Fprintf(os.Stderr, "arch-callgraph-go: WARNING — SSA built 0 functions from %v. "+
			"Try running from the module root.\n", expanded)
	}

	// chaCallGraphRecovering wraps cha.CallGraph to recover from TypeParam panics.
	chaCallGraphRecovering := func(prog *ssa.Program) (cg *callgraph.Graph, panicVal any) {
		defer func() { panicVal = recover() }()
		return cha.CallGraph(prog), nil
	}

	cg, cgPanic := chaCallGraphRecovering(prog)

	var null *string
	emitted := make(map[string]bool) // shared by edge visitor + scanForTopAnchors
	pdCache := newAlwaysExecCache()  // dominance: MUST only when the call always runs

	if cgPanic != nil {
		// CHA panicked on generics: fall back to direct SSA instruction walk.
		// MUST edges for static calls; MAY_TOP for invoke/dynamic/closure calls.
		// This is soundier than emitting nothing — we still capture the static call graph.
		fmt.Fprintf(os.Stderr, "arch-callgraph-go: cha.CallGraph panic (generics/TypeParam): %v — falling back to direct SSA instruction walk\n", cgPanic)
		for fn := range allFns {
			if fn.Package() == nil {
				continue
			}
			callerName := funcName(fn)
			callerFile := filePath(fset, fn)
			for _, b := range fn.Blocks {
				for _, instr := range b.Instrs {
					site, ok := instr.(ssa.CallInstruction)
					if !ok {
						continue
					}
					c := site.Common()
					sitePos := posStr(fset, instr.Pos())

					if c.IsInvoke() {
						// Interface method dispatch — emit as MAY_TOP (no CHA candidates).
						key := callerName + "→*TOP*@" + sitePos
						if !emitted[key] {
							emitted[key] = true
							emit(callRecord{
								Type:       "call",
								CallerName: callerName,
								CallerFile: callerFile,
								CalleeName: "*TOP*",
								CalleeFile: null,
								CallSite:   sitePos,
								Kind:       "MAY_TOP",
							})
						}
						continue
					}

					static := c.StaticCallee()
					if static == nil {
						// Func value / closure call — MAY_TOP.
						key := callerName + "→*TOP*@" + sitePos
						if !emitted[key] {
							emitted[key] = true
							emit(callRecord{
								Type:       "call",
								CallerName: callerName,
								CallerFile: callerFile,
								CalleeName: "*TOP*",
								CalleeFile: null,
								CallSite:   sitePos,
								Kind:       "MAY_TOP",
							})
						}
						continue
					}

					calleeName := funcName(static)
					kind := "MUST"
					// Dominance: MUST only if this call runs on every execution
					// of fn. A conditional/looped call with a uniquely-resolved
					// callee demotes to MAY_ENUMERATED (candidate set of one) —
					// it either calls that exact callee or nothing, so it never
					// forges a ⊤ frontier. MAY_TOP stays reserved for truly
					// unknowable targets (the reclassification below wins last).
					if !pdCache.runsAlways(fn, b) {
						kind = "MAY_ENUMERATED"
					}
					if isWellKnownTop(static) || isExternalCGO(static) {
						calleeName = "*TOP*"
						kind = "MAY_TOP"
					}

					key := callerName + "→" + calleeName + "@" + sitePos
					if !emitted[key] {
						emitted[key] = true
						var calleeFile *string
						if calleeName != "*TOP*" {
							fp := filePath(fset, static)
							if fp != "" {
								calleeFile = &fp
							} else {
								calleeFile = null
							}
						}
						emit(callRecord{
							Type:       "call",
							CallerName: callerName,
							CallerFile: callerFile,
							CalleeName: calleeName,
							CalleeFile: calleeFile,
							CallSite:   sitePos,
							Kind:       kind,
						})
					}
				}
			}
		}
	} else {
		err = callgraph.GraphVisitEdges(cg, func(edge *callgraph.Edge) error {
			caller := edge.Caller.Func
			callee := edge.Callee.Func
			if caller == nil || callee == nil || caller.Name() == "<root>" {
				return nil
			}

			callerName := funcName(caller)
			calleeName := funcName(callee)

			site := ""
			if edge.Site != nil {
				site = posStr(fset, edge.Site.Pos())
			}

			kind := "MAY_ENUMERATED"
			if edge.Site != nil && edge.Site.Common().StaticCallee() != nil {
				kind = "MUST"
				// Dominance: a uniquely-resolved static call is MUST only if it
				// runs on every execution of the caller. A call in an
				// if/switch/loop arm (block does not post-dominate entry) is
				// conditional → demote to MAY_ENUMERATED (candidate set of one:
				// it either calls that exact callee or nothing, so it never
				// forges a ⊤ frontier; unreachable stays decidable). MAY_TOP is
				// reserved for truly unknowable targets — the well-known-⊤
				// reclassification below always wins last.
				if !pdCache.runsAlways(caller, edge.Site.Block()) {
					kind = "MAY_ENUMERATED"
				}
			}

			// Reclassify known soundiness holes to MAY_TOP regardless of static resolution.
			if isWellKnownTop(callee) || isExternalCGO(callee) {
				calleeName = "*TOP*"
				kind = "MAY_TOP"
			}

			key := callerName + "→" + calleeName + "@" + site
			if emitted[key] {
				return nil
			}
			emitted[key] = true

			var calleeFile *string
			if calleeName != "*TOP*" {
				fp := filePath(fset, callee)
				if fp != "" {
					calleeFile = &fp
				} else {
					calleeFile = null
				}
			}

			emit(callRecord{
				Type:       "call",
				CallerName: callerName,
				CallerFile: filePath(fset, caller),
				CalleeName: calleeName,
				CalleeFile: calleeFile,
				CallSite:   site,
				Kind:       kind,
			})
			return nil
		})
		if err != nil {
			die("graph visit: %v", err)
		}

		// Belt-and-suspenders: scan SSA directly for wellKnownTop calls not captured above.
		scanForTopAnchors(fset, prog, emitted)
	}

	flushOut() // write buffered records in deterministic sorted order
	fmt.Fprintf(os.Stderr, "arch-callgraph-go: %d SSA functions, %d edges emitted\n",
		nFuncs, len(emitted))
}
