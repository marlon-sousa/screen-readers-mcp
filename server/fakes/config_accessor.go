// screenreader-mcp fakes -- FakeConfigAccessor: the ConfigAccessor port double.
// Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
//
// ROLE: test double for domain/ports/config_accessor.go.
// USED BY: the get_config and set_config tool controller tests.
package fakes

import (
	"encoding/json"
	"fmt"
	"strings"
	"sync"

	"github.com/marlon-sousa/screen-readers-mcp/server/domain/ports"
)

type FakeConfigAccessor struct {
	mu     sync.Mutex
	values map[string]json.RawMessage
	err    error
}

var _ ports.ConfigAccessor = (*FakeConfigAccessor)(nil)

func NewFakeConfigAccessor() *FakeConfigAccessor {
	return &FakeConfigAccessor{values: map[string]json.RawMessage{}}
}

func (f *FakeConfigAccessor) Put(keyPath []string, value string) {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.values[key(keyPath)] = json.RawMessage(value)
}

func (f *FakeConfigAccessor) FailWith(err error) {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.err = err
}

func (f *FakeConfigAccessor) GetConfig(keyPath []string) (json.RawMessage, error) {
	f.mu.Lock()
	defer f.mu.Unlock()
	if f.err != nil {
		return nil, f.err
	}
	value, ok := f.values[key(keyPath)]
	if !ok {
		return nil, fmt.Errorf("no config at %s", key(keyPath))
	}
	return value, nil
}

func (f *FakeConfigAccessor) SetConfig(keyPath []string, value json.RawMessage) (json.RawMessage, error) {
	f.mu.Lock()
	defer f.mu.Unlock()
	if f.err != nil {
		return nil, f.err
	}
	f.values[key(keyPath)] = value
	return value, nil
}

func key(keyPath []string) string { return strings.Join(keyPath, ".") }
