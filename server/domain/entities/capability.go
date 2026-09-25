// screenreader-mcp domain -- Capability and Set: the capability vocabulary.
// Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
// ROLE: entity; the pure vocabulary of what a reader can do, built from what hello announced.
// BUILT BY: adapters/bridge/handshake.go, from the wire's capability strings.
// READ BY: adapters/bridge/handshake.go and domain/entities/tool_catalog.go.
package entities

import "sort"

type Capability string

// A bridge may announce strings beyond these, and Set retains the unknown members.
const (
	CapabilitySpeech   Capability = "speech"
	CapabilityBraille  Capability = "braille"
	CapabilityGestures Capability = "gestures"
	CapabilityFocus    Capability = "focus"
	CapabilityState    Capability = "state"
	CapabilityConfig   Capability = "config"
	CapabilityInteract Capability = "interact"
	CapabilityTyping   Capability = "typing"
	CapabilityLog      Capability = "log"

	// CapabilityGuidance gates a resource rather than a tool, so ToolCatalog does not list it.
	CapabilityGuidance Capability = "guidance"

	CapabilityDocument Capability = "document"
)

func AllCapabilities() []Capability {
	return []Capability{
		CapabilitySpeech,
		CapabilityBraille,
		CapabilityFocus,
		CapabilityState,
		CapabilityGestures,
		CapabilityTyping,
		CapabilityInteract,
		CapabilityConfig,
		CapabilityLog,
		CapabilityGuidance,
		CapabilityDocument,
	}
}

// Meaning is empty for a string this server does not declare.
func (c Capability) Meaning() string {
	switch c {
	case CapabilitySpeech:
		return "What the reader SAYS -- its utterances, captured as they are produced, " +
			"readable by index and waitable on."
	case CapabilityBraille:
		return "What the reader sends to a BRAILLE DISPLAY, which is abbreviated " +
			"differently from what it speaks and carries its own indices."
	case CapabilityFocus:
		return "What the reader currently has FOCUS on, described in the reader's own " +
			"vocabulary -- introspection, for asserting rather than for orienting."
	case CapabilityState:
		return "The reader's own MODE STATE -- browse or focus mode, speech mode, sleep, " +
			"input help -- which is how you observe the actions it signals with a beep " +
			"rather than with words."
	case CapabilityGestures:
		return "Pressing the reader's own COMMANDS, in the notation its user guide " +
			"prints, wherever the system focus happens to be."
	case CapabilityTyping:
		return "Inserting literal TEXT at the focused control, independently of the " +
			"keyboard layout -- content, not commands."
	case CapabilityInteract:
		return "Reaching the HUMAN sitting at the reader: speaking to them aloud, and " +
			"asking them something you need an answer to."
	case CapabilityConfig:
		return "Reading and writing the reader's own CONFIGURATION, addressed by a key " +
			"path into its settings tree."
	case CapabilityLog:
		return "The reader's own DIAGNOSTIC LOG -- marking it, reading a filtered slice " +
			"of it, and blocking until a record you named appears."
	case CapabilityGuidance:
		return "The reader's own written GUIDANCE for the persona this session declared. " +
			"It gates a resource rather than a tool: screenreader://reader-guidance."
	case CapabilityDocument:
		return "The whole DOCUMENT the reader is showing, as the flat lines a user arrows " +
			"through -- roles and all, in one call instead of one round trip per line."
	}
	return ""
}

// A zero Set is a valid empty set.
type Set struct {
	members map[Capability]struct{}
}

func NewSet(announced []string) Set {
	members := make(map[Capability]struct{}, len(announced))
	for _, name := range announced {
		members[Capability(name)] = struct{}{}
	}
	return Set{members: members}
}

func (s Set) Has(c Capability) bool {
	_, ok := s.members[c]
	return ok
}

func (s Set) All() []Capability {
	all := make([]Capability, 0, len(s.members))
	for c := range s.members {
		all = append(all, c)
	}
	sort.Slice(all, func(i, j int) bool { return all[i] < all[j] })
	return all
}

func (s Set) Strings() []string {
	all := s.All()
	out := make([]string, len(all))
	for i, c := range all {
		out[i] = string(c)
	}
	return out
}
