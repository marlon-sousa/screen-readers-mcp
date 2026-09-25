// screenreader-mcp domain -- the set_config tool.
// Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
// ROLE: controller, gated on config.
// USES: ports.ConfigAccessor, through ToolContext.Config().
// LISTED BY: registry.go.
// Returns what the reader now holds, which may differ from what was sent.
package tools

import (
	"encoding/json"
	"errors"

	"github.com/marlon-sousa/screen-readers-mcp/server/domain/entities"
)

type SetConfig struct{}

var _ Tool = (*SetConfig)(nil)

func (t *SetConfig) Name() string { return "set_config" }

func (t *SetConfig) Capability() entities.Capability { return entities.CapabilityConfig }

func (t *SetConfig) Description() string {
	return "Write one value into the screen reader's own configuration, addressed by a " +
		"key path into its config tree. Returns the value the reader now holds, which " +
		"may differ from what was sent if the reader normalised it. The path and the " +
		"value are the READER's vocabulary. This changes a live setting for a real " +
		"user's screen reader: read it with get_config first and put it back when you " +
		"are done."
}

func (t *SetConfig) InputSchema() json.RawMessage {
	return json.RawMessage(`{
	"type": "object",
	"properties": {
		"key_path": {
			"type": "array",
			"items": {"type": "string"},
			"minItems": 1,
			"description": "The path into the reader's configuration tree, outermost key first, as that reader spells it. Reader-specific and passed through untouched; this server never interprets it."
		},
		"value": {
			"description": "The value to write. Any JSON the reader accepts for this key -- a string, number, boolean, object or array."
		}
	},
	"required": ["key_path", "value"],
	"additionalProperties": false
}`)
}

func (t *SetConfig) OutputSchema() json.RawMessage {
	return json.RawMessage(`{
	"type": "object",
	"properties": {
		"value": {
			"description": "What the reader NOW HOLDS, which is not always what was sent -- a reader may normalise, clamp or partly reject a value. Read it rather than assuming the write landed as written."
		}
	},
	"required": ["value"]
}`)
}

func (t *SetConfig) Execute(ctx ToolContext, params json.RawMessage) (any, error) {
	config, err := ctx.Config()
	if err != nil {
		return nil, err
	}
	var request configParams
	if err := decodeParams(params, &request); err != nil {
		return nil, err
	}
	if len(request.KeyPath) == 0 {
		return nil, errors.New("key_path is required, and must name at least one key")
	}
	if len(request.Value) == 0 {
		// An absent value is a malformed call, whereas JSON null is a value a reader may store.
		return nil, errors.New("value is required; pass null explicitly to write a null")
	}

	written, err := config.SetConfig(request.KeyPath, request.Value)
	if err != nil {
		return nil, err
	}
	return configResult{Value: written}, nil
}
