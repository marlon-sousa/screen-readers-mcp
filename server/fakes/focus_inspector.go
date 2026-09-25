// screenreader-mcp fakes -- FakeFocusInspector: the FocusInspector port double.
// Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
//
// ROLE: test double for domain/ports/focus_inspector.go.
// USED BY: the get_focus_info tool controller tests.
package fakes

import (
	"sync"

	"github.com/marlon-sousa/screen-readers-mcp/server/domain/ports"
)

type FakeFocusInspector struct {
	mu    sync.Mutex
	focus ports.FocusInfo
	err   error
}

var _ ports.FocusInspector = (*FakeFocusInspector)(nil)

func NewFakeFocusInspector() *FakeFocusInspector { return &FakeFocusInspector{} }

func (f *FakeFocusInspector) SetFocus(focus ports.FocusInfo) {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.focus = focus
}

func (f *FakeFocusInspector) FailWith(err error) {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.err = err
}

func (f *FakeFocusInspector) FocusInfo() (ports.FocusInfo, error) {
	f.mu.Lock()
	defer f.mu.Unlock()
	if f.err != nil {
		return ports.FocusInfo{}, f.err
	}
	return f.focus, nil
}
