// A hand-written stateful fake for the ProviderLifecycle port, mirroring
// Sources/VoiceOverBridgeDomain/Ports/ProviderLifecycle.swift.
//
// IT IS A LITTLE STATE MACHINE RATHER THAN A SCRIPT OF ANSWERS, because the
// thing under test is a sequence: read the user's voice, write ours, confirm it
// took, put theirs back. A double that returned canned values could not tell a
// bridge that restored the right voice from one that restored ours -- which is
// the failure that leaves a person on a voice they did not choose.

import VoiceOverBridgeDomain

public final class FakeProviderLifecycle: ProviderLifecycle {
	/// What the reader is currently set to. Written by the fake exactly as the
	/// preference is written on the machine.
	public var selected: String?
	/// The suffix that makes an identifier ours.
	public let captureVoiceIdentifier: String
	/// What `state()` answers before anything is selected.
	public var machineState: ProviderState
	/// When set, `selectCaptureVoice` throws it and leaves the selection alone.
	public var selectionRefusal: ProviderError?
	/// When set, `restoreVoice` throws it -- the case that must not stop teardown.
	public var restoreRefusal: ProviderError?
	/// When set, `register` throws it and the machine state is left alone.
	public var registrationRefusal: ProviderError?
	/// What `register` promotes the machine to when it succeeds. `published` is
	/// the honest default for a fake of a MACHINE that has just been registered
	/// and whose reader has restarted; a test that wants the rung this bridge
	/// cannot climb sets `.registered` and gets exactly that failure.
	public var stateAfterRegistering: ProviderState = .published

	public private(set) var selectCalls = 0
	public private(set) var registerCalls = 0
	public private(set) var restored: [String] = []

	public init(
		selected: String? = "com.apple.voice.compact.pt-BR.Luciana",
		captureVoiceIdentifier: String = "org.screen-readers-mcp.capture.voice",
		machineState: ProviderState = .published
	) {
		self.selected = selected
		self.captureVoiceIdentifier = captureVoiceIdentifier
		self.machineState = machineState
	}

	public func state() -> ProviderState {
		guard machineState >= .published else { return machineState }
		return selected == captureVoiceIdentifier ? .selected : .published
	}

	public func selectedVoice() -> SelectedVoice? {
		selected.map { SelectedVoice(identifier: $0, isCaptureVoice: $0 == captureVoiceIdentifier) }
	}

	/// COUNTED, and never undone. `register()` is MACHINE state: the port says in
	/// as many words that there is no `unregister()` and that nothing at teardown
	/// may be paired with this, so a fake that counted nothing could not tell a
	/// bridge that registers once from one that registers on every connect -- nor
	/// catch the `unregister()` somebody adds for symmetry, which would put the
	/// next session back in the state 13.20 exists to repair.
	public func register() throws {
		registerCalls += 1
		if let registrationRefusal { throw registrationRefusal }
		machineState = stateAfterRegistering
	}

	public func selectCaptureVoice() throws {
		selectCalls += 1
		if let selectionRefusal { throw selectionRefusal }
		// MIRRORS THE REAL ADAPTER, which cannot select a voice the system has not
		// published and says so by name. A fake that wrote the selection anyway
		// would let a test climb a rung the machine cannot.
		guard machineState >= .published else {
			throw ProviderError("cannot select the capture voice: " + state().report)
		}
		selected = captureVoiceIdentifier
	}

	public func restoreVoice(_ identifier: String) throws {
		restored.append(identifier)
		if let restoreRefusal { throw restoreRefusal }
		selected = identifier
	}
}
