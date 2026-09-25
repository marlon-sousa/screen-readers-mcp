// screenreader-mcp testsupport -- FakeBridge: a bridge speaking real wire frames.
// Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
// ROLE: test scaffolding: a whole fake bridge serving the real JSON-lines contract over an in-memory net.Pipe.
// USED BY: the headless integration tier, server/tests/.
package testsupport

import (
	"bufio"
	"encoding/json"
	"errors"
	"io"
	"net"
	"sync"
	"time"

	adapterports "github.com/marlon-sousa/screen-readers-mcp/server/adapters/ports"
	"github.com/marlon-sousa/screen-readers-mcp/server/adapters/wire"
)

type BridgeOptions struct {
	// Zero value announces a generic reader.
	Reader wire.ReaderInfo

	// Nil announces every group; an empty non-nil slice announces none.
	Capabilities []wire.Capability

	// Zero means this server's own version.
	ProtocolVersion int

	Synth   string
	LogPath string

	// Nil announces no field, as an older bridge does; the server must report "did not say", not "uncapped".
	SilenceCap *wire.SilenceCapInfo

	// Nil declares no field, as an older bridge does, so the server infers attendance from SilenceCap.
	Attended *bool

	// Nil says nothing, like an older bridge.
	Suppressing *bool

	// Answers `hello` without the guidance document, as an older bridge does, so the `getGuidance` fallback runs.
	OmitHandshakeGuidance bool
}

type FakeBridge struct {
	opts BridgeOptions

	mu       sync.Mutex
	handlers map[wire.Command]func(params json.RawMessage) (any, error)
	received []wire.Command
	byeSeen  bool
	persona  string
	conn     net.Conn
}

func EveryWireCapability() []wire.Capability {
	return []wire.Capability{
		wire.CapabilitySpeech, wire.CapabilityBraille, wire.CapabilityGestures,
		wire.CapabilityFocus, wire.CapabilityState, wire.CapabilityConfig,
		wire.CapabilityInteract, wire.CapabilityTyping, wire.CapabilityLog,
		wire.CapabilityGuidance,
	}
}

// DefaultGuidanceText is unlike anything the server writes, so it could only have come from the bridge.
const DefaultGuidanceText = "# fakereader's own guidance\n\nPress the fake key to do the fake thing.\n"

func NewFakeBridge(opts BridgeOptions) *FakeBridge {
	if opts.Reader.Name == "" {
		opts.Reader = wire.ReaderInfo{Name: "fakereader", Version: "1.0"}
	}
	if opts.Capabilities == nil {
		opts.Capabilities = EveryWireCapability()
	}
	if opts.ProtocolVersion == 0 {
		opts.ProtocolVersion = wire.ProtocolVersion
	}
	if opts.Synth == "" {
		opts.Synth = "fakesynth"
	}
	if opts.LogPath == "" {
		opts.LogPath = `C:\logs\session.log`
	}
	return &FakeBridge{opts: opts, handlers: map[wire.Command]func(json.RawMessage) (any, error){}}
}

// An error becomes an error response, which an established session survives.
func (b *FakeBridge) Handle(cmd wire.Command, fn func(params json.RawMessage) (any, error)) {
	b.mu.Lock()
	defer b.mu.Unlock()
	b.handlers[cmd] = fn
}

func (b *FakeBridge) Received() []wire.Command {
	b.mu.Lock()
	defer b.mu.Unlock()
	return append([]wire.Command(nil), b.received...)
}

func (b *FakeBridge) SawBye() bool {
	b.mu.Lock()
	defer b.mu.Unlock()
	return b.byeSeen
}

func (b *FakeBridge) Connect() adapterports.Transport {
	client, server := net.Pipe()
	go b.serve(server)
	return &connTransport{conn: client}
}

func (b *FakeBridge) Serve(conn net.Conn) { b.serve(conn) }

// DropConnection closes the connection without a `bye`, as a crashed reader does. Safe to call from inside a handler.
func (b *FakeBridge) DropConnection() {
	b.mu.Lock()
	conn := b.conn
	b.mu.Unlock()
	if conn != nil {
		_ = conn.Close()
	}
}

func (b *FakeBridge) serve(conn net.Conn) {
	defer conn.Close()
	b.mu.Lock()
	b.conn = conn
	b.mu.Unlock()
	lines := bufio.NewScanner(conn)
	for lines.Scan() {
		var request wire.Request
		if err := json.Unmarshal(lines.Bytes(), &request); err != nil {
			return // a malformed line is a protocol fault; drop the session
		}
		command := wire.Command(request.Cmd)

		b.mu.Lock()
		b.received = append(b.received, command)
		handler, hasHandler := b.handlers[command]
		if command == wire.CommandBye {
			b.byeSeen = true
		}
		b.mu.Unlock()

		var (
			result any
			err    error
		)
		switch {
		case command == wire.CommandHello:
			b.recordPersona(request.Params)
			result = b.helloResult()
		case command == wire.CommandPing:
			ok := true
			result = wire.PingResult{OK: &ok, Suppressing: b.opts.Suppressing}
		case command == wire.CommandBye:
			ok := true
			result = wire.AckResult{OK: &ok}
		case command == wire.CommandGetGuidance && !hasHandler:
			result = wire.GetGuidanceResult{
				Persona:    b.lastPersona(),
				Recognised: true,
				Text:       DefaultGuidanceText,
			}
		case hasHandler:
			result, err = handler(request.Params)
		default:
			// An unknown command is an error response, not a framing fault; the session continues.
			err = errors.New("unknown command " + request.Cmd)
		}

		if writeErr := b.respond(conn, request.ID, result, err); writeErr != nil {
			return
		}
		if command == wire.CommandBye {
			return
		}
	}
}

func (b *FakeBridge) Persona() string { return b.lastPersona() }

func (b *FakeBridge) lastPersona() string {
	b.mu.Lock()
	defer b.mu.Unlock()
	return b.persona
}

func (b *FakeBridge) recordPersona(params json.RawMessage) {
	var hello wire.HelloParams
	if err := json.Unmarshal(params, &hello); err != nil || hello.Persona == nil {
		return
	}
	b.mu.Lock()
	defer b.mu.Unlock()
	b.persona = *hello.Persona
}

func (b *FakeBridge) helloResult() wire.HelloResult {
	result := wire.HelloResult{
		ProtocolVersion: b.opts.ProtocolVersion,
		Reader:          b.opts.Reader,
		Capabilities:    b.opts.Capabilities,
		Mode:            wire.CaptureModeSilent,
		Synth:           b.opts.Synth,
		LogPath:         b.opts.LogPath,
		SilenceCap:      b.opts.SilenceCap,
		Attended:        b.opts.Attended,
	}
	if !b.opts.OmitHandshakeGuidance && b.announces(wire.CapabilityGuidance) {
		result.Guidance = b.guidanceDocument()
	}
	return result
}

// The handshake copy and `getGuidance` both come from here, as in the real bridge, so the two cannot disagree.
func (b *FakeBridge) guidanceDocument() *wire.GetGuidanceResult {
	if handler := b.handlerFor(wire.CommandGetGuidance); handler != nil {
		scripted, err := handler(nil)
		if err != nil {
			return nil
		}
		if document, ok := scripted.(wire.GetGuidanceResult); ok {
			return &document
		}
		return nil
	}
	return &wire.GetGuidanceResult{
		Persona:    b.lastPersona(),
		Recognised: true,
		Text:       DefaultGuidanceText,
	}
}

func (b *FakeBridge) handlerFor(command wire.Command) func(json.RawMessage) (any, error) {
	b.mu.Lock()
	defer b.mu.Unlock()
	return b.handlers[command]
}

func (b *FakeBridge) announces(capability wire.Capability) bool {
	for _, announced := range b.opts.Capabilities {
		if announced == capability {
			return true
		}
	}
	return false
}

func (b *FakeBridge) respond(conn net.Conn, id int, result any, failure error) error {
	response := wire.Response{ID: id}
	if failure != nil {
		response.Error = &wire.ErrorInfo{Message: failure.Error()}
	} else if result != nil {
		encoded, err := json.Marshal(result)
		if err != nil {
			return err
		}
		response.Result = encoded
	}
	line, err := json.Marshal(response)
	if err != nil {
		return err
	}
	_, err = conn.Write(append(line, '\n'))
	return err
}

// connTransport applies the seam's poll deadline exactly as the production leaves do.
type connTransport struct {
	conn net.Conn
}

func (t *connTransport) Read(p []byte) (int, error) {
	if err := t.conn.SetReadDeadline(time.Now().Add(adapterports.PollInterval)); err != nil {
		return 0, err
	}
	n, err := t.conn.Read(p)
	if err != nil && errors.Is(err, io.ErrClosedPipe) {
		return n, io.EOF
	}
	return n, err
}

func (t *connTransport) Write(p []byte) (int, error) { return t.conn.Write(p) }

func (t *connTransport) Close() error { return t.conn.Close() }
