// screenreader-mcp tools -- wiregen: the wire binding generator.
// Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
// ROLE: development tool that reads specs/wire/v1/schema.json and writes server/adapters/wire/wire.gen.go.
// USED BY: the //go:generate directive in adapters/wire/doc.go, and the CI check that regenerates and diffs it.
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
		// The unformatted source rides along, where a generator syntax bug is easiest to see.
		return fmt.Errorf("generated source does not parse: %w\n%s", err, source)
	}
	return os.WriteFile(outPath, formatted, 0o644)
}

type document struct {
	ProtocolVersion int     `json:"protocolVersion"`
	Defs            *object `json:"$defs"`
	Commands        *object `json:"commands"`
}

// object is a JSON object that keeps its key order: a map would lose it, and the output must be byte-stable
// for the drift check to mean anything.
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

// Keys returns the key order as written; a nil object has none.
func (o *object) Keys() []string {
	if o == nil {
		return nil
	}
	return o.keys
}

func (o *object) Raw(key string) json.RawMessage {
	if o == nil {
		return nil
	}
	return o.values[key]
}

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

// enumNames names each enum after protocol.py's own types; an enum missing here fails the generator.
var enumNames = map[string]string{
	"live|silent":       "CaptureMode",
	"browse|focus|none": "BrowseMode",
	"debug|debugwarning|error|info|io|warning":                                         "LogLevel",
	"braille|config|document|focus|gestures|guidance|interact|log|speech|state|typing": "Capability",
	"maxChars|maxLines|none":                                                           "TruncatedBy",
}

var initialisms = map[string]string{
	"id":   "ID",
	"ok":   "OK",
	"io":   "IO",
	"nvda": "NVDA",
	"url":  "URL",
	"json": "JSON",
	"tcp":  "TCP",
}

func enumKey(values []string) string {
	sorted := append([]string(nil), values...)
	sort.Strings(sorted)
	return strings.Join(sorted, "|")
}

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

// goType maps a schema fragment to a Go type. Shapes the contract leaves open become json.RawMessage, so reader
// vocabulary rides through untouched.
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
			// A union of two concrete shapes has no faithful Go spelling, so it is carried opaquely.
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

// nullable_ must stay idempotent: a field both nullable and optional must never become a double pointer.
func nullable_(goTypeName string) string {
	if strings.HasPrefix(goTypeName, "*") ||
		strings.HasPrefix(goTypeName, "[]") ||
		strings.HasPrefix(goTypeName, "map[") ||
		goTypeName == "json.RawMessage" {
		return goTypeName
	}
	return "*" + goTypeName
}

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

func emitCommands(b *strings.Builder, doc *document) error {
	b.WriteString("// Command is a wire command name.\ntype Command string\n\n")
	b.WriteString("// The commands this contract defines (protocol.md §5).\nconst (\n")
	for _, name := range doc.Commands.Keys() {
		fmt.Fprintf(b, "\tCommand%s Command = %q\n", exported(name), name)
	}
	b.WriteString(")\n\n")
	return nil
}

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
				// An optional field is nilable and omitted when absent, so a zero value is never mistaken for a choice.
				typeName = nullable_(typeName)
				tag += ",omitempty"
			}
			fmt.Fprintf(b, "\t%s %s `json:%q`\n", exported(field), typeName, tag)
		}
		b.WriteString("}\n\n")
	}
	return nil
}
