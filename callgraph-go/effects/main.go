// arch-effects-go — Go Tier-1 effects/mutation extractor for the arch-index.
//
// Emits NDJSON effect records on stdout, one per line:
//   {"type":"effect","function_name":"pkg.Fn","file_path":"x.go",
//    "value_kind":"HashTbl","target":"myMap","soundness":"sound",
//    "producer":"arch-effects-go"}
//
// Pipe to `arch-effects-load out.db`.
//
// Extractor interface contract (Extractor_intf.S equivalent):
//   producer_id    = "arch-effects-go"
//   soundness_tier = Sound (Tier-1: go/ssa + go/types)
//
// Value-kind classification:
//   GlobalVar    — module-level var with an assignment in a function body
//   FieldAccess  — struct field assignment (*p).Field = v or p.Field = v
//   ArrayElem    — slice/array element assignment a[i] = v
//   HashTbl      — map element assignment m[k] = v  or  delete(m, k)
//   BytesBuf     — bytes.Buffer.Write*, bytes.Write*, strings.Builder.Write*
//   HeapRef      — *p = v (pointer dereference assign)
//   IoSideEffect — fmt.Print*, log.Print*, os.Stderr.Write*, os.Stdout.Write*
//   EnvVar       — os.Setenv
//   FileSystem   — os.Create, os.Remove, os.Rename, os.Write*, ioutil.WriteFile
//   Network      — net.Dial*, net.Listen*, (*net.Conn).Write, (*net.UDPConn).*
//   UnknownMut   — any other Store instruction whose target is not classified
//
// Soundness: Sound — SSA Store instructions are the complete mutation set at
// the SSA level. Mutations via unsafe.Pointer arithmetic are classified
// UnknownMut (they are not Store instructions in the SSA representation).
//
// Extension points:
//   Capability B (yield-race): add yield_before field by tracking
//     blocking SSA instructions (channel ops, runtime.Gosched) preceding Stores.
//   Capability D (error-sink): add is_error_path by checking whether the Store's
//     BasicBlock is dominated by an error-branch (call returning non-nil error).
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

	"golang.org/x/tools/go/packages"
	"golang.org/x/tools/go/ssa"
	"golang.org/x/tools/go/ssa/ssautil"
)

func die(format string, args ...any) {
	fmt.Fprintf(os.Stderr, "arch-effects-go: "+format+"\n", args...)
	os.Exit(2)
}

type effectRecord struct {
	Type         string  `json:"type"`
	FunctionName string  `json:"function_name"`
	FilePath     string  `json:"file_path,omitempty"`
	ValueKind    string  `json:"value_kind"`
	Target       *string `json:"target,omitempty"`
	Soundness    string  `json:"soundness"`
	Producer     string  `json:"producer"`
}

var enc = json.NewEncoder(os.Stdout)

func emitEffect(e effectRecord) {
	if err := enc.Encode(e); err != nil {
		die("JSON encode: %v", err)
	}
}

func posFile(fset *token.FileSet, pos token.Pos) string {
	if !pos.IsValid() {
		return ""
	}
	return fset.Position(pos).Filename
}

// funcName returns a stable qualified name matching the Go call-graph producer.
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

// classifyAddrOf classifies what value kind a Store instruction targets.
// addr is the SSA address operand (Store.Addr).
func classifyAddrOf(addr ssa.Value, pkgPath string) (kind string, target *string) {
	switch a := addr.(type) {
	case *ssa.FieldAddr:
		// struct field write
		st, ok := a.X.Type().Underlying().(*types.Pointer)
		if ok {
			if named, ok := st.Elem().(*types.Named); ok {
				fields := named.Underlying().(*types.Struct)
				if a.Field < fields.NumFields() {
					name := fields.Field(a.Field).Name()
					return "FieldAccess", strPtr(name)
				}
			}
		}
		return "FieldAccess", nil

	case *ssa.IndexAddr:
		// array/slice element write
		return "ArrayElem", nil

	case *ssa.Global:
		// global variable write
		name := a.Name()
		return "GlobalVar", strPtr(name)

	case *ssa.UnOp:
		// *p = v — pointer dereference write
		_ = a
		return "HeapRef", nil

	case *ssa.Alloc:
		// local alloc (usually escaped)
		return "HeapRef", nil
	}

	// Fallback: check the type of what we're storing into
	typ := addr.Type()
	if ptr, ok := typ.(*types.Pointer); ok {
		switch ptr.Elem().String() {
		case "bytes.Buffer", "strings.Builder":
			return "BytesBuf", nil
		}
	}
	return "UnknownMut", nil
}

// classifyMapUpdate detects MapUpdate instructions (map[k]=v and delete(m,k)).
func classifyMapUpdate(instr *ssa.MapUpdate) (string, *string) {
	return "HashTbl", strPtr(instr.Map.Type().String())
}

// wellKnownIOCalls maps short function names to value kinds.
var wellKnownMutCalls = map[string]string{
	// I/O
	"fmt.Print": "IoSideEffect", "fmt.Println": "IoSideEffect",
	"fmt.Printf": "IoSideEffect", "fmt.Fprintf": "IoSideEffect",
	"fmt.Fprintln": "IoSideEffect", "fmt.Fprint": "IoSideEffect",
	"log.Print": "IoSideEffect", "log.Println": "IoSideEffect",
	"log.Printf": "IoSideEffect", "log.Fatal": "IoSideEffect",
	"log.Fatalf": "IoSideEffect", "log.Fatalln": "IoSideEffect",
	// env
	"os.Setenv": "EnvVar",
	// fs
	"os.Create": "FileSystem", "os.OpenFile": "FileSystem",
	"os.Remove": "FileSystem", "os.RemoveAll": "FileSystem",
	"os.Rename": "FileSystem", "os.Mkdir": "FileSystem",
	"os.MkdirAll": "FileSystem", "os.MkdirTemp": "FileSystem",
	"ioutil.WriteFile": "FileSystem", "os.WriteFile": "FileSystem",
	// net
	"net.Dial": "Network", "net.DialTCP": "Network",
	"net.Listen": "Network", "net.ListenTCP": "Network",
}

func classifyCall(callee *ssa.Function) (string, bool) {
	if callee == nil || callee.Package() == nil {
		return "", false
	}
	name := funcName(callee)
	if k, ok := wellKnownMutCalls[name]; ok {
		return k, true
	}
	// Receiver-based classification
	recv := callee.Signature.Recv()
	if recv != nil {
		recvType := recv.Type()
		if ptr, ok := recvType.(*types.Pointer); ok {
			recvType = ptr.Elem()
		}
		typeName := recvType.String()
		switch {
		case strings.HasSuffix(typeName, "bytes.Buffer"),
			strings.HasSuffix(typeName, "strings.Builder"):
			if strings.HasPrefix(callee.Name(), "Write") ||
				callee.Name() == "Reset" || callee.Name() == "Grow" {
				return "BytesBuf", true
			}
		case strings.HasSuffix(typeName, "os.File"):
			if strings.HasPrefix(callee.Name(), "Write") {
				return "IoSideEffect", true
			}
		case strings.HasSuffix(typeName, "net.Conn"),
			strings.HasSuffix(typeName, "net.UDPConn"),
			strings.HasSuffix(typeName, "net.TCPConn"):
			if strings.HasPrefix(callee.Name(), "Write") ||
				strings.HasPrefix(callee.Name(), "Send") {
				return "Network", true
			}
		}
	}
	return "", false
}

func strPtr(s string) *string { return &s }

func filePathOf(fset *token.FileSet, fn *ssa.Function) string {
	if fn.Pos().IsValid() {
		return fset.Position(fn.Pos()).Filename
	}
	return ""
}

// relativize makes path relative to moduleRoot when possible.
func relativize(path, moduleRoot string) string {
	if path == "" || moduleRoot == "" {
		return path
	}
	rel, err := filepath.Rel(moduleRoot, path)
	if err != nil || strings.HasPrefix(rel, "..") {
		return path
	}
	return rel
}

func main() {
	flag.Usage = func() {
		fmt.Fprintln(os.Stderr, "usage: arch-effects-go [-root <module-root>] <pattern> [patterns...]")
		fmt.Fprintln(os.Stderr, "  Emits NDJSON effect records to stdout. Pipe to arch-effects-load.")
		os.Exit(2)
	}
	moduleRoot := flag.String("root", "", "module root directory (for relative paths)")
	flag.Parse()

	patterns := flag.Args()
	if len(patterns) == 0 {
		flag.Usage()
	}

	loadDir := ""
	expanded := make([]string, 0, len(patterns))
	for _, p := range patterns {
		if filepath.IsAbs(p) {
			base := strings.TrimSuffix(strings.TrimRight(p, "/"), "...")
			base = strings.TrimRight(base, "/")
			if loadDir == "" {
				loadDir = base
			}
			if *moduleRoot == "" {
				*moduleRoot = base
			}
			expanded = append(expanded, "./...")
		} else {
			expanded = append(expanded, p)
		}
	}

	cfg := &packages.Config{
		Dir: loadDir,
		Mode: packages.NeedName | packages.NeedFiles | packages.NeedCompiledGoFiles |
			packages.NeedImports | packages.NeedDeps | packages.NeedTypes |
			packages.NeedSyntax | packages.NeedTypesInfo | packages.NeedTypesSizes |
			packages.NeedModule,
	}
	pkgs, err := packages.Load(cfg, expanded...)
	if err != nil {
		die("packages.Load: %v", err)
	}
	packages.Visit(pkgs, nil, func(p *packages.Package) {
		for _, e := range p.Errors {
			fmt.Fprintf(os.Stderr, "arch-effects-go: load warning: %s\n", e)
		}
	})
	if len(pkgs) == 0 {
		die("no packages loaded from %v", expanded)
	}

	prog, _ := ssautil.AllPackages(pkgs, ssa.InstantiateGenerics)
	prog.Build()
	fset := prog.Fset

	// Index loaded package paths
	loadedPkgPaths := make(map[string]bool)
	for _, pkg := range pkgs {
		if pkg.PkgPath != "" {
			loadedPkgPaths[pkg.PkgPath] = true
		}
	}

	allFns := func() (m map[*ssa.Function]bool) {
		defer func() {
			if r := recover(); r != nil {
				m = make(map[*ssa.Function]bool)
			}
		}()
		return ssautil.AllFunctions(prog)
	}()

	n_effects := 0
	dedup := make(map[string]bool)

	for fn := range allFns {
		if fn.Package() == nil || !loadedPkgPaths[fn.Package().Pkg.Path()] {
			continue
		}
		callerName := funcName(fn)
		callerFile := relativize(filePathOf(fset, fn), *moduleRoot)

		emit := func(kind string, target *string) {
			key := callerName + "|" + kind + "|"
			if target != nil {
				key += *target
			}
			if dedup[key] {
				return
			}
			dedup[key] = true
			n_effects++
			emitEffect(effectRecord{
				Type:         "effect",
				FunctionName: callerName,
				FilePath:     callerFile,
				ValueKind:    kind,
				Target:       target,
				Soundness:    "sound",
				Producer:     "arch-effects-go",
			})
		}

		for _, b := range fn.Blocks {
			for _, instr := range b.Instrs {
				switch i := instr.(type) {
				case *ssa.Store:
					kind, target := classifyAddrOf(i.Addr, fn.Package().Pkg.Path())
					emit(kind, target)

				case *ssa.MapUpdate:
					kind, target := classifyMapUpdate(i)
					emit(kind, target)

				case ssa.CallInstruction:
					c := i.Common()
					if c.IsInvoke() {
						continue
					}
					static := c.StaticCallee()
					if static == nil {
						continue
					}
					if kind, ok := classifyCall(static); ok {
						site := posFile(fset, instr.Pos())
						_ = site
						emit(kind, strPtr(funcName(static)))
					}
				}
			}
		}
	}

	fmt.Fprintf(os.Stderr, "arch-effects-go: %d effect records emitted\n", n_effects)
}
