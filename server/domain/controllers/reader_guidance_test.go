// screenreader-mcp tests -- the reader-guidance controller.
// Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
//
// The call count is the subject: content assertions would also pass against a controller that refetched every read or served a previous session's text.
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

type fakeSessions struct{ current *ports.ReaderConnection }

func (f *fakeSessions) Current() *ports.ReaderConnection { return f.current }

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

func TestReadingWithNoSessionReportsThatRatherThanFailing(t *testing.T) {
	guidance := controllers.NewReaderGuidance(&fakeSessions{})

	_, err := guidance.Document()
	if !errors.Is(err, controllers.ErrNoSession) {
		t.Errorf("err = %v, want ErrNoSession", err)
	}
}

func TestABridgeThatPublishesNoGuidanceIsReportedAsSuch(t *testing.T) {
	session := testsupport.NewConnection("jaws", entities.CapabilitySpeech)
	guidance := controllers.NewReaderGuidance(&fakeSessions{current: session.Connection})

	_, err := guidance.Document()
	if !errors.Is(err, controllers.ErrNoReaderGuidance) {
		t.Errorf("err = %v, want ErrNoReaderGuidance", err)
	}
}

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
