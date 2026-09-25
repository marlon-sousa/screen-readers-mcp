// screenreader-mcp domain -- Connection: the session lifecycle controller.
// Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
//
// ROLE: controller owning the agent-initiated connection lifecycle: List, Connect, Disconnect, loss detection and the heartbeat.
// BUILT BY: wiring/wiring.go.
// USED BY: the four ungated tool controllers, through the ConnectionControl interface they declare.
//
// A failed connect returns the error and leaves the state Disconnected; this server never retries on its own.
package controllers

import (
	"errors"
	"fmt"
	"sync"
	"time"

	"github.com/marlon-sousa/screen-readers-mcp/server/domain/entities"
	"github.com/marlon-sousa/screen-readers-mcp/server/domain/ports"
)

// HeartbeatInterval keeps the connection honest; `ping` does not reset the bridge's command inactivity watchdog, so an abandoned session still ends.
const HeartbeatInterval = 20 * time.Second

type Connection struct {
	endpoints ports.EndpointSource
	probe     ports.EndpointProbe
	dialer    ports.SessionDialer
	clock     ports.Clock
	log       ports.Log

	// The heartbeat goroutine and a tool call reach the state at the same time.
	mu         sync.Mutex
	status     entities.ConnectionStatus
	connection *ports.ReaderConnection
}

func NewConnection(
	endpoints ports.EndpointSource,
	probe ports.EndpointProbe,
	dialer ports.SessionDialer,
	clock ports.Clock,
	log ports.Log,
) *Connection {
	return &Connection{
		endpoints: endpoints,
		probe:     probe,
		dialer:    dialer,
		clock:     clock,
		log:       log,
		status:    entities.ConnectionStatus{State: entities.Disconnected},
	}
}

// List dials nothing: the bridge serves one session at a time, so a probe would occupy the agent's slot.
func (c *Connection) List() entities.ReaderListing {
	readers := c.endpoints.Readers()

	var candidates []entities.Endpoint
	for _, reader := range readers {
		candidates = append(candidates, reader.Endpoints...)
	}
	return entities.BuildListing(readers, c.probe.Live(candidates))
}

func (c *Connection) Connect(readerName string, opts ports.SessionOptions) (*ports.ReaderConnection, error) {
	reader, err := c.find(readerName)
	if err != nil {
		return nil, err
	}

	c.mu.Lock()
	if c.connection != nil {
		live := c.connection.Session.Reader.Name
		c.mu.Unlock()
		// An error rather than a silent switch, which would pull the session from under a running task.
		return nil, fmt.Errorf(
			"a session with %q is already live; call disconnect_reader first", live)
	}
	c.status = entities.ConnectionStatus{State: entities.Connecting}
	c.mu.Unlock()

	connection, err := c.dialer.Dial(reader, opts)
	if err != nil {
		c.recordFailure(err)
		return nil, err
	}

	c.mu.Lock()
	c.connection = connection
	c.status = entities.ConnectionStatus{State: entities.Connected}
	c.mu.Unlock()

	c.log.Infof("connected to %q over %s; the reader announced %d capability(ies)",
		connection.Session.Reader.Name, connection.Endpoint,
		len(connection.Session.Capabilities.All()))
	return connection, nil
}

// Disconnect is not an error when nothing is connected, and an already-gone peer still yields a clean disconnect.
func (c *Connection) Disconnect() error {
	c.mu.Lock()
	connection := c.connection
	c.mu.Unlock()

	if connection == nil {
		return nil
	}

	byeErr := connection.Lifecycle.Bye()
	closeErr := connection.Lifecycle.Close()

	c.clear(entities.ConnectionStatus{State: entities.Disconnected})

	if byeErr != nil {
		c.log.Debugf("bye failed on disconnect: %v", byeErr)
	}
	if closeErr != nil {
		c.log.Debugf("closing the connection failed: %v", closeErr)
	}
	return nil
}

func (c *Connection) Status() entities.ConnectionStatus {
	c.mu.Lock()
	defer c.mu.Unlock()
	return c.status
}

// Current is the live connection, or nil.
func (c *Connection) Current() *ports.ReaderConnection {
	c.mu.Lock()
	defer c.mu.Unlock()
	return c.connection
}

// Verify makes a real round trip and records a loss it finds; nil when there is no session.
func (c *Connection) Verify() (ports.PingReport, error) {
	c.mu.Lock()
	connection := c.connection
	c.mu.Unlock()

	if connection == nil {
		return ports.PingReport{}, nil
	}

	report, err := connection.Lifecycle.Ping()
	if err == nil {
		return report, nil
	}
	if errors.Is(err, ports.ErrConnectionLost) {
		c.lose(err)
		return ports.PingReport{}, err
	}
	// A bridge that answered with a refusal is still there, so nothing is torn down.
	c.log.Debugf("ping was refused but the connection is alive: %v", err)
	return ports.PingReport{}, err
}

// RunHeartbeat sleeps on the Clock port, until stop is closed.
func (c *Connection) RunHeartbeat(stop <-chan struct{}) {
	for {
		select {
		case <-stop:
			return
		default:
		}

		c.clock.Sleep(HeartbeatInterval)

		select {
		case <-stop:
			return
		default:
		}

		_, _ = c.Verify()
	}
}

// Close ends the session, if any, at process shutdown.
func (c *Connection) Close() {
	_ = c.Disconnect()
}

func (c *Connection) find(name string) (entities.ConfiguredReader, error) {
	readers := c.endpoints.Readers()
	for _, reader := range readers {
		if reader.Name == name {
			return reader, nil
		}
	}

	// The error lists the known names so the agent can self-correct in the same turn.
	known := make([]string, 0, len(readers))
	for _, reader := range readers {
		known = append(known, reader.Name)
	}
	if len(known) == 0 {
		return entities.ConfiguredReader{}, fmt.Errorf(
			"unknown reader %q: no readers are configured", name)
	}
	return entities.ConfiguredReader{}, fmt.Errorf(
		"unknown reader %q: known readers are %v", name, known)
}

// recordFailure gives a protocol mismatch its own state, because the remedy is to update a component, not retry.
func (c *Connection) recordFailure(err error) {
	state := entities.Disconnected

	var mismatch *ports.ProtocolMismatchError
	if errors.As(err, &mismatch) {
		state = entities.Incompatible
	}

	c.mu.Lock()
	defer c.mu.Unlock()
	c.status = entities.ConnectionStatus{State: state, Reason: err.Error()}
	c.log.Errorf("connect failed: %v", err)
}

// lose records an observed connection loss; the agent may reconnect whenever it chooses.
func (c *Connection) lose(cause error) {
	c.mu.Lock()
	connection := c.connection
	c.mu.Unlock()

	if connection == nil {
		return
	}
	_ = connection.Lifecycle.Close()

	c.clear(entities.ConnectionStatus{
		State:  entities.Disconnected,
		Reason: fmt.Sprintf("the connection to %q was lost: %v", connection.Session.Reader.Name, cause),
	})
	c.log.Infof("connection to %q lost: %v", connection.Session.Reader.Name, cause)
}

// clear drops the session; afterwards every gated tool answers a CapabilityError, whether it ended politely or was lost.
func (c *Connection) clear(status entities.ConnectionStatus) {
	c.mu.Lock()
	c.connection = nil
	c.status = status
	c.mu.Unlock()
}
