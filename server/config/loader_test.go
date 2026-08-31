// screenreader-mcp config -- tests for loader.go.
// Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
//
// Black-box (package config_test), and no test here touches disk: the file
// reader is a seam, so the layering rules are exercised as the pure decisions
// they are. These cases are acceptance criterion 4b.
package config_test

import (
	"encoding/json"
	"errors"
	"testing"

	"github.com/google/go-cmp/cmp"
	"github.com/marlon-sousa/screen-readers-mcp/server/config"
	"github.com/marlon-sousa/screen-readers-mcp/server/domain/entities"
)

// files scripts a --config file without a filesystem.
func files(contents map[string]string) config.FileReader {
	return func(path string) ([]byte, error) {
		raw, ok := contents[path]
		if !ok {
			return nil, errors.New("no such file")
		}
		return []byte(raw), nil
	}
}

// specs is the endpoint spelling of a reader's endpoints, which is what these
// assertions are really about.
func specs(reader entities.ConfiguredReader) []string {
	out := make([]string, 0, len(reader.Endpoints))
	for _, endpoint := range reader.Endpoints {
		out = append(out, endpoint.String())
	}
	return out
}

// shippedReaders is what the embedded defaults carry, named once so that the
// layering tests below can say "the shipped set, plus mine" instead of counting.
//
// THEY USED TO COUNT, AND 13.11 IS WHERE THAT COST SOMETHING. Three tests
// asserted `len(readers) != 1` -- a statement about how many bridges this repo
// happened to have rather than about layering -- so shipping the VoiceOver reader
// turned them red for a reason none of them was testing. The property each one
// actually cares about is that a config file or a flag EXTENDS the shipped set
// and does not replace it, which is what they say now.
var shippedReaders = []string{"nvda", "voiceover"}

// A freshly started server with NO arguments knows where our bridges listen:
// the zero-configuration install works because the default is a constant in the
// binary, not an inference from anything running.
func TestEmbeddedDefaultsShipEveryBridgeEndpointInOrder(t *testing.T) {
	loader, err := config.Load(config.Options{})
	if err != nil {
		t.Fatalf("Load: %v", err)
	}

	readers := loader.Readers()
	names := make([]string, 0, len(readers))
	for _, reader := range readers {
		names = append(names, reader.Name)
	}
	if diff := cmp.Diff(shippedReaders, names); diff != "" {
		t.Fatalf("shipped readers (-want +got):\n%s", diff)
	}

	// The LOCAL endpoint first, then loopback TCP: spec 0011's dialog lets the
	// user switch between them, and this is the order connect_reader tries. The
	// local name follows protocol.md §1's `<reader>McpBridge` convention against
	// each bridge's own reader.name, which is what lets one shipped default reach
	// a local bridge on every host (spec 0044).
	want := map[string][]string{
		"nvda":      {"local:nvdaMcpBridge", "tcp:127.0.0.1:8765"},
		"voiceover": {"local:voiceoverMcpBridge", "tcp:127.0.0.1:8765"},
	}
	for _, reader := range readers {
		if diff := cmp.Diff(want[reader.Name], specs(reader)); diff != "" {
			t.Errorf("%s's shipped endpoints (-want +got):\n%s", reader.Name, diff)
		}
	}
}

// --print-default-config must emit exactly the embedded bytes, since its whole
// purpose is to give the user a file they can edit and pass back as --config.
func TestDefaultsJSONIsValidAndParsesBackToTheSameSet(t *testing.T) {
	raw := config.DefaultsJSON()

	if !json.Valid(raw) {
		t.Fatalf("the embedded defaults are not valid JSON:\n%s", raw)
	}
	loader, err := config.Load(config.Options{
		ConfigPath: "copy.json",
		ReadFile:   files(map[string]string{"copy.json": string(raw)}),
	})
	if err != nil {
		t.Fatalf("Load from a copy of the defaults: %v", err)
	}
	if diff := cmp.Diff([]string{"local:nvdaMcpBridge", "tcp:127.0.0.1:8765"}, specs(loader.Readers()[0])); diff != "" {
		t.Errorf("round-tripped defaults (-want +got):\n%s", diff)
	}
}

func TestAConfigFileAddsAReaderTheDefaultsDoNotKnow(t *testing.T) {
	loader, err := config.Load(config.Options{
		ConfigPath: "readers.json",
		ReadFile: files(map[string]string{"readers.json": `{
			"readers": [{"name": "talkback", "endpoints": ["tcp:127.0.0.1:9010"]}]
		}`}),
	})
	if err != nil {
		t.Fatalf("Load: %v", err)
	}

	readers := loader.Readers()
	if len(readers) != len(shippedReaders)+1 {
		t.Fatalf("readers = %v, want the shipped set extended, not replaced", readers)
	}
	if readers[0].Name != shippedReaders[0] || readers[len(readers)-1].Name != "talkback" {
		t.Errorf("reader order = %v; want the defaults first and talkback appended", readers)
	}
}

// Per-reader REPLACEMENT rather than a merge of endpoint lists. A merge would
// make it impossible to remove a shipped default -- a user who moved their
// bridge would still have the old endpoint tried first, with no way to say
// otherwise.
func TestAConfigFileReplacesAReaderItNames(t *testing.T) {
	loader, err := config.Load(config.Options{
		ConfigPath: "readers.json",
		ReadFile: files(map[string]string{"readers.json": `{
			"readers": [{"name": "nvda", "endpoints": ["local:myOwnBridge"]}]
		}`}),
	})
	if err != nil {
		t.Fatalf("Load: %v", err)
	}

	if diff := cmp.Diff([]string{"local:myOwnBridge"}, specs(loader.Readers()[0])); diff != "" {
		t.Errorf("endpoints (-want +got):\n%s", diff)
	}
}

func TestReaderFlagsWinOverBothLayers(t *testing.T) {
	loader, err := config.Load(config.Options{
		ConfigPath: "readers.json",
		ReadFile: files(map[string]string{"readers.json": `{
			"readers": [{"name": "nvda", "endpoints": ["local:fromTheFile"]}]
		}`}),
		ReaderFlags: []string{"nvda=tcp:127.0.0.1:9999"},
	})
	if err != nil {
		t.Fatalf("Load: %v", err)
	}

	if diff := cmp.Diff([]string{"tcp:127.0.0.1:9999"}, specs(loader.Readers()[0])); diff != "" {
		t.Errorf("endpoints (-want +got):\n%s", diff)
	}
}

// Repeating a name adds an endpoint to that reader, in flag order, so a one-off
// override can still name both a pipe and a socket.
func TestRepeatingAReaderFlagAddsEndpointsInOrder(t *testing.T) {
	loader, err := config.Load(config.Options{
		ReaderFlags: []string{"nvda=tcp:127.0.0.1:9999", "nvda=local:someOtherBridge"},
	})
	if err != nil {
		t.Fatalf("Load: %v", err)
	}

	want := []string{"tcp:127.0.0.1:9999", "local:someOtherBridge"}
	if diff := cmp.Diff(want, specs(loader.Readers()[0])); diff != "" {
		t.Errorf("endpoints (-want +got):\n%s", diff)
	}
}

func TestANewReaderFromAFlagIsAppended(t *testing.T) {
	loader, err := config.Load(config.Options{ReaderFlags: []string{"jaws=local:jawsMcpBridge"}})
	if err != nil {
		t.Fatalf("Load: %v", err)
	}

	readers := loader.Readers()
	if len(readers) != len(shippedReaders)+1 || readers[len(readers)-1].Name != "jaws" {
		t.Fatalf("readers = %v, want jaws appended after the shipped set", readers)
	}
}

// A bad configuration must fail while the process is starting, not when an agent
// finally asks to connect.
func TestBadInputFailsAtLoadTime(t *testing.T) {
	cases := []struct {
		name string
		opts config.Options
	}{
		{"malformed flag", config.Options{ReaderFlags: []string{"nvda"}}},
		{"unknown transport", config.Options{ReaderFlags: []string{"nvda=carrier-pigeon:home"}}},
		{"missing file", config.Options{ConfigPath: "nowhere.json", ReadFile: files(nil)}},
		{"invalid json", config.Options{
			ConfigPath: "readers.json",
			ReadFile:   files(map[string]string{"readers.json": "{"}),
		}},
		{"reader with no endpoints", config.Options{
			ConfigPath: "readers.json",
			ReadFile:   files(map[string]string{"readers.json": `{"readers":[{"name":"nvda","endpoints":[]}]}`}),
		}},
		{"reader with no name", config.Options{
			ConfigPath: "readers.json",
			ReadFile:   files(map[string]string{"readers.json": `{"readers":[{"endpoints":["local:x"]}]}`}),
		}},
	}

	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			if _, err := config.Load(c.opts); err == nil {
				t.Error("Load succeeded; want an error at startup")
			}
		})
	}
}

// The order endpoints are declared in is the order they are dialed in, so a
// caller must not be able to reorder the loader's own slice underneath it.
func TestReadersReturnsACopy(t *testing.T) {
	loader, err := config.Load(config.Options{})
	if err != nil {
		t.Fatalf("Load: %v", err)
	}

	loader.Readers()[0] = entities.ConfiguredReader{Name: "tampered"}

	if loader.Readers()[0].Name != "nvda" {
		t.Error("a caller was able to modify the loader's reader set")
	}
}

// A config file written before spec 0044 says `pipe:`, and must keep working:
// the alias parses and normalises, so what the loader hands on -- and what
// list_readers therefore shows -- is the canonical spelling.
func TestLoadAcceptsThePipeAliasInAConfigFile(t *testing.T) {
	loader, err := config.Load(config.Options{
		ConfigPath: "readers.json",
		ReadFile: files(map[string]string{"readers.json": `{
			"readers": [{"name": "nvda", "endpoints": ["pipe:nvdaMcpBridge"]}]
		}`}),
	})
	if err != nil {
		t.Fatalf("Load: %v", err)
	}
	if diff := cmp.Diff([]string{"local:nvdaMcpBridge"}, specs(loader.Readers()[0])); diff != "" {
		t.Errorf("endpoints (-want +got):\n%s", diff)
	}
}
