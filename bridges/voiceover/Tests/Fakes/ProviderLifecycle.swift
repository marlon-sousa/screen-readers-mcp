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

	public private(set) var selectCalls = 0
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

	public func selectCaptureVoice() throws {
		selectCalls += 1
		if let selectionRefusal { throw selectionRefusal }
		selected = captureVoiceIdentifier
	}

	public func restoreVoice(_ identifier: String) throws {
		restored.append(identifier)
		if let restoreRefusal { throw restoreRefusal }
		selected = identifier
	}
}
