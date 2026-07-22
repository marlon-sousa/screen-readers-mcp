// screenreader-mcp tools -- wiregen: the wire binding generator.
// Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
//
// ROLE: development tool, outside the ports-and-adapters architecture. It reads
// the published contract, specs/wire/v1/schema.json, and writes the server's
// private binding of it, server/adapters/wire/wire.gen.go.
// RUN BY: the //go:generate directive in adapters/wire/doc.go, and by the CI
// `server` job, which regenerates and then `git diff --exit-code`s -- so the
// committed binding can never drift from the published schema.
// NOT SHIPPED: it lives under tools/ rather than cmd/ so that cmd/ stays exactly
// the binaries we release.
//
// Why generation at all: spec 0013 decided that each implementation owns its own
// binding, and that what is shared between the halves is the CONTRACT, not code.
// Generating from the schema is what makes that split safe -- it replaces the
// same-bytes drift guarantee the two Python halves used to get for free.
//
// There is no test file beside this. Its correctness is checked end to end and
// continuously: the generated package must compile, its unit tests must pass,
// the drift gate must produce no diff, and 10c's conformance job proves the
// binding against the real Python bridge. A unit test of the type mapper would
// restate the mapping table in a second place.
package main

import (
	"bytes"
	"encoding/json"
	"flag"
	"fmt"
	"go/format"
	"os"
	"sort"
	"strings"
)

func main() {
	schemaPath := flag.String("schema", "../../../specs/wire/v1/schema.json", "path to the published wire schema")
	outPath := flag.String("out", "wire.gen.go", "path of the Go file to write")
	pkg := flag.String("package", "wire", "package name for the generated file")
	flag.Parse()

	if err := run(*schemaPath, *outPath, *pkg); err != nil {
		fmt.Fprintf(os.Stderr, "wiregen: %v\n", err)
		os.Exit(1)
	}
}

func run(schemaPath, outPath, pkg string) error {
	raw, err := os.ReadFile(schemaPath)
	if err != nil {
		return err
	}
	var doc document
	if err := json.Unmarshal(raw, &doc); err != nil {
		return fmt.Errorf("%s: %w", schemaPath, err)
	}
	source, err := generate(&doc, pkg, schemaPath)
	if err != nil {
		return err
	}
	formatted, err := format.Source(source)
	if err != nil {
		// Emit the unformatted source alongside the error: a syntax bug in
		// the generator is far easier to see in the text it produced.
		return fmt.Errorf("generated source does not parse: %w\n%s", err, source)
	}
	return os.WriteFile(outPath, formatted, 0o644)
}

// --- the schema, read with key order preserved --------------------------------

// document is the published schema's top level.
type document struct {
	ProtocolVersion int     `json:"protocolVersion"`
	Defs            *object `json:"$defs"`
	Commands        *object `json:"commands"`
}

// object is a JSON object that remembers the order its keys were written in.
//
// encoding/json decodes an object into a map, which loses that order, and the
// generator's output must be byte-stable for the drift gate to mean anything.
// Preserving order also keeps a generated struct's fields in the same sequence
// as the schema, so the two documents read alike.
type object struct {
	keys   []string
	values map[string]json.RawMessage
}

func (o *object) UnmarshalJSON(data []byte) error {
	dec := json.NewDecoder(bytes.NewReader(data))
	if _, err := dec.Token(); err != nil { // consume '{'
		return err
	}
	o.values = map[string]json.RawMessage{}
	for dec.More() {
		key, err := dec.Token()
		if err != nil {
			return err
		}
		name, ok := key.(string)
		if !ok {
			return fmt.Errorf("object key %v is not a string", key)
		}
		var value json.RawMessage
		if err := dec.Decode(&value); err != nil {
			return err
		}
		o.keys = append(o.keys, name)
		o.values[name] = value
	}
	_, err := dec.Token() // consume '}'
	return err
}

// Keys returns the key order as written. A nil object has none, so callers need
// no nil check.
func (o *object) Keys() []string {
	if o == nil {
		return nil
	}
	return o.keys
}

// Raw returns one member's raw JSON.
func (o *object) Raw(key string) json.RawMessage {
	if o == nil {
		return nil
	}
	return o.values[key]
}

// node is one JSON Schema fragment, in the subset this contract uses.
type node struct {
	Ref                  string          `json:"$ref"`
	Type                 string          `json:"type"`
	Enum                 []string        `json:"enum"`
	Items                *node           `json:"items"`
	Properties           *object         `json:"properties"`
	Required             []string        `json:"required"`
	AnyOf                []node          `json:"anyOf"`
	AdditionalProperties json.RawMessage `json:"additionalProperties"`
}

// --- the mapping decisions ----------------------------------------------------

// enumNames maps a schema enum's value set to the Go type it becomes.
//
// The schema spells its enums inline, so nothing in the document says what to
// call them. Rather than inventing a name from the field that happens to use an
// enum first -- which would rename types as the schema is edited -- the naming
// is an explicit decision recorded here, matching the reference implementation's
// own names (protocol.py's CaptureMode, LogLevel).
//
// An enum that is NOT in this table is a hard error rather than a fall-back to
// plain string: a new closed value set in the contract deserves a deliberate
// name, and failing the generator is how that decision gets asked for.
var enumNames = map[string]string{
	"live|silent":                "CaptureMode",
	"debug|debugwarning|info|io": "LogLevel",
	"announce|braille|config|focus|gestures|speech|state": "Capability",
}

// initialisms are the leading lowercase runs that are spelled all-caps in Go.
var initialisms = map[string]string{
	"id":   "ID",
	"ok":   "OK",
	"io":   "IO",
	"nvda": "NVDA",
	"url":  "URL",
	"json": "JSON",
	"tcp":  "TCP",
}

// enumKey is the order-independent identity of a value set.
func enumKey(values []string) string {
	sorted := append([]string(nil), values...)
	sort.Strings(sorted)
	return strings.Join(sorted, "|")
}

// exported turns a JSON member name into an exported Go identifier, spelling a
// leading initialism in caps (`id` -> `ID`, `nvdaLogPath` -> `NVDALogPath`).
func exported(name string) string {
	if name == "" {
		return ""
	}
	lead := name
	for i, r := range name {
		if r >= 'A' && r <= 'Z' {
			lead = name[:i]
			break
		}
	}
	if caps, ok := initialisms[lead]; ok {
		return caps + name[len(lead):]
	}
	return strings.ToUpper(name[:1]) + name[1:]
}

// goType maps one schema fragment to a Go type.
//
// The one rule worth stating out loud: any shape the contract deliberately
// leaves OPEN -- an empty schema, an object with no declared properties --
// becomes json.RawMessage. Those are exactly the places where reader-specific
// vocabulary rides through as opaque data (a config value, a command's params),
// and raw JSON carries them byte-for-byte without this server deciding what
// type they are.
func goType(n *node) (string, error) {
	switch {
	case n.Ref != "":
		return n.Ref[strings.LastIndex(n.Ref, "/")+1:], nil

	case len(n.AnyOf) > 0:
		var concrete []node
		nullable := false
		for _, option := range n.AnyOf {
			if option.Type == "null" {
				nullable = true
				continue
			}
			concrete = append(concrete, option)
		}
		if len(concrete) != 1 {
			// A genuine union of two concrete shapes has no faithful Go
			// spelling; carry it opaquely rather than picking one.
			return "json.RawMessage", nil
		}
		inner, err := goType(&concrete[0])
		if err != nil {
			return "", err
		}
		if nullable {
			return nullable_(inner), nil
		}
		return inner, nil

	case len(n.Enum) > 0:
		name, ok := enumNames[enumKey(n.Enum)]
		if !ok {
			return "", fmt.Errorf(
				"enum %v has no Go type name; add one to enumNames in tools/wiregen",
				n.Enum,
			)
		}
		return name, nil
	}

	switch n.Type {
	case "string":
		return "string", nil
	case "integer":
		return "int", nil
	case "number":
		return "float64", nil
	case "boolean":
		return "bool", nil
	case "array":
		if n.Items == nil {
			return "[]json.RawMessage", nil
		}
		elem, err := goType(n.Items)
		if err != nil {
			return "", err
		}
		return "[]" + elem, nil
	case "object":
		if len(n.Properties.Keys()) > 0 {
			return "", fmt.Errorf("inline object with properties is not supported; give it a $def")
		}
		return "json.RawMessage", nil
	case "":
		return "json.RawMessage", nil
	default:
		return "", fmt.Errorf("unsupported schema type %q", n.Type)
	}
}

// nullable_ makes a type able to express "absent". Slices, maps,
// json.RawMessage and anything already a pointer can, so they are left alone
// rather than becoming a pointer to something nilable.
//
// Idempotent on purpose: a field can be BOTH nullable in its schema and absent
// from the required list -- `logLevel` is exactly that -- and applying the rule
// twice must not produce a double pointer, which expresses a third state
// ("present, but null") that the contract does not have.
func nullable_(goTypeName string) string {
	if strings.HasPrefix(goTypeName, "*") ||
		strings.HasPrefix(goTypeName, "[]") ||
		strings.HasPrefix(goTypeName, "map[") ||
		goTypeName == "json.RawMessage" {
		return goTypeName
	}
	return "*" + goTypeName
}

// --- emission -----------------------------------------------------------------

func generate(doc *document, pkg, schemaPath string) ([]byte, error) {
	var b strings.Builder

	fmt.Fprintf(&b, "// Code generated by tools/wiregen from %s. DO NOT EDIT.\n",
		strings.ReplaceAll(schemaPath, "\\", "/"))
	b.WriteString(`//
// ROLE: generated adapter. The server's private binding of the published wire
// contract -- envelope types, per-command params and results, the command and
// capability constants, and the supported protocol versions. NO BEHAVIOUR
// beyond marshalling.
// IMPORTED BY: adapters/bridge only. Nothing under domain/ may import this
// package; that rule is what keeps a future wire v2 from rewriting the domain,
// and tests/architecture/imports_test.go enforces it.
//
// Regenerate with: go generate ./adapters/wire
//
// One file rather than one type per file: the one-type-per-file rule exists so
// that a human editing a type knows where it lives, and nothing here is edited
// by a human.

`)
	fmt.Fprintf(&b, "package %s\n\n", pkg)
	b.WriteString("import \"encoding/json\"\n\n")

	fmt.Fprintf(&b, "// ProtocolVersion is the wire version this binding was generated from.\nconst ProtocolVersion = %d\n\n", doc.ProtocolVersion)

	b.WriteString(`// SupportedVersions is every wire version this server accepts at handshake.
//
// A set consulted by the handshake rather than a constant compared with == at
// one call site: spec 0013 leaves the hub-versus-lockstep question open and
// keeps the choice cheap, and accepting a second version must be a change to
// data, not to control flow.
//
// A function rather than a package-level var because a slice var would be
// package-level MUTABLE state, which nothing in server/ is allowed to have.
func SupportedVersions() []int {
	return []int{ProtocolVersion}
}

// Supports reports whether this server can talk to a bridge announcing version.
func Supports(version int) bool {
	for _, supported := range SupportedVersions() {
		if version == supported {
			return true
		}
	}
	return false
}

`)

	if err := emitCommands(&b, doc); err != nil {
		return nil, err
	}
	if err := emitEnums(&b, doc); err != nil {
		return nil, err
	}
	if err := emitStructs(&b, doc); err != nil {
		return nil, err
	}
	return []byte(b.String()), nil
}

// emitCommands writes the command name constants, in the schema's own order.
func emitCommands(b *strings.Builder, doc *document) error {
	b.WriteString("// Command is a wire command name.\ntype Command string\n\n")
	b.WriteString("// The commands this contract defines (protocol.md §5).\nconst (\n")
	for _, name := range doc.Commands.Keys() {
		fmt.Fprintf(b, "\tCommand%s Command = %q\n", exported(name), name)
	}
	b.WriteString(")\n\n")
	return nil
}

// emitEnums writes each named enum type once, discovered by walking every
// fragment of the document and grouping by value set.
func emitEnums(b *strings.Builder, doc *document) error {
	values := map[string][]string{} // Go type name -> its values, in schema order
	var walk func(n *node) error
	walk = func(n *node) error {
		if len(n.Enum) > 0 && n.Type == "string" {
			name, ok := enumNames[enumKey(n.Enum)]
			if !ok {
				return fmt.Errorf(
					"enum %v has no Go type name; add one to enumNames in tools/wiregen",
					n.Enum,
				)
			}
			if _, seen := values[name]; !seen {
				values[name] = n.Enum
			}
		}
		if n.Items != nil {
			if err := walk(n.Items); err != nil {
				return err
			}
		}
		for i := range n.AnyOf {
			if err := walk(&n.AnyOf[i]); err != nil {
				return err
			}
		}
		for _, key := range n.Properties.Keys() {
			var child node
			if err := json.Unmarshal(n.Properties.Raw(key), &child); err != nil {
				return err
			}
			if err := walk(&child); err != nil {
				return err
			}
		}
		return nil
	}

	for _, name := range doc.Defs.Keys() {
		var def node
		if err := json.Unmarshal(doc.Defs.Raw(name), &def); err != nil {
			return err
		}
		if err := walk(&def); err != nil {
			return err
		}
	}

	names := make([]string, 0, len(values))
	for name := range values {
		names = append(names, name)
	}
	sort.Strings(names)

	for _, name := range names {
		fmt.Fprintf(b, "// %s is a closed value set in the wire contract.\ntype %s string\n\n", name, name)
		fmt.Fprintf(b, "// The values %s may take.\nconst (\n", name)
		for _, value := range values[name] {
			fmt.Fprintf(b, "\t%s%s %s = %q\n", name, exported(value), name, value)
		}
		b.WriteString(")\n\n")
	}
	return nil
}

// emitStructs writes one struct per $def, fields in schema order.
func emitStructs(b *strings.Builder, doc *document) error {
	for _, name := range doc.Defs.Keys() {
		var def node
		if err := json.Unmarshal(doc.Defs.Raw(name), &def); err != nil {
			return err
		}
		if def.Type != "object" {
			return fmt.Errorf("$defs.%s is not an object", name)
		}
		required := map[string]bool{}
		for _, field := range def.Required {
			required[field] = true
		}

		fmt.Fprintf(b, "// %s is the wire shape of the same name.\ntype %s struct {\n", name, name)
		for _, field := range def.Properties.Keys() {
			var prop node
			if err := json.Unmarshal(def.Properties.Raw(field), &prop); err != nil {
				return err
			}
			typeName, err := goType(&prop)
			if err != nil {
				return fmt.Errorf("$defs.%s.%s: %w", name, field, err)
			}
			tag := field
			if !required[field] {
				// An optional field must be able to say "absent", so it is
				// made nilable and omitted when it is: a peer that never
				// receives the key behaves as the contract says, and a zero
				// value is never mistaken for a choice.
				typeName = nullable_(typeName)
				tag += ",omitempty"
			}
			fmt.Fprintf(b, "\t%s %s `json:%q`\n", exported(field), typeName, tag)
		}
		b.WriteString("}\n\n")
	}
	return nil
}
