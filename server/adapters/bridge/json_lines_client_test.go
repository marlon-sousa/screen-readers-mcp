// screenreader-mcp adapters -- tests for json_lines_client.go.
// Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
package bridge_test

import (
	"encoding/json"
	"errors"
	"testing"
	"time"

	"github.com/google/go-cmp/cmp"
	"github.com/marlon-sousa/screen-readers-mcp/server/adapters/bridge"
	"github.com/marlon-sousa/screen-readers-mcp/server/adapters/wire"
	"github.com/marlon-sousa/screen-readers-mcp/server/domain/ports"
	"github.com/marlon-sousa/screen-readers-mcp/server/fakes"
)

// newClient builds a client over a scripted transport whose responder answers each request.
func newClient(t testing.TB, respond func(request wire.Request) (any, error)) (*bridge.JSONLinesClient, *fakes.FakeTransport) {
	t.Helper()
	clock := fakes.NewFakeClock()
	transport := fakes.NewFakeTransport(clock)
	if respond != nil {
		transport.OnWrite(func(raw []byte) {
			var request wire.Request
			if err := json.Unmarshal(raw, &request); err != nil {
				t.Errorf("client wrote a line that is not a request: %v", err)
				return
			}
			result, failure := respond(request)
			response := wire.Response{ID: request.ID}
			if failure != nil {
				response.Error = &wire.ErrorInfo{Message: failure.Error()}
			} else if result != nil {
				encoded, err := json.Marshal(result)
				if err != nil {
					t.Errorf("scripting a response: %v", err)
					return
				}
				response.Result = encoded
			}
			line, err := json.Marshal(response)
			if err != nil {
				t.Errorf("scripting a response: %v", err)
				return
			}
			transport.QueueRead(append(line, '\n'))
		})
	}
	return bridge.NewJSONLinesClient(transport, clock, fakes.NewFakeLog()), transport
}

func TestSpeechSinceMapsTheWireResultIntoDomainVocabulary(t *testing.T) {
	client, transport := newClient(t, func(request wire.Request) (any, error) {
		if wire.Command(request.Cmd) != wire.CommandGetSpeech {
			t.Errorf("cmd = %q, want %q", request.Cmd, wire.CommandGetSpeech)
		}
		var params wire.GetSpeechParams
		if err := json.Unmarshal(request.Params, &params); err != nil {
			t.Fatalf("params: %v", err)
		}
		if params.SinceIndex != 7 {
			t.Errorf("sinceIndex = %d, want 7", params.SinceIndex)
		}
		return wire.SpeechResult{
			Entries:   []wire.SpeechEntry{{Text: "button", Index: 8, LogPosition: 41}},
			FromIndex: 7,
			ToIndex:   9,
		}, nil
	})

	got, err := client.SpeechSince(7)
	if err != nil {
		t.Fatalf("SpeechSince: %v", err)
	}

	want := ports.SpeechRange{
		Entries:   []ports.SpeechEntry{{Text: "button", Index: 8, LogPosition: 41}},
		FromIndex: 7,
		ToIndex:   9,
	}
	if diff := cmp.Diff(want, got); diff != "" {
		t.Errorf("speech range (-want +got):\n%s", diff)
	}
	if len(transport.Written()) == 0 {
		t.Error("nothing was written to the transport")
	}
}

func TestEachRequestIsOneNewlineTerminatedLine(t *testing.T) {
	client, transport := newClient(t, func(wire.Request) (any, error) {
		return wire.NextIndexResult{Index: 3}, nil
	})

	if _, err := client.NextSpeechIndex(); err != nil {
		t.Fatalf("NextSpeechIndex: %v", err)
	}
	if _, err := client.NextSpeechIndex(); err != nil {
		t.Fatalf("NextSpeechIndex: %v", err)
	}

	written := transport.Written()
	if written[len(written)-1] != '\n' {
		t.Error("the last frame written is not newline-terminated")
	}
	lines := 0
	for _, b := range written {
		if b == '\n' {
			lines++
		}
	}
	if lines != 2 {
		t.Errorf("wrote %d lines for 2 requests", lines)
	}
}

func TestCorrelationIDsAdvancePerRequest(t *testing.T) {
	var seen []int
	client, _ := newClient(t, func(request wire.Request) (any, error) {
		seen = append(seen, request.ID)
		return wire.NextIndexResult{Index: 0}, nil
	})

	for range 3 {
		if _, err := client.NextSpeechIndex(); err != nil {
			t.Fatalf("NextSpeechIndex: %v", err)
		}
	}

	if len(seen) != 3 || seen[0] == seen[1] || seen[1] == seen[2] {
		t.Errorf("request ids = %v, want three distinct ids", seen)
	}
}

func TestABridgeErrorFailsTheCommandButNotTheConnection(t *testing.T) {
	client, transport := newClient(t, func(request wire.Request) (any, error) {
		if wire.Command(request.Cmd) == wire.CommandPressGesture {
			return nil, errors.New("unknown gesture kb:NVDA+nonsense")
		}
		return wire.NextIndexResult{Index: 1}, nil
	})

	_, err := client.PressGestures([]string{"kb:NVDA+nonsense"}, 0, "")

	var bridgeErr *bridge.BridgeError
	if !errors.As(err, &bridgeErr) {
		t.Fatalf("PressGestures error = %v, want a *bridge.BridgeError", err)
	}
	if bridgeErr.Message != "unknown gesture kb:NVDA+nonsense" {
		t.Errorf("message = %q, want the bridge's own words", bridgeErr.Message)
	}
	if transport.Closed() {
		t.Error("the connection was closed by a command failure")
	}
	if _, err := client.NextSpeechIndex(); err != nil {
		t.Errorf("the session did not survive a failed command: %v", err)
	}
}

func TestAPeerThatClosesIsReportedAsConnectionLost(t *testing.T) {
	client, transport := newClient(t, nil)
	transport.QueueEOF()

	_, err := client.Ping()

	if !errors.Is(err, bridge.ErrConnectionLost) {
		t.Fatalf("Ping error = %v, want ErrConnectionLost", err)
	}
	if !transport.Closed() {
		t.Error("a lost connection was not closed")
	}
}

func TestAResetIsTreatedAsAnAbruptEOF(t *testing.T) {
	clock := fakes.NewFakeClock()
	reset := fakes.NewFakeTransport(clock)
	reset.QueueError(errors.New("wsarecv: An existing connection was forcibly closed"))
	client := bridge.NewJSONLinesClient(reset, clock, fakes.NewFakeLog())

	if _, err := client.Ping(); !errors.Is(err, bridge.ErrConnectionLost) {
		t.Fatalf("Ping error = %v, want ErrConnectionLost", err)
	}
}

func TestACommandThatIsNeverAnsweredTimesOut(t *testing.T) {
	client, _ := newClient(t, nil)

	_, err := client.Ping()

	var timeout *bridge.TimeoutError
	if !errors.As(err, &timeout) {
		t.Fatalf("Ping error = %v, want a *bridge.TimeoutError", err)
	}
	if timeout.Command != wire.CommandPing {
		t.Errorf("timeout names %q, want %q", timeout.Command, wire.CommandPing)
	}
	if timeout.Waited != bridge.DefaultCallTimeout {
		t.Errorf("waited %s, want the ordinary call budget %s", timeout.Waited, bridge.DefaultCallTimeout)
	}
}

func TestAWaitingCommandOutlivesItsOwnTimeout(t *testing.T) {
	client, _ := newClient(t, nil)

	_, err := client.WaitForSpeech(ports.SpeechWait{Text: "ready", Timeout: 2 * time.Second})

	var timeout *bridge.TimeoutError
	if !errors.As(err, &timeout) {
		t.Fatalf("WaitForSpeech error = %v, want a *bridge.TimeoutError", err)
	}
	if timeout.Waited <= 2*time.Second {
		t.Errorf("local budget %s is not longer than the requested 2s", timeout.Waited)
	}
}

func TestWaitForUserReplyOutlivesTheBridgesOwnDefault(t *testing.T) {
	client, _ := newClient(t, nil)

	_, err := client.WaitForUserReply("ticket-1", 0)

	var timeout *bridge.TimeoutError
	if !errors.As(err, &timeout) {
		t.Fatalf("WaitForUserReply error = %v, want a *bridge.TimeoutError", err)
	}
	if timeout.Waited <= 30*time.Second {
		t.Errorf("local budget %s does not outlast the bridge's own 30s default for an "+
			"omitted timeout, so the client would abandon a reply still in flight",
			timeout.Waited)
	}
}

func TestWaitForUserReplyOmitsAnUnaskedTimeout(t *testing.T) {
	client, _ := newClient(t, func(request wire.Request) (any, error) {
		var params wire.WaitForUserReplyParams
		if err := json.Unmarshal(request.Params, &params); err != nil {
			t.Fatalf("params: %v", err)
		}
		if params.Timeout != nil {
			t.Errorf("timeout = %v on the wire, want it omitted so the bridge decides",
				*params.Timeout)
		}
		return wire.WaitForUserReplyResult{Answered: true}, nil
	})

	reply, err := client.WaitForUserReply("ticket-1", 0)
	if err != nil {
		t.Fatalf("WaitForUserReply: %v", err)
	}
	if !reply.Answered {
		t.Error("answered = false, want the scripted answer through")
	}
}

func TestWaitForUserReplySendsAnExplicitTimeout(t *testing.T) {
	client, _ := newClient(t, func(request wire.Request) (any, error) {
		var params wire.WaitForUserReplyParams
		if err := json.Unmarshal(request.Params, &params); err != nil {
			t.Fatalf("params: %v", err)
		}
		if params.Timeout == nil {
			t.Fatal("timeout was omitted, want the caller's 45s on the wire")
		}
		if *params.Timeout != 45 {
			t.Errorf("timeout = %v, want 45 seconds", *params.Timeout)
		}
		return wire.WaitForUserReplyResult{Answered: false}, nil
	})

	if _, err := client.WaitForUserReply("ticket-1", 45*time.Second); err != nil {
		t.Fatalf("WaitForUserReply: %v", err)
	}
}

func TestAFrameSplitAcrossReadsIsReassembled(t *testing.T) {
	clock := fakes.NewFakeClock()
	transport := fakes.NewFakeTransport(clock)
	client := bridge.NewJSONLinesClient(transport, clock, fakes.NewFakeLog())

	transport.OnWrite(func(raw []byte) {
		var request wire.Request
		if err := json.Unmarshal(raw, &request); err != nil {
			t.Errorf("request: %v", err)
			return
		}
		line, err := json.Marshal(wire.Response{
			ID:     request.ID,
			Result: json.RawMessage(`{"index":42}`),
		})
		if err != nil {
			t.Errorf("response: %v", err)
			return
		}
		line = append(line, '\n')
		transport.QueueRead(line[:5])
		transport.QueueRead(line[5:])
	})

	index, err := client.NextSpeechIndex()
	if err != nil {
		t.Fatalf("NextSpeechIndex: %v", err)
	}
	if index != 42 {
		t.Errorf("index = %d, want 42", index)
	}
}

func TestBufferedFramesAreDrainedBeforeReadingAgain(t *testing.T) {
	clock := fakes.NewFakeClock()
	transport := fakes.NewFakeTransport(clock)
	client := bridge.NewJSONLinesClient(transport, clock, fakes.NewFakeLog())

	// Both answers arrive in one chunk, in response to the first request.
	transport.OnWrite(func(raw []byte) {
		var request wire.Request
		if err := json.Unmarshal(raw, &request); err != nil || request.ID != 1 {
			return
		}
		transport.QueueRead([]byte(
			`{"id":1,"result":{"index":1}}` + "\n" +
				`{"id":2,"result":{"index":2}}` + "\n"))
	})

	first, err := client.NextSpeechIndex()
	if err != nil {
		t.Fatalf("first NextSpeechIndex: %v", err)
	}
	second, err := client.NextSpeechIndex()
	if err != nil {
		t.Fatalf("second NextSpeechIndex: %v", err)
	}
	if first != 1 || second != 2 {
		t.Errorf("indices = %d, %d; want 1, 2", first, second)
	}
}

func TestAnUnmatchedResponseIDEndsTheConnection(t *testing.T) {
	clock := fakes.NewFakeClock()
	transport := fakes.NewFakeTransport(clock)
	client := bridge.NewJSONLinesClient(transport, clock, fakes.NewFakeLog())
	transport.QueueLine(`{"id":9999,"result":{"index":0}}`)

	if _, err := client.NextSpeechIndex(); err == nil {
		t.Fatal("an unmatched id was accepted")
	}
	if !transport.Closed() {
		t.Error("an unmatched id did not end the connection")
	}
}

func TestAnUnreadableLineEndsTheConnection(t *testing.T) {
	clock := fakes.NewFakeClock()
	transport := fakes.NewFakeTransport(clock)
	client := bridge.NewJSONLinesClient(transport, clock, fakes.NewFakeLog())
	transport.QueueLine(`this is not JSON`)

	if _, err := client.Ping(); err == nil {
		t.Fatal("an unreadable line was accepted")
	}
	if !transport.Closed() {
		t.Error("a protocol fault did not end the connection")
	}
}

func TestConfigValuesRideThroughAsOpaqueJSON(t *testing.T) {
	client, _ := newClient(t, func(request wire.Request) (any, error) {
		var params wire.SetConfigParams
		if err := json.Unmarshal(request.Params, &params); err != nil {
			t.Fatalf("params: %v", err)
		}
		return wire.ConfigResult{Value: params.Value}, nil
	})

	got, err := client.SetConfig([]string{"speech", "outputDevice"}, json.RawMessage(`{"nested":[1,2]}`))
	if err != nil {
		t.Fatalf("SetConfig: %v", err)
	}
	if string(got) != `{"nested":[1,2]}` {
		t.Errorf("value = %s, want the bytes to survive the round trip", got)
	}
}

func TestByeOnAConnectionThatIsAlreadyGoneSucceeds(t *testing.T) {
	client, transport := newClient(t, nil)
	transport.QueueEOF()
	if _, err := client.Ping(); !errors.Is(err, bridge.ErrConnectionLost) {
		t.Fatalf("setup: Ping error = %v", err)
	}

	if err := client.Bye(); err != nil {
		t.Errorf("Bye after a loss = %v, want nil", err)
	}
}

func TestCloseIsIdempotent(t *testing.T) {
	client, _ := newClient(t, nil)

	if err := client.Close(); err != nil {
		t.Fatalf("first Close: %v", err)
	}
	if err := client.Close(); err != nil {
		t.Errorf("second Close: %v", err)
	}
}
