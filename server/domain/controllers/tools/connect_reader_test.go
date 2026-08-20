// screenreader-mcp domain -- the connect_reader tool's tests.
// Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
//
// This tool is the only thing in the server that causes a dial, so its tests are
// where "the agent owns the connection" is pinned down: the reader is required,
// the session-fixed parameters reach the handshake as given, and a bad value is
// refused HERE rather than travelling to the bridge to be rejected there.
package tools_test

import (
	"encoding/json"
	"errors"
	"strings"
	"testing"

	"github.com/marlon-sousa/screen-readers-mcp/server/domain/controllers/tools"
	"github.com/marlon-sousa/screen-readers-mcp/server/domain/entities"
	"github.com/marlon-sousa/screen-readers-mcp/server/testsupport"
)

func connectCall(t *testing.T) *testsupport.ToolCall {
	t.Helper()
	call := testsupport.NewToolCall(&tools.ConnectReader{})
	built := testsupport.NewConnection("nvda", testsupport.EveryCapability()...)
	call.Control.SetConnection(built.Connection)
	return call
}

func TestConnectPassesTheReaderAndModeThrough(t *testing.T) {
	call := connectCall(t)

	if _, err := call.Run(`{"reader":"nvda","mode":"silent","persona":"user"}`); err != nil {
		t.Fatalf("connect_reader: %v", err)
	}

	connects := call.Control.Connects()
	if len(connects) != 1 {
		t.Fatalf("Connect called %d times, want once", len(connects))
	}
	if connects[0].Reader != "nvda" {
		t.Errorf("reader = %q, want nvda", connects[0].Reader)
	}
	if connects[0].Options.Mode != entities.CaptureSilent {
		t.Errorf("mode = %q, want silent", connects[0].Options.Mode)
	}
	if connects[0].Options.LogLevel != nil {
		t.Errorf("log level = %v, want unset when the agent did not ask", *connects[0].Options.LogLevel)
	}
}

// log_level is optional, and when given it must reach the handshake -- it is a
// real, temporary change to the READER's own logging, fixed for the session.
func TestConnectPassesAnOptionalLogLevelThrough(t *testing.T) {
	call := connectCall(t)

	if _, err := call.Run(`{"reader":"nvda","mode":"live","persona":"expert","log_level":"debug"}`); err != nil {
		t.Fatalf("connect_reader: %v", err)
	}

	options := call.Control.Connects()[0].Options
	if options.Mode != entities.CaptureLive {
		t.Errorf("mode = %q, want live", options.Mode)
	}
	if options.LogLevel == nil || *options.LogLevel != entities.ReaderLogDebug {
		t.Errorf("log level = %v, want debug", options.LogLevel)
	}
}

// Required and never defaulted (spec 0013): defaulting to the single live reader
// would make one call mean different things minute to minute, and defaulting to
// the single KNOWN one is deterministic only until a second bridge ships.
func TestTheReaderArgumentIsRequiredAndTheErrorListsTheKnownNames(t *testing.T) {
	call := connectCall(t)
	call.Control.SetListing(entities.BuildListing([]entities.ConfiguredReader{
		{Name: "nvda"}, {Name: "jaws"},
	}, nil))

	_, err := call.Run(`{"mode":"silent","persona":"user"}`)
	if err == nil {
		t.Fatal("connecting with no reader succeeded")
	}
	if !strings.Contains(err.Error(), "nvda") || !strings.Contains(err.Error(), "jaws") {
		t.Errorf("error = %q, want the known reader names listed so a wrong "+
			"guess self-corrects in the same turn", err)
	}
	if len(call.Control.Connects()) != 0 {
		t.Error("a dial was attempted with no reader named")
	}
}

// A bad mode is refused at the tool boundary, with the valid values named. The
// bridge would reject it too, but a round trip later and with a worse message.
func TestAnInvalidModeIsRefusedBeforeDialing(t *testing.T) {
	call := connectCall(t)

	_, err := call.Run(`{"reader":"nvda","mode":"quiet","persona":"user"}`)
	if err == nil {
		t.Fatal("an invalid capture mode was accepted")
	}
	if !strings.Contains(err.Error(), "silent") || !strings.Contains(err.Error(), "live") {
		t.Errorf("error = %q, want the valid modes listed", err)
	}
	if len(call.Control.Connects()) != 0 {
		t.Error("a dial was attempted with an invalid mode")
	}
}

func TestAnInvalidLogLevelIsRefusedBeforeDialing(t *testing.T) {
	call := connectCall(t)

	_, err := call.Run(`{"reader":"nvda","mode":"silent","persona":"user","log_level":"shout"}`)
	if err == nil {
		t.Fatal("an invalid log level was accepted")
	}
	if len(call.Control.Connects()) != 0 {
		t.Error("a dial was attempted with an invalid log level")
	}
}

// Mode is required too: the wire fixes it for the session's lifetime, so a tool
// inventing a default would be the wrong layer making that choice.
func TestTheModeArgumentIsRequired(t *testing.T) {
	call := connectCall(t)

	if _, err := call.Run(`{"reader":"nvda","persona":"user"}`); err == nil {
		t.Error("connecting with no mode succeeded")
	}
}

// -- persona (spec 0029) ------------------------------------------------------

// Required, like mode, and NEVER defaulted. A default would silently attribute a
// stance nobody chose, and a claim resting on a defaulted `user` session is one
// nobody can withdraw, because nobody knows it was made.
func TestThePersonaArgumentIsRequired(t *testing.T) {
	call := connectCall(t)

	_, err := call.Run(`{"reader":"nvda","mode":"silent"}`)
	if err == nil {
		t.Fatal("connecting with no persona succeeded")
	}
	if len(call.Control.Connects()) != 0 {
		t.Error("a dial was attempted with no persona declared")
	}
}

// The error is where most agents will meet personas for the first time, so it
// names all three WITH the question each one asks -- a wrong guess should
// self-correct in this turn rather than cost a round trip.
func TestAnInvalidPersonaIsRefusedAndTheErrorTeachesTheThree(t *testing.T) {
	call := connectCall(t)

	_, err := call.Run(`{"reader":"nvda","mode":"silent","persona":"tester"}`)
	if err == nil {
		t.Fatal("an invalid persona was accepted")
	}
	for _, want := range []string{"user", "validator", "expert", "can I do this?"} {
		if !strings.Contains(err.Error(), want) {
			t.Errorf("error = %q, want it to mention %q", err, want)
		}
	}
	if len(call.Control.Connects()) != 0 {
		t.Error("a dial was attempted with an invalid persona")
	}
}

func TestThePersonaReachesTheHandshake(t *testing.T) {
	call := connectCall(t)

	if _, err := call.Run(`{"reader":"nvda","mode":"silent","persona":"validator"}`); err != nil {
		t.Fatalf("connect_reader: %v", err)
	}

	if got := call.Control.Connects()[0].Options.Persona; got != entities.PersonaValidator {
		t.Errorf("persona = %q, want it carried into the session options", got)
	}
}

// A persona an agent declares but never reads is a label, not an instruction --
// and the first external run (spec 0027) never read the guidance resource at
// all. Connect is the one moment an agent is guaranteed to be reading.
func TestTheResultCarriesTheStanceInFull(t *testing.T) {
	call := connectCall(t)

	result, err := call.Run(`{"reader":"nvda","mode":"silent","persona":"user"}`)
	if err != nil {
		t.Fatalf("connect_reader: %v", err)
	}

	var got struct {
		Persona string `json:"persona"`
		Stance  string `json:"stance"`
	}
	encoded, _ := json.Marshal(result)
	if err := json.Unmarshal(encoded, &got); err != nil {
		t.Fatalf("decoding the result: %v", err)
	}

	if got.Persona != "user" {
		t.Errorf("persona = %q, want the declared one echoed", got.Persona)
	}
	if got.Stance != entities.PersonaUser.Stance() {
		t.Errorf("stance = %q, want the persona's stance in full", got.Stance)
	}
}

// What the agent gets back has to be enough to work with: who answered, where,
// what it can do, and where the session's two logs are.
func TestTheResultDescribesTheSessionThatWasEstablished(t *testing.T) {
	call := connectCall(t)

	result, err := call.Run(`{"reader":"nvda","mode":"silent","persona":"user"}`)
	if err != nil {
		t.Fatalf("connect_reader: %v", err)
	}

	var got struct {
		Reader       string   `json:"reader"`
		Endpoint     string   `json:"endpoint"`
		Capabilities []string `json:"capabilities"`
		Mode         string   `json:"mode"`
		LogPath      string   `json:"logPath"`
	}
	encoded, _ := json.Marshal(result)
	if err := json.Unmarshal(encoded, &got); err != nil {
		t.Fatalf("decoding the result: %v", err)
	}

	if got.Reader != "nvda" {
		t.Errorf("reader = %q, want the one hello announced", got.Reader)
	}
	if got.Endpoint != "pipe:nvdaMcpBridge" {
		t.Errorf("endpoint = %q, want the one that answered", got.Endpoint)
	}
	if len(got.Capabilities) != len(testsupport.EveryCapability()) {
		t.Errorf("capabilities = %v, want every capability announced", got.Capabilities)
	}
	// Acceptance criterion 5: the mode reported is the one the BRIDGE
	// confirmed, which is what makes the check meaningful rather than an echo.
	if got.Mode != "silent" {
		t.Errorf("mode = %q, want the mode hello established", got.Mode)
	}
	if got.LogPath == "" {
		t.Errorf("log path = %q, want it reported", got.LogPath)
	}
}

// A failed connect is reported and nothing else happens: no retry, no fallback
// to another reader, no state invented here.
func TestAFailedConnectIsReportedToTheAgent(t *testing.T) {
	call := testsupport.NewToolCall(&tools.ConnectReader{})
	call.Control.FailConnectWith(errors.New(`reader "nvda": no endpoint answered`))

	_, err := call.Run(`{"reader":"nvda","mode":"silent","persona":"user"}`)
	if err == nil {
		t.Fatal("a failed connect was reported as success")
	}
	if len(call.Control.Connects()) != 1 {
		t.Errorf("Connect was called %d times; a failure must not be retried",
			len(call.Control.Connects()))
	}
}

// -- the silence cap (spec 0032) ---------------------------------------------
//
// Connect is the one moment an agent is guaranteed to be reading, and it is the
// earliest instant this fact exists -- it describes the machine that just
// answered. An agent that never learns a human is expected there is an agent
// that goes quiet on them.

func connectAnswer(t *testing.T, call *testsupport.ToolCall) map[string]any {
	t.Helper()
	result, err := call.Run(`{"reader":"nvda","mode":"silent","persona":"user"}`)
	if err != nil {
		t.Fatalf("connect_reader: %v", err)
	}
	encoded, _ := json.Marshal(result)
	var answer map[string]any
	if err := json.Unmarshal(encoded, &answer); err != nil {
		t.Fatalf("decoding the result: %v", err)
	}
	return answer
}

func TestConnectStatesTheMachinesSilenceCap(t *testing.T) {
	call := testsupport.NewToolCall(&tools.ConnectReader{})
	built := testsupport.NewConnection("nvda", testsupport.EveryCapability()...)
	built.Connection.Session.SilenceCap = &entities.SilenceCap{
		Enabled: true, WarnAfter: 45, LiftAfter: 90,
	}
	call.Control.SetConnection(built.Connection)

	sentence, _ := connectAnswer(t, call)["silenceCap"].(string)

	if !strings.Contains(sentence, "45s") || !strings.Contains(sentence, "90s") {
		t.Errorf("silenceCap does not name the thresholds: %q", sentence)
	}
}

func TestConnectAlwaysSaysSomethingAboutSilence(t *testing.T) {
	// Including for a bridge that sent no field at all. An absent answer would
	// read as "nothing to worry about", which is the one thing it does not mean.
	call := connectCall(t)

	sentence, ok := connectAnswer(t, call)["silenceCap"].(string)

	if !ok || sentence == "" {
		t.Fatal("silenceCap is absent; an agent has nothing to act on")
	}
	if !strings.Contains(sentence, "did not say") {
		t.Errorf("a bridge that said nothing was reported as something: %q", sentence)
	}
}
