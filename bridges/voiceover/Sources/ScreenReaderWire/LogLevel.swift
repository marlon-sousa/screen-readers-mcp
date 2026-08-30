// ROLE: entity -- the reader log verbosity a session may request.
//
// Pure. Carried by HelloParams, GetLogParams, WaitForLogParams, SetLogLevelParams
// and LogLevelResult -- five shapes, which is why it is a file of its own rather
// than living with one of them.
//
// THE VOCABULARY IS NVDA'S, AND THAT IS A CONTRACT FACT RATHER THAN A LEAK: the
// wire enum was drawn from NVDA's logHandler levels, and a second reader binds
// the same strings whether or not its own logging uses them. VoiceOver emits no
// diagnostic log of its own at all (spec 0046 part 2, measured), so this bridge
// does not advertise the `log` capability -- and still renders the enum, because
// the binding renders the contract.

public enum LogLevel: String, Codable, CaseIterable, Sendable {
	case debug
	case io
	case debugwarning
	case info
	case warning
	case error
}
