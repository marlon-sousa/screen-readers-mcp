// screenreader-mcp domain -- the output schemas, against the results themselves.
// Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
//
// WHITE-BOX (package tools), which the repo's default rule allows where an
// unexported thing deserves direct coverage and the header says why. This is
// that case, and it is the whole point of the file: the result structs are
// PRIVATE and stay private (spec 0031, 5.1), so the only place they can be
// compared against the hand-written schemas is inside the package that declares
// them.
//
// THIS IS THE TEST THAT MAKES HAND-WRITING SAFE. Spec 0031, 3.2 rejected
// reflecting the schema out of the result -- Execute returns `any`, so there is
// no type to reflect until a call has already happened, and a reflected schema
// would drop the prose that is most of the value. The cost of that decision is
// exactly one thing: a schema can disagree with its struct. So the schema stays
// hand-written and the FIELD NAMES are checked mechanically, all the way down,
// including through the embedded observation and through arrays of entries.
//
// It also checks the OTHER half of the shape an agent depends on: a field is
// declared required exactly when it is not `omitempty`. That is what makes
// "absent" mean something -- absent state is a reader with no state capability,
// absent emittedAt is a reader that supplied no instant -- and a struct that
// gains an omitempty without the schema following would quietly promise a field
// that is not always there.
package tools

import (
	"encoding/json"
	"reflect"
	"strings"
	"testing"

	"github.com/marlon-sousa/screen-readers-mcp/server/domain/ports"
)

// resultOf names the value each tool's Execute returns on success.
//
// Hand-written, and covered by TestEveryToolDeclaresItsResultType below: a new
// tool that does not appear here fails that test, which is the point at which
// somebody is asked what their tool returns.
//
// Two entries are port types rather than local structs -- get_log and
// set_log_level forward the port's answer unchanged -- which is not an
// inconsistency to tidy away: what the agent receives is what the schema must
// describe, wherever the struct happens to live.
var resultOf = map[string]any{
	"list_readers":      listReadersResult{},
	"connect_reader":    connectResult{},
	"disconnect_reader": disconnectResult{},
	"status":            statusResult{},

	"get_speech":                speechRangeResult{},
	"get_last_speech":           lastSpeechResult{},
	"get_next_speech_index":     nextIndexResult{},
	"wait_for_speech":           waitForSpeechResult{},
	"wait_for_speech_to_finish": waitToFinishResult{},

	"get_braille": speechRangeResult{},

	"press_gesture": pressGestureResult{},
	"type_text":     typeTextResult{},

	"announce":            announceResult{},
	"ask_user":            askUserResult{},
	"wait_for_user_reply": waitForUserReplyResult{},

	"get_focus_info": focusResult{},
	"get_state":      stateResult{},
	"set_state":      setStateResult{},

	"get_config": configResult{},
	"set_config": configResult{},

	"get_document_snapshot": documentSnapshotResult{},

	"run_sequence": runSequenceResult{},

	"get_log":          ports.LogSliceResult{},
	"get_log_position": logPositionResult{},
	"wait_for_log":     waitForLogResult{},
	"set_log_level":    ports.LogLevelResult{},
}

// The table is only a guard if it covers everything, and only honest if it
// covers nothing else.
func TestEveryToolDeclaresItsResultType(t *testing.T) {
	registered := map[string]bool{}
	for _, tool := range BuildRegistry().All() {
		registered[tool.Name()] = true
		if _, named := resultOf[tool.Name()]; !named {
			t.Errorf("%s has no result type here, so its output schema is unchecked; "+
				"add the struct its Execute returns", tool.Name())
		}
	}
	for name := range resultOf {
		if !registered[name] {
			t.Errorf("%q is named here but is not a registered tool", name)
		}
	}
}

// The assertion the spec's "honest limits" section is about: a hand-written
// output schema can be wrong, and this is the window being kept narrow.
func TestEveryOutputSchemaMatchesItsResultStruct(t *testing.T) {
	for _, tool := range BuildRegistry().All() {
		result, named := resultOf[tool.Name()]
		if !named {
			continue // reported by TestEveryToolDeclaresItsResultType
		}
		t.Run(tool.Name(), func(t *testing.T) {
			var schema map[string]any
			if err := json.Unmarshal(tool.OutputSchema(), &schema); err != nil {
				t.Fatalf("output schema is not valid JSON: %v", err)
			}
			if schema["type"] != "object" {
				t.Fatalf(`output schema type = %v, want "object"`, schema["type"])
			}
			compareSchema(t, schema, reflect.TypeOf(result), tool.Name())
		})
	}
}

// compareSchema walks the declared schema and the Go type together.
func compareSchema(t *testing.T, schema map[string]any, typ reflect.Type, path string) {
	t.Helper()

	for typ.Kind() == reflect.Pointer {
		typ = typ.Elem()
	}
	switch {
	case typ == reflect.TypeOf(json.RawMessage{}):
		// Opaque by design: the reader owns the shape of its own settings, so
		// there is nothing here to compare. Descending would compare a schema
		// against []byte and demand a field per element.
		return
	case typ.Kind() == reflect.Slice:
		items, described := schema["items"].(map[string]any)
		if !described {
			t.Errorf("%s: is a list, and the schema declares no items", path)
			return
		}
		compareSchema(t, items, typ.Elem(), path+"[]")
		return
	case typ.Kind() != reflect.Struct:
		return
	}

	declared, described := schema["properties"].(map[string]any)
	if !described {
		t.Errorf("%s: is an object, and the schema declares no properties", path)
		return
	}
	marshalled := marshalledFields(typ)

	for name := range declared {
		if _, real := marshalled[name]; !real {
			t.Errorf("%s: the schema declares %q, which the result does not marshal", path, name)
		}
	}
	required := map[string]bool{}
	for _, name := range stringsIn(schema["required"]) {
		if _, declaredHere := declared[name]; !declaredHere {
			t.Errorf("%s: %q is required and not declared", path, name)
		}
		required[name] = true
	}

	for name, field := range marshalled {
		property, describedHere := declared[name].(map[string]any)
		if !describedHere {
			t.Errorf("%s: the result marshals %q, which the schema does not declare -- "+
				"an agent reading this schema would not know the field exists", path, name)
			continue
		}
		// Absence has to mean the same thing in both places.
		if required[name] == field.omitEmpty {
			if field.omitEmpty {
				t.Errorf("%s: %q is omitempty and declared required; an agent would "+
					"count on a field that is legitimately absent", path, name)
			} else {
				t.Errorf("%s: %q is always marshalled and not declared required", path, name)
			}
		}
		compareSchema(t, property, field.typ, path+"."+name)
	}
}

// field is one marshalled member: the type behind it, and whether it can be
// absent.
type field struct {
	typ       reflect.Type
	omitEmpty bool
}

// marshalledFields is what encoding/json would actually emit for typ, with
// embedded structs flattened the way the encoder flattens them -- which is how
// press_gesture and type_text come to publish the observation's four fields as
// their own.
func marshalledFields(typ reflect.Type) map[string]field {
	fields := map[string]field{}
	for i := range typ.NumField() {
		structField := typ.Field(i)
		tag := structField.Tag.Get("json")
		name, options, _ := strings.Cut(tag, ",")
		switch {
		case !structField.IsExported() && !structField.Anonymous:
			continue
		case name == "-":
			continue
		case structField.Anonymous && name == "":
			for embedded, value := range marshalledFields(structField.Type) {
				fields[embedded] = value
			}
			continue
		case name == "":
			name = structField.Name
		}
		fields[name] = field{
			typ:       structField.Type,
			omitEmpty: strings.Contains(options, "omitempty"),
		}
	}
	return fields
}

// stringsIn reads a decoded JSON array of strings, tolerating its absence.
func stringsIn(value any) []string {
	list, isList := value.([]any)
	if !isList {
		return nil
	}
	found := make([]string, 0, len(list))
	for _, item := range list {
		if text, isText := item.(string); isText {
			found = append(found, text)
		}
	}
	return found
}
