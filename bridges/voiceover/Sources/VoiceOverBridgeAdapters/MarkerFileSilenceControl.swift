// ROLE: adapter -- IMPLEMENTS the SilenceControl domain port by writing the one
// file the capture voice reads.
//
// BUILT BY: VoiceOverAdapterFactory, one per session. THE OTHER HALF IS
// MarkerFileCaptureModeSource, inside the extension, and the two are separate
// PROCESSES that meet only at this file -- so its shape is a wire contract in
// miniature: `{"silent": <bool>, "voice": "<identifier>"}`, and a change here is
// a change there.
//
// WHAT IT WRITES, AND WHY THE FILE EXISTS IN BOTH MODES. A live session keeps a
// marker too, saying `silent: false`, because the second field has to reach the
// extension either way: it names the voice the user chose for themselves, so
// pass-through re-speaks in it and capture becomes acoustically invisible (spec
// 0046, "Rule 0"). PRESENCE IS THEREFORE NOT SILENCE -- if it were, every live
// session would mute the machine.
//
// SILENCE IS A LEASE. Every write stamps the file's modification time, and the
// extension treats a marker older than its lease as pass-through. `renew()` is
// what keeps a silence alive, and it is called from the session loop rather than
// from a timer of this class's own -- deliberately, and it is the safer
// coupling: silence then depends on the liveness of THE VERY LOOP THAT CAN LIFT
// IT. A session thread that wedged inside a handler would go on renewing from
// its own timer and leave a blind user mute with every watchdog still ticking;
// with the loop as the pulse, that machine un-mutes itself in one lease.
//
// The cost of that choice, stated rather than hidden: a single command that
// blocks LONGER than the lease -- a `waitForSpeech` with a timeout past 30 s --
// lets the marker expire mid-command, and the human hears their machine again
// before the agent expected. That is the safe direction, it is visible in
// `ping`'s `suppressing`, and it is preferable to the alternative failure.
//
// AN ATOMIC REPLACE, NOT AN APPEND. `Data.write(to:)` replaces the file whole, so
// the extension -- which reads it on the request thread, once per utterance --
// can never observe half a line. That is also why this class does its own IO
// rather than sitting on the FileWriter seam: that seam is an append-only,
// long-lived-handle writer built for the transcript, and it can neither replace
// nor delete. See the tests, which drive a real file for the same reason
// FileLineTailer's do -- every decision here is about what a real filesystem
// does with mtimes.

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

	/// Where the marker lives for a given home directory.
	///
	/// DUPLICATED FROM THE EXTENSION ON PURPOSE, for the reason
	/// `ContainerFileSpeechSource.containerFilePath` is and `LocalSocketPath`
	/// mirrors the server's Go: two processes must compute one path from one rule
	/// or they never meet. Inside the sandbox the extension's own
	/// `NSHomeDirectory()` already IS its container, so it writes
	/// `<home>/voiceover-capture-silent`; this side is not sandboxed and spells
	/// the whole path out. `home` is passed in, so this stays a pure function.
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
		// A failed renewal is deliberately silent: it expires the lease, the
		// machine speaks, and that is the direction every unanswerable question in
		// this mechanism is answered in.
		guard open else { return }
		try? write()
	}

	public func release() {
		open = false
		suppressing = false
		// The ordinary case's immediate lift. NOTHING DEPENDS ON IT RUNNING -- the
		// lease is the guarantee, because a SIGKILL, a panic and a power cut all
		// skip this line and all leave the marker to expire on its own.
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

/// The marker's name inside the extension's container. Frozen with the bundle
/// identity, for the reason `captureExtensionBundleID` is.
public let markerFileName = "voiceover-capture-silent"
