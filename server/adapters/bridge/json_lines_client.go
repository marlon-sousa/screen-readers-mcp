// screenreader-mcp adapters -- JSONLinesClient: the bridge client.
// Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
//
// ROLE: adapter. IMPLEMENTS all six capability ports (domain/ports/{speech,
// braille,gesture,focus,state,config}_*.go) plus ports.SessionLifecycle, over
// one bridge connection.
// DEPENDS ON: the Transport seam (adapters/ports) -- never a concrete transport,
// which is what keeps every decision here testable against scripted bytes while
// the socket and the pipe stay dumb leaves. Also the Clock port (deadlines are
// never read from the wall clock) and the Log port.
// BUILT BY: adapters/bridge/handshake.go, which dials, hands the transport over,
// and then hands the finished client out as the capability ports the reader
// announced.
//
// This file is where ALL the decisions live: correlation ids, request/response
// matching, JSON-lines framing, deadlines, and the wire<->domain mapping. That
// last one is the load-bearing part -- it is the only place in the server where
// a generated wire type meets a domain type, which is what lets the domain stay
// ignorant of the contract's shape (spec 0013, "the domain never speaks wire
// types").
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

// DefaultCallTimeout is how long an ordinary command may take before the client
// gives up on the connection.
//
// Generous, because the bridge answers on NVDA's main thread and a gesture
// blocks until the reader has processed it; short enough that a bridge that
// died mid-command does not hang the agent indefinitely.
const DefaultCallTimeout = 15 * time.Second

// contractWaitDefault mirrors the wire contract's own default timeout for the
// speech-waiting commands (protocol.py's 5.0 seconds).
//
// It is used ONLY to size the local deadline when the caller did not ask for a
// specific timeout -- the request still omits the field, so the bridge applies
// its own default and stays the single authority on the value. Duplicating it
// here to compute a budget is safe in a way that sending it would not be: if
// the contract's default changed, the worst outcome is a budget that is too
// generous or too tight by seconds, not two peers disagreeing about when to
// stop waiting.
//
// That tolerance only holds while every waiting command shares one default, and
// `waitForUserReply` does not -- hence contractUserReplyWaitDefault below.
const contractWaitDefault = 5 * time.Second

// contractUserReplyWaitDefault mirrors protocol.py's own default for
// `waitForUserReply.timeout`, which is 30 s rather than the 5 s the
// speech-waiting commands share.
//
// It exists because the budget must always outlast the wait the BRIDGE will
// actually perform. Sizing an omitted user-reply timeout from the 5 s default
// gave a 10 s budget against a 30 s wait: the client gave up first, returned a
// timeout instead of `answered: false`, and left the bridge's late reply unread
// in the stream -- where the next call read it, saw a mismatched id, and declared
// the connection lost, one command after the mistake.
//
// The request still OMITS the field either way, so the bridge remains the single
// authority on the value; this only sizes the local deadline. Callers are
// expected to send a timeout explicitly (tools.defaultPollTimeout does), and
// this is what keeps the port safe for one that does not.
const contractUserReplyWaitDefault = 30 * time.Second

// waitSlack is added to a waiting command's own timeout before the client gives
// up, so that the BRIDGE's timeout always fires first and the agent gets
// `found: false` rather than a lost connection.
const waitSlack = 5 * time.Second

// ErrConnectionLost is the connection ending underneath a call: EOF, a reset, or
// a close.
//
// An ALIAS of the domain's sentinel, not a second one (spec 0013's 10b delivery
// amendment 2): the party that must recognise a loss is the connection
// controller, which retracts the gated tools and records why, and the domain
// cannot import this package. Declaring it here and re-declaring it there would
// give the two halves of one event two identities.
var ErrConnectionLost = ports.ErrConnectionLost

// BridgeError is the bridge answering a command with an error.
//
// Distinct from a transport failure on purpose: protocol.md §3 says an
// established session is TOLERANT -- a failing command yields an error response
// and the session keeps running -- so this must never be mistaken for a
// connection loss and must never tear anything down.
type BridgeError struct {
	Command wire.Command
	Message string
}

func (e *BridgeError) Error() string {
	return fmt.Sprintf("bridge refused %s: %s", e.Command, e.Message)
}

// TimeoutError is the client giving up on a command that the bridge never
// answered.
type TimeoutError struct {
	Command wire.Command
	Waited  time.Duration
}

func (e *TimeoutError) Error() string {
	return fmt.Sprintf("bridge did not answer %s within %s", e.Command, e.Waited)
}

// JSONLinesClient speaks the wire contract over one transport.
//
// Safe for concurrent use, and it has to be: 10b's connection controller sends
// a heartbeat while a tool call may be in flight. A single mutex serialises
// whole round trips rather than multiplexing by id, which is the right trade
// for a protocol that answers one request at a time over one connection -- it
// makes an unmatched id a genuine fault rather than an ordinary occurrence to
// be tolerated.
type JSONLinesClient struct {
	transport adapterports.Transport
	clock     ports.Clock
	log       ports.Log

	mu     sync.Mutex
	nextID int
	lines  lineReader
	lost   bool
}

// The compile-time proof that this one adapter really does satisfy the whole
// capability port set. Required, not optional (spec 0013): an adapter that falls
// behind its port fails the build rather than a test.
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

// NewJSONLinesClient wraps one already-connected transport.
func NewJSONLinesClient(transport adapterports.Transport, clock ports.Clock, log ports.Log) *JSONLinesClient {
	return &JSONLinesClient{transport: transport, clock: clock, log: log, nextID: 1}
}

// --- wire -> domain mapping helpers -------------------------------------------

// speechEntries maps captured utterances into domain vocabulary, coordinate and
// all. The wire carries one entry per utterance since spec 0021, each with the
// journal position it was captured at, so the mapping is one to one -- there is
// nothing to join and nothing to drop.
func speechEntries(entries []wire.SpeechEntry) []ports.SpeechEntry {
	mapped := make([]ports.SpeechEntry, 0, len(entries))
	for _, e := range entries {
		mapped = append(mapped, ports.SpeechEntry{
			Text:        e.Text,
			Index:       e.Index,
			LogPosition: e.LogPosition,
			// Optional on the wire, so a bridge older than spec 0028 simply
			// sends nothing and the field reads empty rather than failing.
			EmittedAt: derefString(e.EmittedAt),
		})
	}
	return mapped
}

// observation maps the half of a mutating result that pressGesture and typeText
// answer identically (spec 0025). One mapping, because the two shapes agreeing
// is the point: an agent reads the same window and the same resume coordinate
// from both tools.
func observation(entries []wire.SpeechEntry, from, to int, state *wire.StateResult) ports.Observation {
	observed := ports.Observation{
		Speech:    speechEntries(entries),
		FromIndex: from,
		ToIndex:   to,
	}
	// Absent stays absent: a reader serving no `state` capability reports no
	// snapshot, which is a different answer from "browse mode is empty string".
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

// callTimeoutFor stretches the standard call timeout by the grace the BRIDGE is
// about to spend, once per gesture in the batch. Without this a 20-key batch at
// the default 100 ms would spend 2 s inside a window the caller asked for and
// then be reported as a timed-out bridge.
func callTimeoutFor(graceMs int, presses int) time.Duration {
	if graceMs <= 0 || presses <= 0 {
		return DefaultCallTimeout
	}
	return DefaultCallTimeout + time.Duration(graceMs*presses)*time.Millisecond
}

// brailleEntries is speechEntries for braille updates.
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

// copyInt copies a nullable wire int, so the domain never aliases wire memory.
// Absent stays absent: a getLog anchored by position or time is attributable to
// no command, and command id 0 is a real id, so nil and 0 are different answers.
func copyInt(v *int) *int {
	if v == nil {
		return nil
	}
	copied := *v
	return &copied
}

// derefInt reads a wire field that is nullable only because it carries a DEFAULT
// -- logPosition on the single-entry speech results, whose default is the same 0
// the domain uses for "no coordinate". Distinct from copyInt above, where absent
// is a meaningful answer the domain has to keep.
func derefInt(v *int) int {
	if v == nil {
		return 0
	}
	return *v
}

// derefString is derefInt for a defaulted string field.
func derefString(v *string) string {
	if v == nil {
		return ""
	}
	return *v
}

// --- the capability ports, in domain vocabulary -------------------------------

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
	// The ids pass through untouched: gesture syntax is the reader's, and the
	// server routes it without interpreting it.
	var result wire.GestureResult
	params := wire.PressGestureParams{Gestures: ids, GraceMs: &graceMs, Announce: &announce}
	// The grace is spent INSIDE the bridge, so the reply cannot arrive before it
	// elapses: a call timeout that ignored it would turn a long deliberate
	// window into a transport failure.
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
	// The text passes through untouched: it is opaque content, routed exactly
	// as a gesture id is.
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
	// The result is an acknowledgement, so it is discarded: the bridge cannot
	// report whether a human listened, only that it spoke.
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

// --- the log capability port --------------------------------------------------

func (c *JSONLinesClient) GetLog(params ports.GetLogParams) (ports.LogSliceResult, error) {
	wireParams := wire.GetLogParams{}
	// The three anchors are mutually exclusive; the bridge refuses more than one,
	// so they are forwarded as given rather than reconciled into a precedence
	// rule here -- two places deciding that would be one too many.
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
	// waitBudget, like waitForSpeech: the call timeout has to outlast the wait the
	// caller asked for, or the transport gives up on a bridge that is doing
	// exactly what it was told.
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

// --- the guidance capability port ----------------------------------------------

// Guidance asks the bridge what it says about this session's persona.
//
// No parameters go out: the persona was fixed at `hello` and the bridge answers
// for that one (protocol.md §5). The text comes back OPAQUE and is not touched
// here -- not parsed, not trimmed, not checked -- because the whole point of the
// arrangement is that a bridge author writes for their own reader without
// agreeing a shape with this server.
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

// --- the lifecycle port -------------------------------------------------------

func (c *JSONLinesClient) Ping() (ports.PingReport, error) {
	var result wire.PingResult
	if err := c.call(wire.CommandPing, nil, &result, DefaultCallTimeout); err != nil {
		return ports.PingReport{}, err
	}
	// Carried as a POINTER, so "this bridge does not say" survives as itself
	// rather than collapsing into false (spec 0032).
	return ports.PingReport{Suppressing: result.Suppressing}, nil
}

// Bye asks the bridge to end the session and waits for its acknowledgement.
//
// A connection that is already gone is NOT an error here: the goal of Bye is
// "this session is over", and a peer that vanished has achieved it. Reporting a
// loss would make an ordinary disconnect look like a failure to the agent.
func (c *JSONLinesClient) Bye() error {
	err := c.call(wire.CommandBye, nil, nil, DefaultCallTimeout)
	if errors.Is(err, ErrConnectionLost) {
		return nil
	}
	return err
}

// Close drops the connection. Idempotent, so every teardown path may call it
// without first working out whether some other path already did.
func (c *JSONLinesClient) Close() error {
	c.mu.Lock()
	defer c.mu.Unlock()
	if c.lost {
		return nil
	}
	c.lost = true
	return c.transport.Close()
}

// --- framing, correlation and deadlines ---------------------------------------

// waitBudget sizes the local deadline for a waiting command so that the
// BRIDGE's own timeout is always the one that fires.
func waitBudget(requested time.Duration) time.Duration {
	return waitBudgetFrom(requested, contractWaitDefault)
}

// waitBudgetFrom is waitBudget for a command whose contract default is not the
// shared one. The fallback must be the default the BRIDGE will apply to an
// omitted timeout, or the client gives up mid-wait and desynchronises the
// response stream (see contractUserReplyWaitDefault).
func waitBudgetFrom(requested, contractDefault time.Duration) time.Duration {
	if requested <= 0 {
		requested = contractDefault
	}
	return requested + waitSlack
}

// call performs one request/response round trip.
//
// Serialised end to end: the id counter, the write and the read of the matching
// response all happen under one lock, so ids are consumed in the same order the
// requests are written and a response can only belong to the request that is
// waiting for it.
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
	// One JSON object per line, terminated by exactly one newline
	// (protocol.md §1). json.Marshal never emits an embedded newline, so the
	// framing needs nothing beyond the append.
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
		// Impossible while calls are serialised, so it means the peer is not
		// speaking this contract. Treat it as fatal to the connection rather
		// than skipping the frame and hoping.
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

// errDeadline is the internal signal that the caller's budget ran out; call
// turns it into a TimeoutError naming the command.
var errDeadline = errors.New("deadline exceeded")

// readResponse reads frames until one decodes, the deadline passes, or the
// connection ends.
func (c *JSONLinesClient) readResponse(deadline time.Time) (wire.Response, error) {
	line, err := c.readLine(deadline)
	if err != nil {
		return wire.Response{}, err
	}
	var response wire.Response
	if err := json.Unmarshal(line, &response); err != nil {
		// A line that is not a JSON object is a protocol fault, not a command
		// failure (protocol.md §2), so the connection does not survive it.
		c.markLost()
		return wire.Response{}, fmt.Errorf("bridge sent an unreadable line: %w", err)
	}
	return response, nil
}

// readLine returns the next complete frame.
//
// It drains what is already buffered BEFORE touching the transport, so a
// message that has already arrived is never lost to a poll timeout -- the same
// rule the bridge's own channel follows, and the reason both sides can use a
// short poll without dropping traffic.
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
			// A zero-length read with no error tells us nothing; fall
			// through to the deadline check rather than spinning on it.
		case errors.Is(err, os.ErrDeadlineExceeded):
			// The seam's poll contract: idle, not broken.
		case errors.Is(err, io.EOF):
			c.markLost()
			return nil, ErrConnectionLost
		default:
			// Any other transport error is an abrupt end of connection. A
			// client that dies mid-session resets rather than closing
			// cleanly, and the two are the same event to us.
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

// markLost records that this connection is finished. The caller already holds
// the lock.
func (c *JSONLinesClient) markLost() {
	if c.lost {
		return
	}
	c.lost = true
	c.log.Debugf("bridge connection ended")
	_ = c.transport.Close()
}

// lineReader reassembles transport chunks into newline-delimited frames. Its
// own type inside this file rather than a file of its own: it is a private
// helper of this adapter, exactly as the bridge's _LineReader is of its channel.
type lineReader struct {
	buffer []byte
}

func (r *lineReader) feed(chunk []byte) {
	r.buffer = append(r.buffer, chunk...)
}

// next pops one complete line, without its newline.
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
