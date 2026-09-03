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

	/// What `publish` promotes the machine to. `published` is the honest default
	/// for a machine whose system re-reads its voices when asked.
	///
	/// SETTING IT TO `.registered` IS HOW A TEST SAYS "THIS MACHINE WILL NOT
	/// PUBLISH" -- the dead end 13.20 could only name and 13.26 now tries to climb.
	/// It was `stateAfterRegistering` that expressed that until this entry, because
	/// registering and publishing were one step; they are two now, and a machine
	/// that registers fine and never publishes is exactly the state 13.26's first
	/// live connect hit.
	public var stateAfterPublishing: ProviderState = .published

	/// When set, `publish` throws it and the machine state is left alone -- the
	/// state 13.26's first live run actually hit: registered, and the system never
	/// offering the voice.
	public var publicationRefusal: ProviderError?

	/// The identifiers this fake MACHINE publishes, or nil for "publishes anything
	/// it is asked about" -- 13.24.
	///
	/// NIL BY DEFAULT, AND THAT IS DELIBERATE RATHER THAN LAZY. Every test written
	/// before this entry describes a machine whose voices are all present, which is
	/// the ordinary case; a default of "publishes nothing" would have silently
	/// turned each of them into the degraded path and changed what they assert
	/// without anybody editing them. A test that wants the removed-voice case says
	/// so by setting this, which is the same shape as every refusal field above.
	public var publishedVoices: Set<String>?

	public private(set) var selectCalls = 0
	public private(set) var registerCalls = 0
	public private(set) var publishCalls = 0
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

	/// COUNTED, AND IT PROMOTES. Publishing is a SEPARATE ACT from registering --
	/// a registered provider's voices do not appear until something asks the system
	/// to re-read them -- and 13.26's first live connect is why anybody knows that:
	/// the handshake registered, restarted the reader to publish the voice, and the
	/// voice had never been published at all. A fake that folded the two together
	/// could not tell the fixed order from the broken one.
	public func publish() throws {
		publishCalls += 1
		if let publicationRefusal { throw publicationRefusal }
		if machineState < stateAfterPublishing { machineState = stateAfterPublishing }
		guard machineState >= .published else {
			throw ProviderError(
				"the capture voice's extension is registered and the system still does not offer its "
					+ "voice. " + ReaderCondition.providerNotRunning.described)
		}
	}

	public func state() -> ProviderState {
		guard machineState >= .published else { return machineState }
		return selected == captureVoiceIdentifier ? .selected : .published
	}

	public func selectedVoice() -> SelectedVoice? {
		selected.map { SelectedVoice(identifier: $0, isCaptureVoice: $0 == captureVoiceIdentifier) }
	}

	/// MIRRORS THE REAL ADAPTER, which answers from the machine's published voice
	/// list -- the same list it matches our own voice against. See `publishedVoices`
	/// for why "unset" means yes.
	public func systemPublishesVoice(_ identifier: String) -> Bool {
		guard let publishedVoices else { return true }
		return publishedVoices.contains(identifier)
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
