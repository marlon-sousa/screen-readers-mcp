// screenreader-mcp config -- Loader: the layered endpoint set.
// Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
//
// ROLE: adapter implementing the EndpointSource port by layering the embedded defaults, an optional --config file, and --reader flags.
// BUILT BY: wiring/wiring.go, from the parsed flags.
// USED BY: the connection controller, for list_readers and connect_reader.
package config

import (
	_ "embed"
	"encoding/json"
	"fmt"
	"os"
	"strings"

	"github.com/marlon-sousa/screen-readers-mcp/server/domain/entities"
	"github.com/marlon-sousa/screen-readers-mcp/server/domain/ports"
)

// defaultsJSON is the shipped endpoint set; its readers share TCP port 8765 because they never run on one host.
// A reader added here is also policed by name in the agent-visible surface by adapters/mcp/surface_text_test.go.
//
//go:embed defaults.json
var defaultsJSON []byte

// DefaultsJSON returns a copy, so a caller cannot scribble on package state.
func DefaultsJSON() []byte {
	out := make([]byte, len(defaultsJSON))
	copy(out, defaultsJSON)
	return out
}

type FileReader func(path string) ([]byte, error)

type document struct {
	Readers []documentReader `json:"readers"`
}

type documentReader struct {
	Name      string   `json:"name"`
	Endpoints []string `json:"endpoints"`
}

type Options struct {
	// ConfigPath empty means no config file.
	ConfigPath string

	ReaderFlags []string

	ReadFile FileReader
}

// Loader is resolved once at construction, so a bad config file fails before the server serves anything.
type Loader struct {
	readers []entities.ConfiguredReader
}

var _ ports.EndpointSource = (*Loader)(nil)

// Load replaces per reader rather than merging endpoint lists, so a higher layer can remove a shipped default; order is preserved.
func Load(opts Options) (*Loader, error) {
	readFile := opts.ReadFile
	if readFile == nil {
		readFile = os.ReadFile
	}

	var defaults document
	if err := json.Unmarshal(defaultsJSON, &defaults); err != nil {
		return nil, fmt.Errorf("embedded defaults: %w", err)
	}
	readers, err := toReaders(defaults)
	if err != nil {
		return nil, fmt.Errorf("embedded defaults: %w", err)
	}

	if opts.ConfigPath != "" {
		raw, err := readFile(opts.ConfigPath)
		if err != nil {
			return nil, fmt.Errorf("reading %s: %w", opts.ConfigPath, err)
		}
		var fromFile document
		if err := json.Unmarshal(raw, &fromFile); err != nil {
			return nil, fmt.Errorf("%s: %w", opts.ConfigPath, err)
		}
		overrides, err := toReaders(fromFile)
		if err != nil {
			return nil, fmt.Errorf("%s: %w", opts.ConfigPath, err)
		}
		for _, reader := range overrides {
			readers = replaceReader(readers, reader)
		}
	}

	fromFlags, err := readersFromFlags(opts.ReaderFlags)
	if err != nil {
		return nil, err
	}
	for _, reader := range fromFlags {
		readers = replaceReader(readers, reader)
	}

	return &Loader{readers: readers}, nil
}

// Readers returns a copy, because the order is load-bearing.
func (l *Loader) Readers() []entities.ConfiguredReader {
	out := make([]entities.ConfiguredReader, len(l.readers))
	copy(out, l.readers)
	return out
}

func toReaders(doc document) ([]entities.ConfiguredReader, error) {
	readers := make([]entities.ConfiguredReader, 0, len(doc.Readers))
	for _, entry := range doc.Readers {
		if entry.Name == "" {
			return nil, fmt.Errorf("a reader has no name")
		}
		if len(entry.Endpoints) == 0 {
			return nil, fmt.Errorf("reader %q has no endpoints", entry.Name)
		}
		endpoints := make([]entities.Endpoint, 0, len(entry.Endpoints))
		for _, spec := range entry.Endpoints {
			endpoint, err := entities.ParseEndpoint(spec)
			if err != nil {
				return nil, fmt.Errorf("reader %q: %w", entry.Name, err)
			}
			endpoints = append(endpoints, endpoint)
		}
		readers = append(readers, entities.ConfiguredReader{Name: entry.Name, Endpoints: endpoints})
	}
	return readers, nil
}

// readersFromFlags adds each repeated name's endpoint to that reader in flag order; the flag layer then replaces the reader whole.
func readersFromFlags(flags []string) ([]entities.ConfiguredReader, error) {
	var order []string
	byName := map[string][]entities.Endpoint{}

	for _, flag := range flags {
		name, spec, found := strings.Cut(flag, "=")
		if !found || name == "" || spec == "" {
			return nil, fmt.Errorf("--reader %q: want name=spec, e.g. nvda=local:nvdaMcpBridge", flag)
		}
		endpoint, err := entities.ParseEndpoint(spec)
		if err != nil {
			return nil, fmt.Errorf("--reader %q: %w", flag, err)
		}
		if _, seen := byName[name]; !seen {
			order = append(order, name)
		}
		byName[name] = append(byName[name], endpoint)
	}

	readers := make([]entities.ConfiguredReader, 0, len(order))
	for _, name := range order {
		readers = append(readers, entities.ConfiguredReader{Name: name, Endpoints: byName[name]})
	}
	return readers, nil
}

// replaceReader keeps the replaced reader's position, so an override does not reorder `list_readers`.
func replaceReader(readers []entities.ConfiguredReader, override entities.ConfiguredReader) []entities.ConfiguredReader {
	for i, existing := range readers {
		if existing.Name == override.Name {
			readers[i] = override
			return readers
		}
	}
	return append(readers, override)
}
