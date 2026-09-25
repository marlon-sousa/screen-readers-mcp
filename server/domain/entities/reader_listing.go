// screenreader-mcp domain -- ReaderListing: what `list_readers` answers.
// Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
//
// ROLE: entity, the configured readers joined with what the probe learned about their endpoints.
// BUILT BY: BuildListing, called by the connection controller.
// READ BY: the `list_readers` tool.
package entities

type Liveness string

const (
	Listening Liveness = "listening"

	NotListening Liveness = "not listening"

	// LivenessUnknown is every TCP endpoint and every local one addressed by
	// path; never find out by dialing, because the bridge's single session slot
	// would be taken.
	LivenessUnknown Liveness = "unknown"
)

type EndpointStatus struct {
	Endpoint Endpoint
	Liveness Liveness
}

type ReaderStatus struct {
	Name      string
	Endpoints []EndpointStatus
}

type ReaderListing struct {
	Readers []ReaderStatus
}

func BuildListing(readers []ConfiguredReader, live []Endpoint) ReaderListing {
	liveSet := make(map[Endpoint]struct{}, len(live))
	for _, e := range live {
		liveSet[e] = struct{}{}
	}

	listing := ReaderListing{Readers: make([]ReaderStatus, 0, len(readers))}
	for _, reader := range readers {
		status := ReaderStatus{Name: reader.Name, Endpoints: make([]EndpointStatus, 0, len(reader.Endpoints))}
		for _, endpoint := range reader.Endpoints {
			status.Endpoints = append(status.Endpoints, EndpointStatus{
				Endpoint: endpoint,
				Liveness: liveness(endpoint, liveSet),
			})
		}
		listing.Readers = append(listing.Readers, status)
	}
	return listing
}

func liveness(endpoint Endpoint, live map[Endpoint]struct{}) Liveness {
	if endpoint.Kind != TransportLocal || !IsBareName(endpoint.Address) {
		return LivenessUnknown
	}
	if _, ok := live[endpoint]; ok {
		return Listening
	}
	return NotListening
}
