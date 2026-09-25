// screenreader-mcp tools -- tests for the wire binding generator.
// Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
// White-box because the generator's `run` is unexported.
// testdata/contract.json holds constructs the real schema lacks, since the drift check only sees today's schema.
package main

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

const (
	fixtureSchema = "testdata/contract.json"
	goldenOutput  = "testdata/expected.go.txt"
)

func generateFixture(t *testing.T) string {
	t.Helper()
	out := filepath.Join(t.TempDir(), "fixture.go")
	if err := run(fixtureSchema, out, "fixture"); err != nil {
		t.Fatalf("generating from %s: %v", fixtureSchema, err)
	}
	produced, err := os.ReadFile(out)
	if err != nil {
		t.Fatalf("reading generated file: %v", err)
	}
	return string(produced)
}

func unaligned(source string) string {
	return strings.Join(strings.Fields(source), " ")
}

func TestGeneratedOutputMatchesTheGoldenFile(t *testing.T) {
	produced := generateFixture(t)

	want, err := os.ReadFile(goldenOutput)
	if err != nil {
		t.Fatalf("reading %s: %v", goldenOutput, err)
	}
	if produced != string(want) {
		t.Errorf(
			"generated output differs from %s.\n"+
				"If the change is intended, regenerate the golden file:\n"+
				"  go -C server/tools/wiregen run . -schema %s -out %s -package fixture\n\n"+
				"--- got ---\n%s",
			goldenOutput, fixtureSchema, goldenOutput, produced,
		)
	}
}

func TestAnOptionalNullableFieldIsASinglePointer(t *testing.T) {
	produced := generateFixture(t)

	if strings.Contains(produced, "**") {
		t.Errorf("generated output contains a double pointer:\n%s", produced)
	}
	if !strings.Contains(unaligned(produced), "OptionalNullable *int `json:\"optionalNullable,omitempty\"`") {
		t.Error("an optional, nullable integer did not come out as a single pointer with omitempty")
	}
}

func TestARequiredNullableFieldIsNotOmitted(t *testing.T) {
	produced := generateFixture(t)

	if !strings.Contains(unaligned(produced), "RequiredNullable *string `json:\"requiredNullable\"`") {
		t.Error("a required, nullable string was not emitted as a pointer without omitempty")
	}
}

func TestOpenShapesBecomeRawJSON(t *testing.T) {
	produced := generateFixture(t)

	for _, want := range []string{
		"Opaque json.RawMessage `json:\"opaque\"`",
		"Bag json.RawMessage `json:\"bag\"`",
	} {
		if !strings.Contains(unaligned(produced), want) {
			t.Errorf("missing %q -- an open shape was given a concrete type", want)
		}
	}
}

func TestTheProtocolVersionComesFromTheSchema(t *testing.T) {
	produced := generateFixture(t)

	if !strings.Contains(produced, "const ProtocolVersion = 7") {
		t.Error("the fixture's protocolVersion 7 did not reach the generated constant")
	}
}

func TestAnUnnamedEnumFailsTheGenerator(t *testing.T) {
	schema := filepath.Join(t.TempDir(), "unnamed_enum.json")
	contents := `{
		"protocolVersion": 1,
		"$defs": {
			"Thing": {
				"type": "object",
				"properties": {
					"colour": {"type": "string", "enum": ["red", "green"]}
				},
				"required": ["colour"],
				"additionalProperties": true
			}
		},
		"commands": {}
	}`
	if err := os.WriteFile(schema, []byte(contents), 0o644); err != nil {
		t.Fatalf("writing the fixture: %v", err)
	}

	err := run(schema, filepath.Join(t.TempDir(), "out.go"), "fixture")

	if err == nil {
		t.Fatal("an enum with no Go type name was accepted; it must fail loudly")
	}
	if !strings.Contains(err.Error(), "enumNames") {
		t.Errorf("error %q does not say where to add the name", err)
	}
}

func TestLeadingInitialismsAreCapitalised(t *testing.T) {
	produced := generateFixture(t)

	for _, want := range []string{"ID int", "OK bool", "NVDALogPath string"} {
		if !strings.Contains(unaligned(produced), want) {
			t.Errorf("missing %q -- a leading initialism was not spelled in caps", want)
		}
	}
}

func TestGeneratedOutputIsFormatted(t *testing.T) {
	produced := generateFixture(t)

	if strings.Contains(produced, "\t \t") || strings.Contains(produced, " \n") {
		t.Error("generated output carries stray whitespace; format.Source did not run")
	}
	if !strings.HasSuffix(produced, "}\n") {
		t.Error("generated output does not end in a single newline after the last declaration")
	}
}
