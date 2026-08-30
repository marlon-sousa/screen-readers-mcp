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
			// that is the thing that would be rendering silence. Reported as a
			// constant until 13.6 can ASK the provider what is selected -- and it
			// is a constant rather than a hopeful read, so that "the voice is not
			// selected" arrives later as one of spec 0041's named conditions
			// rather than as a field that quietly disagrees with reality.
			synth: captureVoiceName,
			logPath: context.transcript.logPath,
			bridgeVersion: bridgeVersion,
			// The machine's own fact, sent as itself (spec 0035), so a server
			// never has to infer it from a silence cap it may not have been sent.
			attended: context.attended
		)
	}
}

/// What this bridge reports as the voice a session is hearing or silencing.
///
/// The capture voice's product name, not the extension's bundle identifier: the
/// field is read by a human in a transcript and by an agent that treats it as
/// opaque, and neither is served by a reverse-DNS string.
let captureVoiceName = "screen-readers-mcp capture voice"
