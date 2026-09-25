// screenreader-mcp tests -- the import boundaries.
// Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
// ROLE: architecture test for three import boundaries: the domain imports no adapters or MCP SDK, only
// tests import the fakes, and the conformance tier never uses the fake bridge.
// Deliberately untagged, so the boundaries are checked on every `go test`.
package architecture_test

import (
	"go/parser"
	"go/token"
	"io/fs"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

const (
	domainRoot = "../../domain"
	serverRoot = "../.."
)

var forbidden = []struct {
	fragment string
	why      string
}{
	{
		fragment: "adapters/",
		why: "the domain speaks its own vocabulary; adapters map to and from it. " +
			"An import here would put the wire contract's shape into the domain, " +
			"and adding wire v2 would then rewrite the domain.",
	},
	{
		fragment: "modelcontextprotocol",
		why: "the MCP SDK is an adapter concern. The domain must not know it is " +
			"being driven over MCP at all.",
	},
	{
		fragment: "github.com/Microsoft/go-winio",
		why:      "named pipes are an operating-system detail that belongs in a leaf.",
	},
}

func TestDomainImportsNoAdaptersAndNoSDK(t *testing.T) {
	fileSet := token.NewFileSet()

	err := filepath.WalkDir(domainRoot, func(path string, entry fs.DirEntry, err error) error {
		if err != nil {
			return err
		}
		if entry.IsDir() || !strings.HasSuffix(path, ".go") {
			return nil
		}
		file, err := parser.ParseFile(fileSet, path, nil, parser.ImportsOnly)
		if err != nil {
			return err
		}
		for _, imported := range file.Imports {
			path := strings.Trim(imported.Path.Value, `"`)
			for _, rule := range forbidden {
				if strings.Contains(path, rule.fragment) {
					t.Errorf("%s imports %q\n%s", filepath.ToSlash(entry.Name()), path, rule.why)
				}
			}
		}
		return nil
	})
	if err != nil {
		t.Fatalf("walking %s: %v", domainRoot, err)
	}
}

func TestOnlyTestsImportTheTestPackages(t *testing.T) {
	fileSet := token.NewFileSet()
	testOnlyPackages := []string{
		"screen-readers-mcp/server/fakes",
		"screen-readers-mcp/server/testsupport",
	}

	err := filepath.WalkDir(serverRoot, func(path string, entry fs.DirEntry, err error) error {
		if err != nil {
			return err
		}
		if entry.IsDir() || !strings.HasSuffix(path, ".go") || strings.HasSuffix(path, "_test.go") {
			return nil
		}
		slashed := filepath.ToSlash(path)
		if strings.Contains(slashed, "/testsupport/") || strings.Contains(slashed, "/fakes/") {
			return nil
		}

		file, err := parser.ParseFile(fileSet, path, nil, parser.ImportsOnly)
		if err != nil {
			return err
		}
		for _, imported := range file.Imports {
			importPath := strings.Trim(imported.Path.Value, `"`)
			for _, testOnly := range testOnlyPackages {
				if strings.Contains(importPath, testOnly) {
					t.Errorf(
						"%s is not a test file and imports %q.\n"+
							"Test scaffolding must never be reachable from the shipped binary; "+
							"if production code needs this behaviour, it needs a real adapter.",
						slashed, importPath,
					)
				}
			}
		}
		return nil
	})
	if err != nil {
		t.Fatalf("walking %s: %v", serverRoot, err)
	}
}

func TestTheConformanceTierCannotUseTheFakeBridge(t *testing.T) {
	const conformanceRoot = "../conformance"

	forbiddenNames := []string{"FakeBridge", "BridgeOptions"}
	checked := 0

	err := filepath.WalkDir(conformanceRoot, func(path string, entry fs.DirEntry, err error) error {
		if err != nil {
			return err
		}
		if entry.IsDir() || !strings.HasSuffix(path, ".go") {
			return nil
		}
		source, err := os.ReadFile(path)
		if err != nil {
			return err
		}
		checked++
		for _, name := range forbiddenNames {
			if strings.Contains(string(source), name) {
				t.Errorf("%s mentions %s.\n"+
					"The conformance tier's whole purpose is that the bridge on the other "+
					"end is the REAL Python one: a run that used the fake would pass while "+
					"proving nothing about the wire contract. If the real bridge cannot be "+
					"reached, the run must FAIL.",
					filepath.ToSlash(path), name)
			}
		}
		return nil
	})
	if err != nil {
		t.Fatalf("walking %s: %v", conformanceRoot, err)
	}
	if checked == 0 {
		t.Fatalf("no Go files found under %s; this rule is checking nothing", conformanceRoot)
	}
}

func TestTheDomainTreeWasActuallyWalked(t *testing.T) {
	found := 0
	err := filepath.WalkDir(domainRoot, func(path string, entry fs.DirEntry, err error) error {
		if err != nil {
			return err
		}
		if !entry.IsDir() && strings.HasSuffix(path, ".go") {
			found++
		}
		return nil
	})
	if err != nil {
		t.Fatalf("walking %s: %v", domainRoot, err)
	}
	if found == 0 {
		t.Fatalf("no Go files found under %s; the boundary test is checking nothing", domainRoot)
	}
}
