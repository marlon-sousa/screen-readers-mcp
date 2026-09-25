// ROLE: adapter that implements CaptureModeSource by reading a marker file the bridge writes and refreshes.
// Read once per utterance, so a lift takes effect on the next thing VoiceOver says.
// Silence is opt-in and a lease: a marker that is missing, older than the lease, unreadable or unparseable
// means speak, so a dead bridge un-mutes the machine without any code of ours running.
// The file is `{"silent": <bool>, "voice": "<identifier>"}`; a live session keeps a fresh one with
// `silent: false` too, because the user's own voice has to reach here in both modes.

import Foundation

public final class MarkerFileCaptureModeSource: CaptureModeSource {
	public static let lease: TimeInterval = 30

	private let path: String
	private let lease: TimeInterval
	private let now: () -> Date

	public init(
		path: String,
		lease: TimeInterval = MarkerFileCaptureModeSource.lease,
		now: @escaping () -> Date = Date.init
	) {
		self.path = path
		self.lease = lease
		self.now = now
	}

	public var directive: CaptureDirective {
		let url = URL(fileURLWithPath: path)
		guard
			let attributes = try? FileManager.default.attributesOfItem(atPath: path),
			let modified = attributes[.modificationDate] as? Date,
			now().timeIntervalSince(modified) <= lease,
			let data = try? Data(contentsOf: url)
		else { return .passThrough }
		return MarkerFileCaptureModeSource.parse(data)
	}

	static func parse(_ data: Data) -> CaptureDirective {
		guard
			let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
		else { return .passThrough }
		let voice = object["voice"] as? String
		return CaptureDirective(
			silent: object["silent"] as? Bool ?? false,
			preferredVoice: (voice?.isEmpty ?? true) ? nil : voice
		)
	}
}
