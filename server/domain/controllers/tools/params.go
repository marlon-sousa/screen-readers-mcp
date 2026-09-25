// screenreader-mcp domain -- decodeParams: the tools' shared argument decoding.
// Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
// ROLE: a private helper shared by the tool controllers in this package.
// USED BY: every tool that takes parameters.
package tools

import (
	"encoding/json"
	"errors"
	"fmt"
	"reflect"
	"strings"
)

// decodeParams accepts nil params, since a client calling a tool with no arguments sends none.
func decodeParams(params json.RawMessage, into any) error {
	if len(params) == 0 {
		return nil
	}
	if err := json.Unmarshal(params, into); err != nil {
		return fmt.Errorf("could not read the arguments %s: %w%s", params, err, staleSchemaHint(err))
	}
	return nil
}

// staleSchemaHint offers the hypothesis of a stale client schema, for a type mismatch on a declared field only, or nothing at all.
// A client still sending a parameter this build removed fails silently: plain Unmarshal ignores undeclared fields.
func staleSchemaHint(err error) string {
	var mismatch *json.UnmarshalTypeError
	if !errors.As(err, &mismatch) || mismatch.Field == "" {
		return ""
	}
	sent, declared := sentAs(mismatch.Value), takes(mismatch.Type)
	return fmt.Sprintf(
		". The value for %q is %s %s, but this tool takes %s %s. If you did not expect this "+
			"parameter to be new, your client may be holding a tool schema older than this "+
			"server build -- a client caches tools/list, and that cache includes each tool's "+
			"parameters. Read screenreader://tools for the parameters this build actually "+
			"takes: a resource is read live and is never cached, so it describes the build "+
			"that is running even when a cached list does not. Re-listing the tools is "+
			"client UI -- only the human at the keyboard can reconnect this MCP server",
		mismatch.Field, article(sent), sent, article(declared), declared)
}

func article(word string) string {
	if word == "" {
		return "a"
	}
	if strings.ContainsRune("aeiou", rune(word[0])) {
		return "an"
	}
	return "a"
}

func sentAs(value string) string {
	kind, _, _ := strings.Cut(value, " ")
	if kind == "bool" {
		return "boolean"
	}
	return kind
}

func takes(target reflect.Type) string {
	for target != nil && target.Kind() == reflect.Pointer {
		target = target.Elem()
	}
	if target == nil {
		return "another type"
	}
	switch target.Kind() {
	case reflect.Bool:
		return "boolean"
	case reflect.String:
		return "string"
	case reflect.Int, reflect.Int8, reflect.Int16, reflect.Int32, reflect.Int64,
		reflect.Uint, reflect.Uint8, reflect.Uint16, reflect.Uint32, reflect.Uint64,
		reflect.Float32, reflect.Float64:
		return "number"
	case reflect.Slice, reflect.Array:
		return "array"
	case reflect.Map, reflect.Struct:
		return "object"
	default:
		return target.String()
	}
}
