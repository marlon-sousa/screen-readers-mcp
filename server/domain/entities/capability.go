// screenreader-mcp domain -- Capability and Set: the capability vocabulary.
// Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
//
// ROLE: entity. The pure vocabulary of "what can this reader do", built from
// what `hello` announced.
// BUILT BY: adapters/bridge/handshake.go, from the wire's capability strings.
// READ BY: adapters/bridge/handshake.go (which capability ports to hand out)
// and, in 10b, domain/entities/tool_catalog.go (the tool gate).
//
// This is domain vocabulary, not wire vocabulary: adapters/wire has its own
// generated capability constants and the handshake maps between them, which is
// what keeps the domain free of the binding (spec 0013, "the domain never
// speaks wire types").
package entities

import "sort"

// Capability names one command group a reader may support.
//
// A reader difference is a capability, never a protocol version: JAWS having no
// braille is this type's business, not the handshake's.
type Capability string

// The groups the wire contract defines (protocol.md §4). A bridge may announce
// strings beyond these, and a consumer must ignore what it does not know, so Set
// retains unknown members rather than dropping or rejecting them.
//
// `announce` joined the contract with spec 0008 and has been advertised by the
// NVDA bridge since entry 9c; it reached this vocabulary in 11a, which is when
// the server first had a tool to put behind it.
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

	// CapabilityGuidance is the bridge having its own written guidance for the
	// session's persona (spec 0029). It is the first capability that gates a
	// RESOURCE rather than a tool, which is why ToolCatalog knows nothing about
	// it: every earlier capability arrived by adding names to that list, and
	// this one adds none.
	CapabilityGuidance Capability = "guidance"

	// CapabilityDocument is the reader rendering documents into a flat text
	// buffer the user reads with the cursor keys -- NVDA's browse mode, and
	// whatever the analogue is elsewhere -- and being able to hand that
	// rendering over whole (spec 0026). Gates get_document_snapshot.
	CapabilityDocument Capability = "document"
)

// AllCapabilities is every capability the wire contract declares, in the order
// an agent meets them: the observation groups first, then the ones that act on
// the reader, then the ones that reach past it.
//
// Everything that enumerates the vocabulary goes through this -- today the
// completeness test that keeps Meaning honest, tomorrow whatever else needs the
// list -- so adding a capability is one edit to this file, exactly as adding a
// persona is one edit to persona.go.
//
// A Set may still hold strings that are NOT here: a bridge may announce anything
// and NewSet retains what it does not know. This is what THIS SERVER declares,
// not what a reader may say.
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

// Meaning is the contract's own one-line gloss: what this capability IS, as
// opposed to which tools happen to sit behind it.
//
// It lives on the entity rather than in the resource that renders it (spec 0031,
// 2.5) for Stance()'s reason: these strings are wire-contract vocabulary
// (protocol.md section 4) -- the same ones a bridge announces in `hello` and
// screenreader://info reports verbatim -- so what `speech` MEANS is a fact about
// the contract, not about how one document chooses to present it.
//
// Empty for a string this server does not declare, which is the honest answer:
// an unknown capability is a reader saying something we have no gloss for, and
// inventing one would be this server describing a group it knows nothing about.
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

// Set is an immutable set of announced capabilities.
//
// A zero Set is a valid empty set -- a reader that announced nothing supports
// nothing, which Has reports correctly without a nil check at every call site.
type Set struct {
	members map[Capability]struct{}
}

// NewSet builds the set a bridge announced. Duplicates collapse; unknown
// strings are kept, so All() reports the reader honestly even where this
// server has no tool for a member.
func NewSet(announced []string) Set {
	members := make(map[Capability]struct{}, len(announced))
	for _, name := range announced {
		members[Capability(name)] = struct{}{}
	}
	return Set{members: members}
}

// Has reports whether the reader announced c.
func (s Set) Has(c Capability) bool {
	_, ok := s.members[c]
	return ok
}

// All returns every announced capability, sorted, including ones this server
// has no tool for. Sorted because it reaches an agent and a diff, and both
// deserve a stable order.
func (s Set) All() []Capability {
	all := make([]Capability, 0, len(s.members))
	for c := range s.members {
		all = append(all, c)
	}
	sort.Slice(all, func(i, j int) bool { return all[i] < all[j] })
	return all
}

// Strings is All as plain strings, for the places that report the set outward.
func (s Set) Strings() []string {
	all := s.All()
	out := make([]string, len(all))
	for i, c := range all {
		out[i] = string(c)
	}
	return out
}
