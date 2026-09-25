// screenreader-mcp adapters -- JSONLinesClient: the bridge client.
// Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
//
// ROLE: adapter implementing every capability port plus SessionLifecycle over one bridge connection.
// BUILT BY: adapters/bridge/handshake.go, which hands it out as the capability ports the reader announced.
package bridge

import (
	"bytes"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"os"
	"sync"
	"time"

	adapterports "github.com/marlon-sousa/screen-readers-mcp/server/adapters/ports"
	"github.com/marlon-sousa/screen-readers-mcp/server/adapters/wire"
	"github.com/marlon-sousa/screen-readers-mcp/server/domain/ports"
)

// DefaultCallTimeout is generous because the bridge answers only after NVDA's main thread has processed the command.
const DefaultCallTimeout = 15 * time.Second

// contractWaitDefault mirrors protocol.py's default for the speech waits; it only sizes the local deadline, the request still omits the field.
const contractWaitDefault = 5 * time.Second

// contractUserReplyWaitDefault must match protocol.py's `waitForUserReply` default, or the client gives up first and desynchronises the response stream.
const contractUserReplyWaitDefault = 30 * time.Second

// waitSlack lets the bridge's own timeout fire first, so the agent gets `found: false` rather than a lost connection.
const waitSlack = 5 * time.Second

// ErrConnectionLost aliases the domain's sentinel so both halves recognise one event.
var ErrConnectionLost = ports.ErrConnectionLost

// BridgeError is the bridge refusing one command; the session survives it, so it must never tear anything down.
type BridgeError struct {
	Command wire.Command
	Message string
}

func (e *BridgeError) Error() string {
	return fmt.Sprintf("bridge refused %s: %s", e.Command, e.Message)
}

// TimeoutError is the client giving up on a command the bridge never answered.
type TimeoutError struct {
	Command wire.Command
	Waited  time.Duration
}

func (e *TimeoutError) Error() string {
	return fmt.Sprintf("bridge did not answer %s within %s", e.Command, e.Waited)
}

// JSONLinesClient is safe for concurrent use: a heartbeat may run while a tool call is in flight.
type JSONLinesClient struct {
	transport adapterports.Transport
	clock     ports.Clock
	log       ports.Log

	mu     sync.Mutex
	nextID int
	lines  lineReader
	lost   bool
}

var (
	_ ports.SpeechReader     = (*JSONLinesClient)(nil)
	_ ports.BrailleReader    = (*JSONLinesClient)(nil)
	_ ports.LogReader        = (*JSONLinesClient)(nil)
	_ ports.GestureSender    = (*JSONLinesClient)(nil)
	_ ports.FocusInspector   = (*JSONLinesClient)(nil)
	_ ports.StateInspector   = (*JSONLinesClient)(nil)
	_ ports.ConfigAccessor   = (*JSONLinesClient)(nil)
	_ ports.Interact         = (*JSONLinesClient)(nil)
	_ ports.TextTyper        = (*JSONLinesClient)(nil)
	_ ports.GuidanceReader   = (*JSONLinesClient)(nil)
	_ ports.SessionLifecycle = (*JSONLinesClient)(nil)
)

func NewJSONLinesClient(transport adapterports.Transport, clock ports.Clock, log ports.Log) *JSONLinesClient {
	return &JSONLinesClient{transport: transport, clock: clock, log: log, nextID: 1}
}

func speechEntries(entries []wire.SpeechEntry) []ports.SpeechEntry {
	mapped := make([]ports.SpeechEntry, 0, len(entries))
	for _, e := range entries {
		mapped = append(mapped, ports.SpeechEntry{
			Text:        e.Text,
			Index:       e.Index,
			LogPosition: e.LogPosition,
			// Optional on the wire, so an older bridge's field reads empty.
			EmittedAt: derefString(e.EmittedAt),
		})
	}
	return mapped
}

func observation(entries []wire.SpeechEntry, from, to int, state *wire.StateResult) ports.Observation {
	observed := ports.Observation{
		Speech:    speechEntries(entries),
		FromIndex: from,
		ToIndex:   to,
	}
	// Absent stays absent: a reader without the `state` capability reports no snapshot.
	if state != nil {
		observed.State = &ports.ReaderState{
			BrowseMode: string(state.BrowseMode),
			SpeechMode: state.SpeechMode,
			SleepMode:  state.SleepMode,
			InputHelp:  state.InputHelp,
		}
	}
	return observed
}

// callTimeoutFor adds the grace the bridge spends per gesture, so a long batch is not reported as a timeout.
func callTimeoutFor(graceMs int, presses int) time.Duration {
	if graceMs <= 0 || presses <= 0 {
		return DefaultCallTimeout
	}
	return DefaultCallTimeout + time.Duration(graceMs*presses)*time.Millisecond
}

func brailleEntries(entries []wire.BrailleEntry) []ports.BrailleEntry {
	mapped := make([]ports.BrailleEntry, 0, len(entries))
	for _, e := range entries {
		mapped = append(mapped, ports.BrailleEntry{
			Text:        e.Text,
			Index:       e.Index,
			LogPosition: e.LogPosition,
			EmittedAt:   derefString(e.EmittedAt),
		})
	}
	return mapped
}

// copyInt keeps nil distinct from 0, because command id 0 is a real id.
func copyInt(v *int) *int {
	if v == nil {
		return nil
	}
	copied := *v
	return &copied
}

// derefInt reads a field nullable only because its default equals the domain's 0.
func derefInt(v *int) int {
	if v == nil {
		return 0
	}
	return *v
}

func derefString(v *string) string {
	if v == nil {
		return ""
	}
	return *v
}

func (c *JSONLinesClient) SpeechSince(sinceIndex int) (ports.SpeechRange, error) {
	var result wire.SpeechResult
	err := c.call(wire.CommandGetSpeech, wire.GetSpeechParams{SinceIndex: sinceIndex}, &result, DefaultCallTimeout)
	if err != nil {
		return ports.SpeechRange{}, err
	}
	return ports.SpeechRange{
		Entries:   speechEntries(result.Entries),
		FromIndex: result.FromIndex,
		ToIndex:   result.ToIndex,
	}, nil
}

func (c *JSONLinesClient) LastSpeech() (ports.LastSpeech, error) {
	var result wire.LastSpeechResult
	if err := c.call(wire.CommandGetLastSpeech, nil, &result, DefaultCallTimeout); err != nil {
		return ports.LastSpeech{}, err
	}
	return ports.LastSpeech{
		Text:        result.Text,
		Index:       result.Index,
		LogPosition: derefInt(result.LogPosition),
		EmittedAt:   derefString(result.EmittedAt),
	}, nil
}

func (c *JSONLinesClient) NextSpeechIndex() (int, error) {
	var result wire.NextIndexResult
	if err := c.call(wire.CommandGetNextSpeechIndex, nil, &result, DefaultCallTimeout); err != nil {
		return 0, err
	}
	return result.Index, nil
}

func (c *JSONLinesClient) WaitForSpeech(wait ports.SpeechWait) (ports.SpeechMatch, error) {
	params := wire.WaitForSpeechParams{Text: wait.Text}
	if wait.AfterIndex != nil {
		after := *wait.AfterIndex
		params.AfterIndex = &after
	}
	if wait.Timeout > 0 {
		seconds := wait.Timeout.Seconds()
		params.Timeout = &seconds
	}
	var result wire.WaitForSpeechResult
	if err := c.call(wire.CommandWaitForSpeech, params, &result, waitBudget(wait.Timeout)); err != nil {
		return ports.SpeechMatch{}, err
	}
	return ports.SpeechMatch{
		Found:       result.Found,
		Index:       result.Index,
		Text:        result.Text,
		LogPosition: derefInt(result.LogPosition),
		EmittedAt:   derefString(result.EmittedAt),
	}, nil
}

func (c *JSONLinesClient) WaitForSpeechToFinish(timeout time.Duration) (bool, error) {
	var params wire.WaitToFinishParams
	if timeout > 0 {
		seconds := timeout.Seconds()
		params.Timeout = &seconds
	}
	var result wire.WaitToFinishResult
	if err := c.call(wire.CommandWaitForSpeechToFinish, params, &result, waitBudget(timeout)); err != nil {
		return false, err
	}
	return result.Finished, nil
}

func (c *JSONLinesClient) BrailleSince(sinceIndex int) (ports.BrailleRange, error) {
	var result wire.BrailleResult
	err := c.call(wire.CommandGetBraille, wire.GetBrailleParams{SinceIndex: sinceIndex}, &result, DefaultCallTimeout)
	if err != nil {
		return ports.BrailleRange{}, err
	}
	return ports.BrailleRange{
		Entries:   brailleEntries(result.Entries),
		FromIndex: result.FromIndex,
		ToIndex:   result.ToIndex,
	}, nil
}

func (c *JSONLinesClient) PressGestures(ids []string, graceMs int, announce string) (ports.GestureOutcome, error) {
	var result wire.GestureResult
	params := wire.PressGestureParams{Gestures: ids, GraceMs: &graceMs, Announce: &announce}
	if err := c.call(wire.CommandPressGesture, params, &result, callTimeoutFor(graceMs, len(ids))); err != nil {
		return ports.GestureOutcome{}, err
	}
	pressed := make([]ports.GesturePress, 0, len(result.Pressed))
	for _, p := range result.Pressed {
		pressed = append(pressed, ports.GesturePress{
			Gesture:    p.Gesture,
			SpeechFrom: p.SpeechFrom,
			SpeechTo:   p.SpeechTo,
		})
	}
	return ports.GestureOutcome{
		Observation: observation(result.Speech, result.SpeechFrom, result.SpeechTo, result.State),
		Pressed:     pressed,
	}, nil
}

func (c *JSONLinesClient) TypeText(text string, graceMs int, announce string) (ports.TypeOutcome, error) {
	var result wire.TypeResult
	params := wire.TypeParams{Text: text, GraceMs: &graceMs, Announce: &announce}
	if err := c.call(wire.CommandTypeText, params, &result, callTimeoutFor(graceMs, 1)); err != nil {
		return ports.TypeOutcome{}, err
	}
	return ports.TypeOutcome{
		Observation: observation(result.Speech, result.SpeechFrom, result.SpeechTo, result.State),
		Typed:       result.Typed,
	}, nil
}

func (c *JSONLinesClient) Announce(text string) error {
	// The bridge can report only that it spoke, not that a human listened.
	return c.call(wire.CommandAnnounce, wire.AnnounceParams{Text: text}, nil, DefaultCallTimeout)
}

func (c *JSONLinesClient) AskUser(prompt string) (string, error) {
	var result wire.AskUserResult
	if err := c.call(wire.CommandAskUser, wire.AskUserParams{Prompt: prompt}, &result, DefaultCallTimeout); err != nil {
		return "", err
	}
	return result.Ticket, nil
}

func (c *JSONLinesClient) WaitForUserReply(ticket string, timeout time.Duration) (ports.UserReply, error) {
	params := wire.WaitForUserReplyParams{Ticket: ticket}
	if timeout > 0 {
		seconds := timeout.Seconds()
		params.Timeout = &seconds
	}
	var result wire.WaitForUserReplyResult
	budget := waitBudgetFrom(timeout, contractUserReplyWaitDefault)
	if err := c.call(wire.CommandWaitForUserReply, params, &result, budget); err != nil {
		return ports.UserReply{}, err
	}
	text := ""
	if result.Text != nil {
		text = *result.Text
	}
	return ports.UserReply{Answered: result.Answered, Text: text}, nil
}

func (c *JSONLinesClient) FocusInfo() (ports.FocusInfo, error) {
	var result wire.FocusInfoResult
	if err := c.call(wire.CommandGetFocusInfo, nil, &result, DefaultCallTimeout); err != nil {
		return ports.FocusInfo{}, err
	}
	return ports.FocusInfo{
		Name:      result.Name,
		Role:      result.Role,
		States:    result.States,
		Value:     result.Value,
		AppModule: result.AppModule,
	}, nil
}

func (c *JSONLinesClient) State() (ports.ReaderState, error) {
	var result wire.StateResult
	if err := c.call(wire.CommandGetState, nil, &result, DefaultCallTimeout); err != nil {
		return ports.ReaderState{}, err
	}
	return ports.ReaderState{
		BrowseMode: string(result.BrowseMode),
		SpeechMode: result.SpeechMode,
		SleepMode:  result.SleepMode,
		InputHelp:  result.InputHelp,
	}, nil
}

// SetState forwards the fields present; the bridge refuses what the reader cannot set.
func (c *JSONLinesClient) SetState(request ports.StateWrite) (ports.StateWriteResult, error) {
	params := wire.SetStateParams{}
	if request.BrowseMode != nil {
		mode := wire.BrowseMode(*request.BrowseMode)
		params.BrowseMode = &mode
	}
	var result wire.SetStateResult
	if err := c.call(wire.CommandSetState, params, &result, DefaultCallTimeout); err != nil {
		return ports.StateWriteResult{}, err
	}
	return ports.StateWriteResult{
		State: ports.ReaderState{
			BrowseMode: string(result.State.BrowseMode),
			SpeechMode: result.State.SpeechMode,
			SleepMode:  result.State.SleepMode,
			InputHelp:  result.State.InputHelp,
		},
		Changed: result.Changed,
	}, nil
}

func (c *JSONLinesClient) GetConfig(keyPath []string) (json.RawMessage, error) {
	var result wire.ConfigResult
	err := c.call(wire.CommandGetConfig, wire.GetConfigParams{KeyPath: keyPath}, &result, DefaultCallTimeout)
	if err != nil {
		return nil, err
	}
	return result.Value, nil
}

func (c *JSONLinesClient) SetConfig(keyPath []string, value json.RawMessage) (json.RawMessage, error) {
	var result wire.ConfigResult
	params := wire.SetConfigParams{KeyPath: keyPath, Value: value}
	if err := c.call(wire.CommandSetConfig, params, &result, DefaultCallTimeout); err != nil {
		return nil, err
	}
	return result.Value, nil
}

func (c *JSONLinesClient) GetLog(params ports.GetLogParams) (ports.LogSliceResult, error) {
	wireParams := wire.GetLogParams{}
	// The anchors are mutually exclusive and forwarded as given; the bridge refuses more than one.
	wireParams.SincePosition = copyInt(params.SincePosition)
	if params.LastSeconds != nil {
		seconds := *params.LastSeconds
		wireParams.LastSeconds = &seconds
	}
	if params.CommandID != nil {
		wireParams.CommandId = params.CommandID
	}
	if params.Windows != 0 {
		w := params.Windows
		wireParams.Windows = &w
	}
	if params.MinLevel != nil {
		lvl := wire.LogLevel(*params.MinLevel)
		wireParams.MinLevel = &lvl
	}
	wireParams.Contains = params.Contains
	wireParams.Exclude = params.Exclude
	wireParams.Fields = params.Fields
	if params.MaxEntries != 0 {
		m := params.MaxEntries
		wireParams.MaxEntries = &m
	}
	var wireResult wire.LogSliceResult
	if err := c.call(wire.CommandGetLog, wireParams, &wireResult, DefaultCallTimeout); err != nil {
		return ports.LogSliceResult{}, err
	}
	return ports.LogSliceResult{
		Text:            wireResult.Text,
		Entries:         wireResult.Entries,
		Matched:         wireResult.Matched,
		Truncated:       wireResult.Truncated,
		NextPosition:    wireResult.NextPosition,
		FromCommandID:   copyInt(wireResult.FromCommandId),
		ToCommandID:     copyInt(wireResult.ToCommandId),
		CapturedAtLevel: string(wireResult.CapturedAtLevel),
	}, nil
}

func (c *JSONLinesClient) LogPosition() (ports.LogPosition, error) {
	var result wire.LogPositionResult
	if err := c.call(wire.CommandGetLogPosition, nil, &result, DefaultCallTimeout); err != nil {
		return ports.LogPosition{}, err
	}
	return ports.LogPosition{Position: result.Position, Time: result.Time}, nil
}

func (c *JSONLinesClient) WaitForLog(wait ports.LogWait) (ports.LogMatch, error) {
	params := wire.WaitForLogParams{Contains: wait.Contains}
	if wait.Timeout > 0 {
		seconds := wait.Timeout.Seconds()
		params.Timeout = &seconds
	}
	if wait.MinLevel != nil {
		level := wire.LogLevel(*wait.MinLevel)
		params.MinLevel = &level
	}
	var result wire.WaitForLogResult
	if err := c.call(wire.CommandWaitForLog, params, &result, waitBudget(wait.Timeout)); err != nil {
		return ports.LogMatch{}, err
	}
	return ports.LogMatch{Found: result.Found, Position: result.Position, Text: derefString(result.Text)}, nil
}

func (c *JSONLinesClient) SetLogLevel(level string) (ports.LogLevelResult, error) {
	wireLevel := wire.LogLevel(level)
	wireParams := wire.SetLogLevelParams{Level: wireLevel}
	var wireResult wire.LogLevelResult
	if err := c.call(wire.CommandSetLogLevel, wireParams, &wireResult, DefaultCallTimeout); err != nil {
		return ports.LogLevelResult{}, err
	}
	return ports.LogLevelResult{
		Level:    string(wireResult.Level),
		Previous: string(wireResult.Previous),
	}, nil
}

// Guidance returns the bridge's text for the persona fixed at `hello`, untouched.
func (c *JSONLinesClient) Guidance() (ports.ReaderGuidance, error) {
	var result wire.GetGuidanceResult
	if err := c.call(wire.CommandGetGuidance, nil, &result, DefaultCallTimeout); err != nil {
		return ports.ReaderGuidance{}, err
	}
	return ports.ReaderGuidance{
		Persona:    result.Persona,
		Recognised: result.Recognised,
		Text:       result.Text,
	}, nil
}

// Snapshot sends a bound only when the agent set it; the wire's zero means no limit.
func (c *JSONLinesClient) Snapshot(bounds ports.DocumentBounds) (ports.DocumentSnapshot, error) {
	params := wire.DocumentSnapshotParams{}
	if bounds.FromLine != 0 {
		from := bounds.FromLine
		params.FromLine = &from
	}
	if bounds.MaxLines != 0 {
		maxLines := bounds.MaxLines
		params.MaxLines = &maxLines
	}
	if bounds.MaxChars != 0 {
		maxChars := bounds.MaxChars
		params.MaxChars = &maxChars
	}

	var result wire.DocumentSnapshotResult
	if err := c.call(wire.CommandGetDocumentSnapshot, params, &result, DefaultCallTimeout); err != nil {
		return ports.DocumentSnapshot{}, err
	}

	lines := make([]ports.SnapshotLine, 0, len(result.Lines))
	for _, line := range result.Lines {
		lines = append(lines, ports.SnapshotLine{Line: line.Line, Text: line.Text})
	}
	// An omitted `truncatedBy` means the read was not cut off.
	truncatedBy := string(wire.TruncatedByNone)
	if result.TruncatedBy != nil {
		truncatedBy = string(*result.TruncatedBy)
	}
	return ports.DocumentSnapshot{
		HasDocument: result.HasDocument,
		CapturedAt:  result.CapturedAt,
		Title:       derefString(result.Title),
		Lines:       lines,
		FromLine:    derefInt(result.FromLine),
		ToLine:      derefInt(result.ToLine),
		TruncatedBy: truncatedBy,
	}, nil
}

func (c *JSONLinesClient) Ping() (ports.PingReport, error) {
	var result wire.PingResult
	if err := c.call(wire.CommandPing, nil, &result, DefaultCallTimeout); err != nil {
		return ports.PingReport{}, err
	}
	// A pointer, so "this bridge does not say" survives rather than collapsing into false.
	return ports.PingReport{Suppressing: result.Suppressing}, nil
}

// Bye treats a connection already gone as success, since the session is over either way.
func (c *JSONLinesClient) Bye() error {
	err := c.call(wire.CommandBye, nil, nil, DefaultCallTimeout)
	if errors.Is(err, ErrConnectionLost) {
		return nil
	}
	return err
}

// Close is idempotent, so every teardown path may call it.
func (c *JSONLinesClient) Close() error {
	c.mu.Lock()
	defer c.mu.Unlock()
	if c.lost {
		return nil
	}
	c.lost = true
	return c.transport.Close()
}

// waitBudget sizes the local deadline so the bridge's own timeout always fires first.
func waitBudget(requested time.Duration) time.Duration {
	return waitBudgetFrom(requested, contractWaitDefault)
}

func waitBudgetFrom(requested, contractDefault time.Duration) time.Duration {
	if requested <= 0 {
		requested = contractDefault
	}
	return requested + waitSlack
}

// call holds one lock across id allocation, write and read, so a response can belong only to the waiting request.
func (c *JSONLinesClient) call(cmd wire.Command, params any, result any, budget time.Duration) error {
	c.mu.Lock()
	defer c.mu.Unlock()

	if c.lost {
		return ErrConnectionLost
	}

	id := c.nextID
	c.nextID++

	request := wire.Request{ID: id, Cmd: string(cmd)}
	if params != nil {
		encoded, err := json.Marshal(params)
		if err != nil {
			return fmt.Errorf("encoding %s params: %w", cmd, err)
		}
		request.Params = encoded
	}
	line, err := json.Marshal(request)
	if err != nil {
		return fmt.Errorf("encoding %s: %w", cmd, err)
	}
	if err := c.writeAll(append(line, '\n')); err != nil {
		return err
	}

	deadline := c.clock.Now().Add(budget)
	response, err := c.readResponse(deadline)
	if err != nil {
		if errors.Is(err, errDeadline) {
			return &TimeoutError{Command: cmd, Waited: budget}
		}
		return err
	}
	if response.ID != id {
		// Impossible while calls are serialised, so the peer is not speaking this contract.
		c.markLost()
		return fmt.Errorf("bridge answered id %d while waiting for %d (%s)", response.ID, id, cmd)
	}
	if response.Error != nil {
		return &BridgeError{Command: cmd, Message: response.Error.Message}
	}
	if result == nil {
		return nil
	}
	if err := json.Unmarshal(response.Result, result); err != nil {
		return fmt.Errorf("decoding %s result: %w", cmd, err)
	}
	return nil
}

var errDeadline = errors.New("deadline exceeded")

func (c *JSONLinesClient) readResponse(deadline time.Time) (wire.Response, error) {
	line, err := c.readLine(deadline)
	if err != nil {
		return wire.Response{}, err
	}
	var response wire.Response
	if err := json.Unmarshal(line, &response); err != nil {
		// A line that is not a JSON object is a protocol fault, fatal to the connection.
		c.markLost()
		return wire.Response{}, fmt.Errorf("bridge sent an unreadable line: %w", err)
	}
	return response, nil
}

// readLine drains buffered frames before reading the transport, so a poll timeout never loses an arrived message.
func (c *JSONLinesClient) readLine(deadline time.Time) ([]byte, error) {
	for {
		if line, ok := c.lines.next(); ok {
			return line, nil
		}
		buffer := make([]byte, 4096)
		n, err := c.transport.Read(buffer)
		if n > 0 {
			c.lines.feed(buffer[:n])
			continue
		}
		switch {
		case err == nil:
			// Nothing read; fall through to the deadline check.
		case errors.Is(err, os.ErrDeadlineExceeded):
			// The seam's poll contract: idle, not broken.
		case errors.Is(err, io.EOF):
			c.markLost()
			return nil, ErrConnectionLost
		default:
			// A reset and a clean close are the same event here.
			c.markLost()
			return nil, fmt.Errorf("%w: %v", ErrConnectionLost, err)
		}
		if !c.clock.Now().Before(deadline) {
			return nil, errDeadline
		}
	}
}

// writeAll writes every byte, since a transport is free to write short.
func (c *JSONLinesClient) writeAll(data []byte) error {
	for len(data) > 0 {
		n, err := c.transport.Write(data)
		if err != nil {
			c.markLost()
			return fmt.Errorf("%w: %v", ErrConnectionLost, err)
		}
		data = data[n:]
	}
	return nil
}

// markLost requires the caller to hold the lock.
func (c *JSONLinesClient) markLost() {
	if c.lost {
		return
	}
	c.lost = true
	c.log.Debugf("bridge connection ended")
	_ = c.transport.Close()
}

// lineReader reassembles transport chunks into newline-delimited frames.
type lineReader struct {
	buffer []byte
}

func (r *lineReader) feed(chunk []byte) {
	r.buffer = append(r.buffer, chunk...)
}

func (r *lineReader) next() ([]byte, bool) {
	index := bytes.IndexByte(r.buffer, '\n')
	if index < 0 {
		return nil, false
	}
	line := make([]byte, index)
	copy(line, r.buffer[:index])
	r.buffer = r.buffer[index+1:]
	return line, true
}
