// screenreader-mcp tests -- the reader-guidance controller.
// Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
//
// ROLE: unit tests for spec 0029 4.4's three properties -- lazy, cached for the
// session, and keyed on the LIVE CONNECTION rather than on a flag.
//
// The call COUNT is the subject here, not the text: every one of these would
// pass against a controller that made a fresh round trip on every read, or
// against one that served the previous session's document to a new session, if
// the assertions were about content. Both are the bugs this file exists to stop.
package controllers_test

import (
	"errors"
	"testing"

	"github.com/marlon-sousa/screen-readers-mcp/server/domain/controllers"
	"github.com/marlon-sousa/screen-readers-mcp/server/domain/entities"
	"github.com/marlon-sousa/screen-readers-mcp/server/domain/ports"
	"github.com/marlon-sousa/screen-readers-mcp/server/testsupport"
)

// connected builds a control holding one live session that announced guidance.
func connected(t *testing.T, reader string) (*testsupport.Connection, *fakeSessions) {
	t.Helper()
	session := testsupport.NewConnection(reader, testsupport.EveryCapability()...)
	if session.Guidance == nil {
		t.Fatal("the builder announced `guidance` and handed over no port")
	}
	return session, &fakeSessions{current: session.Connection}
}

// fakeSessions is the narrowed session source the controller declares.
//
// Hand-written rather than reaching for FakeConnectionControl: this controller
// needs exactly one method, and a double with connect/disconnect/verify on it
// would suggest the controller could reach them.
type fakeSessions struct{ current *ports.ReaderConnection }

func (f *fakeSessions) Current() *ports.ReaderConnection { return f.current }

// Lazy AND cached, in one assertion: nothing is fetched until somebody reads,
// and a second read costs no round trip.
func TestTheReaderGuidanceIsFetchedOnceAndThenCached(t *testing.T) {
	session, sessions := connected(t, "nvda")
	guidance := controllers.NewReaderGuidance(sessions)

	if calls := session.Guidance.Calls(); calls != 0 {
		t.Fatalf("the bridge was asked %d time(s) before anybody read; the fetch must be lazy", calls)
	}

	first, err := guidance.Document()
	if err != nil {
		t.Fatalf("first read: %v", err)
	}
	second, err := guidance.Document()
	if err != nil {
		t.Fatalf("second read: %v", err)
	}

	if calls := session.Guidance.Calls(); calls != 1 {
		t.Errorf("the bridge was asked %d times for a document that cannot change; want 1", calls)
	}
	if first.Text != second.Text {
		t.Errorf("two reads of one session disagreed:\n%q\n%q", first.Text, second.Text)
	}
	if first.Reader != "nvda" {
		t.Errorf("reader = %q, want nvda -- the frame names whose account this is", first.Reader)
	}
}

// The cache is keyed on the connection itself, so a new session cannot be served
// the previous one's text. This is the case a `fetched bool` would get wrong,
// and it is not a hypothetical: reconnecting under a different persona is the
// documented way to change stance (spec 0029 3.3).
func TestReconnectingRefetchesRatherThanServingThePreviousSession(t *testing.T) {
	first, sessions := connected(t, "nvda")
	first.Guidance.Result = ports.ReaderGuidance{Persona: "user", Recognised: true, Text: "the user's list"}
	guidance := controllers.NewReaderGuidance(sessions)

	if _, err := guidance.Document(); err != nil {
		t.Fatalf("first session: %v", err)
	}

	second := testsupport.NewConnection("nvda", testsupport.EveryCapability()...)
	second.Guidance.Result = ports.ReaderGuidance{
		Persona: "expert", Recognised: true, Text: "the expert's instruments",
	}
	sessions.current = second.Connection

	document, err := guidance.Document()
	if err != nil {
		t.Fatalf("second session: %v", err)
	}
	if document.Text != "the expert's instruments" {
		t.Errorf("after reconnecting the document was %q; the previous session's text was served",
			document.Text)
	}
	if calls := second.Guidance.Calls(); calls != 1 {
		t.Errorf("the new session's bridge was asked %d times; want exactly 1", calls)
	}
}

// Nothing connected is an ANSWER, not a failure -- the resource is registered
// whether or not a session is -- so the controller says which answer it is and
// leaves the wording to the adapter.
func TestReadingWithNoSessionReportsThatRatherThanFailing(t *testing.T) {
	guidance := controllers.NewReaderGuidance(&fakeSessions{})

	_, err := guidance.Document()
	if !errors.Is(err, controllers.ErrNoSession) {
		t.Errorf("err = %v, want ErrNoSession", err)
	}
}

// A bridge that announced no `guidance` is a supported configuration: the gate
// is structural (the port is nil), so nothing here checks a capability string.
func TestABridgeThatPublishesNoGuidanceIsReportedAsSuch(t *testing.T) {
	session := testsupport.NewConnection("jaws", entities.CapabilitySpeech)
	guidance := controllers.NewReaderGuidance(&fakeSessions{current: session.Connection})

	_, err := guidance.Document()
	if !errors.Is(err, controllers.ErrNoReaderGuidance) {
		t.Errorf("err = %v, want ErrNoReaderGuidance", err)
	}
}

// A bridge that announced the capability and then refused the command is a
// FAULT, not a degraded document -- and one bad moment must not become permanent
// for the session, so nothing is cached and the next read tries again.
func TestARefusalIsNotCachedAndIsNotDressedUpAsADocument(t *testing.T) {
	session, sessions := connected(t, "nvda")
	session.Guidance.Err = errors.New("bridge refused getGuidance: no documents packaged")
	guidance := controllers.NewReaderGuidance(sessions)

	if _, err := guidance.Document(); err == nil {
		t.Fatal("a refused getGuidance returned no error")
	}

	session.Guidance.Err = nil
	if _, err := guidance.Document(); err != nil {
		t.Fatalf("the second read after a transient refusal failed too: %v", err)
	}
	if calls := session.Guidance.Calls(); calls != 2 {
		t.Errorf("the bridge was asked %d times; a failure must not be cached", calls)
	}
}

// The persona reported is the one the BRIDGE echoed, so the document says what
// it actually answered for rather than what this server assumed it would.
func TestTheDocumentCarriesWhatTheBridgeAnsweredFor(t *testing.T) {
	session, sessions := connected(t, "nvda")
	session.Guidance.Result = ports.ReaderGuidance{Persona: "auditor", Recognised: false, Text: "general"}

	document, err := controllers.NewReaderGuidance(sessions).Document()
	if err != nil {
		t.Fatalf("read: %v", err)
	}
	if document.Persona != entities.Persona("auditor") {
		t.Errorf("persona = %q, want the bridge's own echo", document.Persona)
	}
	if document.Recognised {
		t.Error("recognised = true for a persona the bridge said it did not know")
	}
}
