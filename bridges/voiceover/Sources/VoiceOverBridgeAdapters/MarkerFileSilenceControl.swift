// ROLE: adapter implementing the SilenceControl port by writing the one file the capture voice reads.
// BUILT BY: VoiceOverAdapterFactory, one per session.
// The file's shape, `{"silent": <bool>, "voice": "<identifier>"}`, is a contract with MarkerFileCaptureModeSource in the extension; change both together.
// A live session writes the marker too, with `silent: false`, to pass on the user's voice, so presence is not silence.
// Silence is a lease on the file's modification time, renewed only from the session loop: a timer of its own would keep a wedged session muting a blind user.
// A command that blocks longer than the lease lets the marker expire mid-command, which is the safe direction.
// Replaced atomically, so the extension, reading once per utterance, never sees half a file.

import Foundation
import VoiceOverBridgeDomain

public final class MarkerFileSilenceControl: SilenceControl {
	private let path: String
	private var preferredVoice: String?
	private var suppressing = false
	private var open = false

	public init(path: String) {
		self.path = path
	}

	public var isSuppressing: Bool { suppressing }

	/// Must compute the path the extension uses (`<home>/voiceover-capture-silent` in its sandbox container), or the two never meet.
	public static func containerMarkerPath(home: String) -> String {
		URL(fileURLWithPath: home)
			.appendingPathComponent("Library/Containers")
			.appendingPathComponent(captureExtensionBundleID)
			.appendingPathComponent("Data")
			.appendingPathComponent(markerFileName)
			.path
	}

	public func begin(preferredVoice: String?) throws {
		self.preferredVoice = preferredVoice
		suppressing = false
		open = true
		try write()
	}

	public func suppress() throws {
		suppressing = true
		open = true
		try write()
	}

	public func passThrough() throws {
		suppressing = false
		open = true
		try write()
	}

	public func renew() {
		// A failed renewal is silent on purpose: the lease expires and the machine speaks.
		guard open else { return }
		try? write()
	}

	public func release() {
		open = false
		suppressing = false
		// The lease, not this removal, is the guarantee: a SIGKILL, a panic or a power cut skips this line.
		try? FileManager.default.removeItem(atPath: path)
	}

	private func write() throws {
		let object: [String: Any] = [
			"silent": suppressing,
			"voice": preferredVoice ?? "",
		]
		let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
		let url = URL(fileURLWithPath: path)
		try FileManager.default.createDirectory(
			at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
		try data.write(to: url, options: .atomic)
	}
}

/// Frozen with the bundle identity; see `captureExtensionBundleID`.
public let markerFileName = "voiceover-capture-silent"
