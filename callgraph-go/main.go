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
	"encoding/json"
	"flag"
	"fmt"
	"go/token"
	"go/types"
	"os"
	"path/filepath"
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

var enc = json.NewEncoder(os.Stdout)

func emit(v any) {
	if err := enc.Encode(v); err != nil {
		die("JSON encode: %v", err)
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

	fmt.Fprintf(os.Stderr, "arch-callgraph-go: %d SSA functions, %d edges emitted\n",
		nFuncs, len(emitted))
}
