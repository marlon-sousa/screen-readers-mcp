// ROLE: adapter that implements the TextTyper port over the EventPoster seam.
// BUILT BY: VoiceOverAdapterFactory.
// USED BY: the TypeText handler, through the port.
// The target application may rewrite what was typed (TextEdit on macOS 15 autocapitalized it), so never
// compare typed input with observed output; ask the application or the reader what arrived.
// Unicode injection makes the keyboard layout irrelevant; a newline is not Return, and nothing is submitted.

import VoiceOverBridgeDomain

public final class AccessibilityTextTyper: TextTyper {
	/// Apple documents no maximum, and longer payloads are reported to be dropped or truncated without failing.
	static let chunkLimit = 20

	private let poster: any EventPoster

	public init(poster: any EventPoster) {
		self.poster = poster
	}

	public func type(_ text: String) throws {
		guard !text.isEmpty else { return }
		for chunk in Self.chunks(of: text) {
			do {
				// Both halves carry the payload: applications insert on either, and an unpaired key-down leaves a key held.
				try poster.post(unicode: chunk, keyDown: true)
				try poster.post(unicode: chunk, keyDown: false)
			} catch let failure as EventPostingFailure {
				throw TypingError(failure.description)
			}
		}
	}

	/// Cut by grapheme cluster, never inside one; a cluster longer than the limit is sent whole.
	static func chunks(of text: String) -> [String] {
		var chunks: [String] = []
		var current = ""
		var currentUnits = 0
		for cluster in text {
			let units = String(cluster).utf16.count
			if currentUnits > 0, currentUnits + units > chunkLimit {
				chunks.append(current)
				current = ""
				currentUnits = 0
			}
			current.append(cluster)
			currentUnits += units
		}
		if !current.isEmpty { chunks.append(current) }
		return chunks
	}
}
