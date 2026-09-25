// ROLE: controller for `hello`, the only command legal before the handshake completes.
// HOLDS: the AdapterFactory, the reader identity, the served capabilities and the bridge version.
// BUILT BY: Registry.
// POPULATES: the SessionContext's mode, persona and adapter set.

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

		// Recorded before anything else can fail, so any evidence the session produces is attributable.
		context.persona = params.persona
		context.mode = params.mode
		context.transcript.open()

		let adapters: AdapterSet
		do {
			adapters = try factory.build(mode: params.mode)
		} catch let refusal as AdapterFactoryError {
			throw CommandError(refusal.description)
		}
		// Installed before capture starts, so teardown can stop what was started if a later step throws.
		context.adapters = adapters

		// One buffer per session: indices that outlived a session would mislead the next agent.
		let speech = SpeechBuffer(clock: context.clock)
		// Wired before anything is captured, so a crashed run still leaves a record of what the reader said.
		speech.setObserver { [transcript = context.transcript] text in transcript.speech(text) }
		context.speech = speech
		adapters.speechSource.start(speech)

		// After capture is listening: pointing the reader at the capture voice starts utterances, and the
		// setup's last rung requires one to reach this buffer.
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
			synth: selectedSynth(adapters.providerLifecycle),
			logPath: context.transcript.logPath,
			bridgeVersion: bridgeVersion,
			// Sent only because this build announces the `guidance` capability; without it the field must be
			// omitted.
			guidance: try GetGuidanceHandler.guidance(for: params.persona),
			// Sent in both modes, since it describes the machine; never settable over the wire.
			silenceCap: SilenceCapInfo(
				enabled: context.silenceCapPolicy.enabled,
				warnAfterSeconds: context.silenceCapPolicy.warnAfter,
				liftAfterSeconds: context.silenceCapPolicy.liftAfter
			),
			attended: context.attended
		)
	}

	private func selectedSynth(_ lifecycle: any ProviderLifecycle) -> String {
		guard let selected = lifecycle.selectedVoice() else { return captureVoiceName }
		return selected.isCaptureVoice ? captureVoiceName : selected.identifier
	}
}

let captureVoiceName = "screen-readers-mcp capture voice"
