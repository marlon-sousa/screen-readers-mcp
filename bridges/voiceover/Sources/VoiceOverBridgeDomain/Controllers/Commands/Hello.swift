// ROLE: controller -- the bootstrap command, and the only one legal before the
// handshake completes.
//
// HOLDS: the AdapterFactory, this bridge's reader identity, the capability set
// this build actually serves, and its own version string. BUILT BY: Registry.
// POPULATES: the SessionContext -- mode, persona and the adapter set -- which is
// why it is the one handler that writes to the context instead of only reading
// it.
//
// IT REFUSES BEFORE IT BUILDS. A protocol-version mismatch throws before the
// factory is called, so a rejected handshake leaves nothing started; the Session
// then ends the session, which is what "a failure before hello ends the
// handshake" means in practice.
//
// AND SINCE 13.6 IT REFUSES A PROMISE IT CANNOT KEEP. `silent` says a human will
// not hear their machine while an agent reads back what it said; on this route
// that is delivered by the capture voice rendering silence, which requires
// VoiceOver to actually be SPEAKING with the capture voice. So the handshake
// asks the provider lifecycle, and a silent session on a machine where the voice
// is not registered, not published, or would not stick is refused BY NAMED
// CONDITION with its recovery -- never established and quietly turned into
// something else. A LIVE session in the same state is NOT refused, and the
// difference is not squeamishness: selecting the voice applies live, in both
// directions (spec 0047, finding 17), so a live session that starts unhealthy
// can become healthy while it runs -- whereas silence promised at the handshake
// has to hold from the handshake.
//
// THE ORDER OF THE VOICE WORK IS LOAD-BEARING. The user's own voice is read and
// recorded on the context BEFORE ours is written, so every teardown path holds
// what to put back even if a later step of this handshake throws -- and it is
// recorded only when it is NOT ours, because a previous session that died
// without restoring leaves our own voice looking like the user's, and restoring
// that would be a bridge quietly keeping the machine on its capture voice.
//
// WHAT IS COMPARED IS THE PROTOCOL VERSION, NEVER THE COMPONENTS' OWN. The
// server, the NVDA bridge and this one release on their own cadences (spec
// 0012); `bridgeVersion` travels for the human reading a transcript and is never
// gated on.

import ScreenReaderWire

public final class HelloHandler: CommandHandler {
	public let availableBeforeHello = true

	private let factory: any AdapterFactory
	private let reader: ReaderInfo
	private let capabilities: [Capability]
	private let bridgeVersion: String

	public init(
		factory: any AdapterFactory,
		reader: ReaderInfo,
		capabilities: [Capability],
		bridgeVersion: String
	) {
		self.factory = factory
		self.reader = reader
		self.capabilities = capabilities
		self.bridgeVersion = bridgeVersion
	}

	public func execute(_ context: SessionContext, _ request: Request) throws -> any Encodable {
		let params = try request.params(as: HelloParams.self)
		guard ProtocolVersion.supports(params.protocolVersion) else {
			throw CommandError(
				"protocol version mismatch: bridge speaks \(ProtocolVersion.current), "
					+ "client sent \(params.protocolVersion)"
			)
		}

		// Recorded before anything else can fail: the persona is what the rest of
		// the session MEANS, and a session that established without it would
		// produce evidence nobody could attribute.
		context.persona = params.persona
		context.mode = params.mode
		context.transcript.open()

		// The factory may refuse the mode -- see VoiceOverAdapterFactory for the
		// one it refuses today and why. Translated into a CommandError here
		// because the port may not depend on this layer, and because the agent
		// should read one vocabulary of failure rather than two.
		let adapters: AdapterSet
		do {
			adapters = try factory.build(mode: params.mode)
		} catch let refusal as AdapterFactoryError {
			throw CommandError(refusal.description)
		}
		// INSTALLED BEFORE CAPTURE STARTS, so teardown can stop what was started
		// even if a later step of this handshake throws. The order is the whole
		// reason the field is set here rather than at the end.
		context.adapters = adapters

		// The buffer belongs to the session, so it is created here rather than
		// wired once in the composition root: indices that outlived a session
		// would mean something different to the next agent that read them.
		let speech = SpeechBuffer(clock: context.clock)
		// Bridge-side recording, wired before anything can be captured. A run that
		// crashed before the agent fetched anything still leaves a record of what
		// the reader said, which is the only account a silent run leaves at all.
		speech.setObserver { [transcript = context.transcript] text in transcript.speech(text) }
		context.speech = speech
		adapters.speechSource.start(speech)

		// AFTER CAPTURE IS LISTENING, and that order is the 13.5 lesson applied to
		// the other end of the same feed: pointing the reader at the capture voice
		// is what makes utterances start arriving, so the tailer has to be attached
		// before it happens or the first thing the reader says is the one nobody
		// can wait for.
		try establishReaderEdge(context, mode: params.mode, adapters: adapters)

		context.transcript.sessionOpened(
			mode: params.mode.rawValue,
			voice: captureVoiceName,
			persona: params.persona
		)

		return HelloResult(
			protocolVersion: ProtocolVersion.current,
			reader: reader,
			capabilities: capabilities,
			mode: params.mode,
			// `synth` NAMES THE VOICE THE SESSION IS HEARING OR SILENCING. On NVDA
			// it is the synthesizer driver; here it is the capture voice, because
			// that is the thing that would be rendering silence. ASKED rather than
			// asserted since 13.6: when the reader is on our voice this is its
			// product name, which is what a human reading a transcript wants, and
			// when it is NOT this is the identifier the reader is actually using
			// -- so the field can never quietly disagree with reality.
			synth: selectedSynth(adapters.providerLifecycle),
			logPath: context.transcript.logPath,
			bridgeVersion: bridgeVersion,
			// The machine's own policy on how long a human may be left unable to
			// hear it (protocol.md §6.1). Sent in BOTH modes: it describes the
			// machine rather than this session, and it is derived from the same
			// `attended` flag reported below, per §3's one-source rule. Never
			// settable over the wire -- an agent that could raise its own ceiling
			// does not have one.
			silenceCap: SilenceCapInfo(
				enabled: context.silenceCapPolicy.enabled,
				warnAfterSeconds: context.silenceCapPolicy.warnAfter,
				liftAfterSeconds: context.silenceCapPolicy.liftAfter
			),
			// The machine's own fact, sent as itself (spec 0035), so a server
			// never has to infer it from a silence cap it may not have been sent.
			attended: context.attended
		)
	}

	// -- the reader edge -------------------------------------------------------

	/// Read the user's voice, point the reader at ours, and open the marker
	/// channel -- refusing a silent session this machine cannot deliver.
	///
	/// Every failure here is REPORTED BY NAME, with its recovery, because the
	/// alternative on this route is an agent reading back nothing and concluding
	/// the reader is silent (spec 0041's sharpest requirement; ReaderCondition
	/// carries the argument).
	private func establishReaderEdge(
		_ context: SessionContext, mode: CaptureMode, adapters: AdapterSet
	) throws {
		let lifecycle = adapters.providerLifecycle

		// BEFORE ANYTHING IS WRITTEN. See the header for why "ours" is recorded as
		// nothing to restore rather than as the user's own voice.
		let previous = lifecycle.selectedVoice()
		if let previous, !previous.isCaptureVoice {
			context.previousVoice = previous.identifier
		}

		var failure: String?
		let initial = lifecycle.state()
		if initial < .published {
			// Nothing to select: the voice is not on this machine to be chosen.
			failure = initial.report
		} else if previous?.isCaptureVoice != true {
			do {
				try lifecycle.selectCaptureVoice()
			} catch {
				failure = (error as? ProviderError)?.description ?? String(describing: error)
			}
		}

		if let failure {
			context.transcript.note("reader edge: \(failure)")
			guard mode != .silent else {
				throw CommandError(
					"this bridge cannot run a silent session on this machine right now: \(failure)")
			}
		}

		// The channel the capture voice reads, open in BOTH modes: it carries the
		// user's own voice so pass-through is acoustically invisible (Rule 0), and
		// it is a LEASE the session renews -- a bridge that dies un-mutes the
		// machine by doing nothing at all.
		try adapters.silenceControl.begin(preferredVoice: context.previousVoice)
		if mode == .silent {
			try adapters.silenceControl.suppress()
			context.transcript.note("silence: suppressing, on a lease the session renews")
		}
	}

	/// The voice this session is hearing or silencing, named for a human when it
	/// is ours and by identifier when it is not.
	private func selectedSynth(_ lifecycle: any ProviderLifecycle) -> String {
		guard let selected = lifecycle.selectedVoice() else { return captureVoiceName }
		return selected.isCaptureVoice ? captureVoiceName : selected.identifier
	}
}

/// What this bridge reports as the voice a session is hearing or silencing.
///
/// The capture voice's product name, not the extension's bundle identifier: the
/// field is read by a human in a transcript and by an agent that treats it as
/// opaque, and neither is served by a reverse-DNS string.
let captureVoiceName = "screen-readers-mcp capture voice"
