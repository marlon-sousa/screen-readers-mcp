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
// AND SINCE 13.20 IT MAKES ITS OWN SETUP RATHER THAN REPORTING ON ONE. The
// reader edge is established by `ReaderEdgeSetup`, a controller of its own that
// CLIMBS the ProviderState ladder -- permissions, a running reader, the
// extension's registration, the voice, and a proof that what the reader says
// actually arrives -- and fails BY NAMED RUNG at the one it cannot climb. This
// handler builds it (its collaborators do not exist until the factory above has
// run) and runs it, and that is all this file knows about the machine.
//
// WHAT 13.6 PUT HERE AND 13.20 MOVED. Until this entry the voice work was a
// private method on this handler, and it REPORTED where the ladder had stopped:
// a `silent` session was refused by named condition and a `live` one carried on
// with a note in the transcript. The refusal was right and the asymmetry was
// right for what it was about -- `silent` is a promise about a human's ears and
// has to hold from the handshake, while writing the voice applies live in both
// directions (spec 0047, finding 17), so a live session could heal itself.
//
// IT IS NOW FATAL IN BOTH MODES, and that does not contradict the above because
// it is a different promise: what the new rungs establish is that `getSpeech`
// means anything at all, and a LIVE session announces the `speech` capability
// exactly as loudly. "It may become healthy while it runs" is a reasonable thing
// to say about a state nobody is repairing and an unreasonable one about a state
// the handshake has just tried to repair and failed. Spec 0050 §2.7.
//
// THE ORDER OF THE VOICE WORK IS LOAD-BEARING AND MOVED INTACT. The user's own
// voice is read and recorded on the context BEFORE ours is written, so every
// teardown path holds what to put back even if a later step throws -- and it is
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
		// can wait for. Since 13.20 the setup's last rung DEPENDS on that order --
		// it presses a command and requires the utterance to reach this buffer.
		try ReaderEdgeSetup(adapters: adapters, context: context, speech: speech).establish()

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
			// THIS READER'S GUIDANCE, SENT IN THE HANDSHAKE (protocol.md §3, spec
			// 0022 A.5). The persona arrived in these very params and this reply was
			// already being written, so the document costs NO ADDITIONAL ROUND TRIP
			// and connect stays one.
			//
			// COMPOSED BY THE SAME CODE `getGuidance` USES, because the contract
			// requires both routes to describe one document and a server that
			// receives this field must not call the command as well. Two
			// compositions would be a handshake and a command that agree today.
			//
			// IT IS SENT ONLY BECAUSE THIS BUILD ANNOUNCES `guidance` -- the
			// capabilities list above and this field are the same claim made twice,
			// and §3 says a bridge that does not announce the capability MUST omit
			// it. They cannot disagree here because both come from the Registry.
			guidance: try GetGuidanceHandler.guidance(for: params.persona),
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
