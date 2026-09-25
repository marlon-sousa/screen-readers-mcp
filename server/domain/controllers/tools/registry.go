// screenreader-mcp domain -- Registry: the explicit tool list.
// Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
// ROLE: the hand-written tool list, read top to bottom.
// BUILT BY: wiring/wiring.go.
// USED BY: dispatcher.go, adapters/mcp/sdk_server.go and Catalog().
package tools

import "github.com/marlon-sousa/screen-readers-mcp/server/domain/entities"

type Registry struct {
	tools  []Tool
	byName map[string]Tool
}

func BuildRegistry() *Registry {
	return NewRegistry(
		&ListReaders{},
		&ConnectReader{},
		&DisconnectReader{},
		&Status{},

		&GetSpeech{},
		&GetLastSpeech{},
		&GetNextSpeechIndex{},
		&WaitForSpeech{},
		&WaitForSpeechToFinish{},

		&GetBraille{},

		&PressGesture{},

		&TypeText{},

		&Announce{},
		&AskUser{},
		&WaitForUserReply{},

		&GetFocusInfo{},

		&GetState{},
		&SetState{},

		&GetConfig{},
		&SetConfig{},

		&GetDocumentSnapshot{},

		&GetLog{},
		&GetLogPosition{},
		&WaitForLog{},
		&SetLogLevel{},

		// Gated per step, so it declares no capability of its own.
		&RunSequence{},
	)
}

func NewRegistry(list ...Tool) *Registry {
	byName := make(map[string]Tool, len(list))
	for _, tool := range list {
		byName[tool.Name()] = tool
	}
	return &Registry{tools: list, byName: byName}
}

func (r *Registry) All() []Tool { return append([]Tool(nil), r.tools...) }

func (r *Registry) Lookup(name string) (Tool, bool) {
	tool, known := r.byName[name]
	return tool, known
}

func (r *Registry) Catalog() entities.ToolCatalog {
	gates := make([]entities.ToolGate, 0, len(r.tools))
	for _, tool := range r.tools {
		gates = append(gates, entities.ToolGate{Name: tool.Name(), Capability: tool.Capability()})
	}
	return entities.NewToolCatalog(gates)
}
