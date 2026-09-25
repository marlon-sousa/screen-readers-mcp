// ROLE: entity, `hello`'s params and result, and the three shapes only the result carries.
// Only `protocolVersion` is compared; `bridgeVersion` is informational.

public struct HelloParams: Codable, Equatable, Sendable {
	public var mode: CaptureMode
	public var protocolVersion: Int
	/// nil leaves the reader's own log verbosity alone.
	public var logLevel: LogLevel?
	/// nil means the mode's default, which differs by mode.
	public var normalize: Bool?
	public var persona: String = ""

	public init(
		mode: CaptureMode,
		protocolVersion: Int,
		logLevel: LogLevel? = nil,
		normalize: Bool? = nil,
		persona: String = ""
	) {
		self.mode = mode
		self.protocolVersion = protocolVersion
		self.logLevel = logLevel
		self.normalize = normalize
		self.persona = persona
	}

	public init(from decoder: any Decoder) throws {
		let box = try decoder.container(keyedBy: CodingKeys.self)
		mode = try box.decode(CaptureMode.self, forKey: .mode)
		protocolVersion = try box.decode(Int.self, forKey: .protocolVersion)
		logLevel = try box.decodeIfPresent(LogLevel.self, forKey: .logLevel)
		normalize = try box.decodeIfPresent(Bool.self, forKey: .normalize)
		persona = try box.decode(String.self, forKey: .persona, orDefault: persona)
	}
}

public struct HelloResult: Codable, Equatable, Sendable {
	public var protocolVersion: Int
	public var reader: ReaderInfo
	public var capabilities: [Capability]
	public var mode: CaptureMode
	public var synth: String
	public var logPath: String
	public var bridgeVersion: String = "unknown"
	public var guidance: GetGuidanceResult?
	public var silenceCap: SilenceCapInfo?
	/// A bridge must default to attended; nil means the peer did not say.
	public var attended: Bool?
	public var normalized: [NormalizedSetting] = []

	public init(
		protocolVersion: Int,
		reader: ReaderInfo,
		capabilities: [Capability],
		mode: CaptureMode,
		synth: String,
		logPath: String,
		bridgeVersion: String = "unknown",
		guidance: GetGuidanceResult? = nil,
		silenceCap: SilenceCapInfo? = nil,
		attended: Bool? = nil,
		normalized: [NormalizedSetting] = []
	) {
		self.protocolVersion = protocolVersion
		self.reader = reader
		self.capabilities = capabilities
		self.mode = mode
		self.synth = synth
		self.logPath = logPath
		self.bridgeVersion = bridgeVersion
		self.guidance = guidance
		self.silenceCap = silenceCap
		self.attended = attended
		self.normalized = normalized
	}

	public init(from decoder: any Decoder) throws {
		let box = try decoder.container(keyedBy: CodingKeys.self)
		protocolVersion = try box.decode(Int.self, forKey: .protocolVersion)
		reader = try box.decode(ReaderInfo.self, forKey: .reader)
		capabilities = try box.decode([Capability].self, forKey: .capabilities)
		mode = try box.decode(CaptureMode.self, forKey: .mode)
		synth = try box.decode(String.self, forKey: .synth)
		logPath = try box.decode(String.self, forKey: .logPath)
		bridgeVersion = try box.decode(String.self, forKey: .bridgeVersion, orDefault: bridgeVersion)
		guidance = try box.decodeIfPresent(GetGuidanceResult.self, forKey: .guidance)
		silenceCap = try box.decodeIfPresent(SilenceCapInfo.self, forKey: .silenceCap)
		attended = try box.decodeIfPresent(Bool.self, forKey: .attended)
		normalized = try box.decode([NormalizedSetting].self, forKey: .normalized, orDefault: normalized)
	}
}

public struct ReaderInfo: Codable, Equatable, Sendable {
	public var name: String
	public var version: String

	public init(name: String, version: String) {
		self.name = name
		self.version = version
	}
}

/// How long a silent session may go before the bridge warns, and before it gives the user speech back.
public struct SilenceCapInfo: Codable, Equatable, Sendable {
	public var enabled: Bool
	public var warnAfterSeconds: Double
	public var liftAfterSeconds: Double

	public init(enabled: Bool, warnAfterSeconds: Double, liftAfterSeconds: Double) {
		self.enabled = enabled
		self.warnAfterSeconds = warnAfterSeconds
		self.liftAfterSeconds = liftAfterSeconds
	}
}

public struct NormalizedSetting: Codable, Equatable, Sendable {
	public var keyPath: [String]
	public var previous: JSONValue
	public var current: JSONValue
	public var why: String

	public init(keyPath: [String], previous: JSONValue, current: JSONValue, why: String) {
		self.keyPath = keyPath
		self.previous = previous
		self.current = current
		self.why = why
	}
}
