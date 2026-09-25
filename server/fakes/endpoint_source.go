// screenreader-mcp fakes -- FakeEndpointSource: the EndpointSource double.
// Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
//
// ROLE: test double for domain/ports/endpoint_source.go.
// USED BY: the connection controller tests.
package fakes

import (
	"github.com/marlon-sousa/screen-readers-mcp/server/domain/entities"
	"github.com/marlon-sousa/screen-readers-mcp/server/domain/ports"
)

type FakeEndpointSource struct {
	readers []entities.ConfiguredReader
}

var _ ports.EndpointSource = (*FakeEndpointSource)(nil)

func NewFakeEndpointSource(readers ...entities.ConfiguredReader) *FakeEndpointSource {
	return &FakeEndpointSource{readers: readers}
}

func (f *FakeEndpointSource) Readers() []entities.ConfiguredReader {
	return append([]entities.ConfiguredReader(nil), f.readers...)
}
