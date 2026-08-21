// screenreader-mcp domain -- decodeParams: the tools' shared argument decoding.
// Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
//
// ROLE: a private helper shared by the tool controllers in this package. Not a
// role in its own right -- it is the one line of boilerplate erased params cost
// us, kept in one place rather than repeated fifteen times.
// USED BY: every tool that takes parameters.
//
// Spec 0034 (board entry 11.26) gave it a second job, and being the one place
// every tool decodes is why the job has exactly one home: a TYPE MISMATCH gains
// a hypothesis about where it came from. See staleSchemaHint.
package tools

import (
	"encoding/json"
	"errors"
	"fmt"
	"reflect"
	"strings"
)

// decodeParams unmarshals a call's raw arguments.
//
// EMPTY IS VALID. A client calling a tool with no arguments sends no `arguments`
// member at all, so params arrives nil rather than as `{}` -- and a tool whose
// parameters are all optional must accept that rather than report a parse error
// for a perfectly ordinary call.
//
// A decode failure is reported with the raw text included, because the agent
// wrote it and can only fix what it can see.
func decodeParams(params json.RawMessage, into any) error {
	if len(params) == 0 {
		return nil
	}
	if err := json.Unmarshal(params, into); err != nil {
		return fmt.Errorf("could not read the arguments %s: %w%s", params, err, staleSchemaHint(err))
	}
	return nil
}

// staleSchemaHint offers a reading of a decode failure, or nothing at all.
//
// Spec 0034 Part 3.2. The failure it was written for: the server gained one
// optional parameter and was redeployed, and the next call sent `"true"` -- a
// string -- for a boolean, because the client was serialising against the
// `inputSchema` it had cached, which did not declare the field. The error it got
// back was about JSON and Go structs, and named nothing that would lead anyone
// to the cache.
//
// IT IS A HYPOTHESIS AND IS WRITTEN AS ONE. A stale client sending `"true"` and
// a current client whose author typed a string produce the SAME BYTES; the
// server holds no copy of what the client holds, so it cannot tell them apart.
// "may be holding" and "if you did not expect" are load-bearing -- asserting a
// cause the server cannot know is the failure spec 0027's reporter demonstrated
// from the other side.
//
// TYPE MISMATCHES ONLY, on a field the tool declares. Malformed JSON is not
// evidence of staleness, and a hypothesis attached to everything is noise the
// next reader learns to skip. (Unknown and missing fields never reach here at
// all: decodeParams uses a plain Unmarshal, which ignores fields no struct
// declares and leaves absent ones at their zero value. That also means the
// MIRROR case -- a client still sending a parameter this build removed -- fails
// silently rather than loudly, and nothing here can catch it.)
//
// IT NAMES BOTH REMEDIES AND SAYS WHICH IS WHOSE. Reading a resource is a move
// an agent can make in the same turn; re-listing the tools is client UI that
// only the human at the keyboard can reach. Sending an agent to a control it
// does not have is the care spec 0032's silence-cap sentence takes.
//
// It is a per-call error. Nothing about it ends a session.
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

// article keeps the sentence readable whichever type names land in it. Trivial,
// and it is a function rather than an inline expression because the alternative
// -- "a array" -- was what the first run of the test actually printed.
func article(word string) string {
	if word == "" {
		return "a"
	}
	if strings.ContainsRune("aeiou", rune(word[0])) {
		return "an"
	}
	return "a"
}

// sentAs names the JSON type the client actually sent, in the vocabulary the
// schemas are written in.
//
// The decoder describes a wrong number as `number 1.5` -- the value along with
// the type -- and the raw arguments are already quoted in full at the front of
// the message, so the first word is the part that adds anything here. `bool` is
// spelled `boolean` for the same reason: it is what the published schema calls
// it, and the whole point is to send the reader to that schema.
func sentAs(value string) string {
	kind, _, _ := strings.Cut(value, " ")
	if kind == "bool" {
		return "boolean"
	}
	return kind
}

// takes names the JSON type the tool's schema declares, from the Go type the
// decoder was aiming at.
//
// Derived rather than looked up in the schema on purpose: the struct is what the
// call is really being decoded into, so a struct and a schema that disagree
// would be reported as the struct sees it -- which is the disagreement that
// caused the error. A type with no JSON spelling is named as Go names it rather
// than guessed at.
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
