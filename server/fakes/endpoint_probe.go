// screenreader-mcp fakes -- FakeEndpointProbe: the EndpointProbe double.
// Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
//
// ROLE: test double for domain/ports/endpoint_probe.go.
// USED BY: the connection controller tests.
package fakes

import (
	"github.com/marlon-sousa/screen-readers-mcp/server/domain/entities"
	"github.com/marlon-sousa/screen-readers-mcp/server/domain/ports"
)

type FakeEndpointProbe struct {
	live map[entities.Endpoint]struct{}
}

var _ ports.EndpointProbe = (*FakeEndpointProbe)(nil)

func NewFakeEndpointProbe(live ...entities.Endpoint) *FakeEndpointProbe {
	set := make(map[entities.Endpoint]struct{}, len(live))
	for _, endpoint := range live {
		set[endpoint] = struct{}{}
	}
	return &FakeEndpointProbe{live: set}
}

func (f *FakeEndpointProbe) Live(candidates []entities.Endpoint) []entities.Endpoint {
	var live []entities.Endpoint
	for _, candidate := range candidates {
		if _, ok := f.live[candidate]; ok {
			live = append(live, candidate)
		}
	}
	return live
}
