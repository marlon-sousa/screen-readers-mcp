// screenreader-mcp testsupport -- builders for configured readers.
// Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
// ROLE: test scaffolding, not a port double.
// USED BY: any test that needs a reader or an endpoint spelled the way a user would spell it.
package testsupport

import (
	"testing"

	"github.com/marlon-sousa/screen-readers-mcp/server/domain/entities"
)

func Endpoint(t testing.TB, spec string) entities.Endpoint {
	t.Helper()
	endpoint, err := entities.ParseEndpoint(spec)
	if err != nil {
		t.Fatalf("endpoint %q: %v", spec, err)
	}
	return endpoint
}

func Reader(t testing.TB, name string, specs ...string) entities.ConfiguredReader {
	t.Helper()
	endpoints := make([]entities.Endpoint, 0, len(specs))
	for _, spec := range specs {
		endpoints = append(endpoints, Endpoint(t, spec))
	}
	return entities.ConfiguredReader{Name: name, Endpoints: endpoints}
}
