// ROLE: entity -- the command vocabulary the contract defines.
//
// Pure. Read by the registry (entry 13.4) to route an incoming Request, and by
// nothing else: `Request.cmd` stays a raw String, so an unknown command reaches
// the registry as data and is answered with a clean error instead of failing to
// decode. That is the same decision the Python binding records for the same
// reason, and it is why this enum is NOT the type of that field.
//
// EVERY COMMAND IN THE CONTRACT IS HERE, INCLUDING THE ONES THIS BRIDGE WILL
// NEVER IMPLEMENT. The binding renders the contract; the capability set (spec
// 0046: speech, gestures, typing, focus, interact, guidance) is what says which
// of them VoiceOver can answer, and it is announced by `hello`, one entry at a
// time. Binding only the implemented subset would give the drift gate an
// exception list, and an exception list is the thing that goes stale.
//
// The raw values are the case names: every command in this contract is already
// spelled in camelCase, so an explicit raw value would be the same string twice.

public enum Command: String, Codable, CaseIterable, Sendable {
	case hello
	case ping
	case echo
	case pressGesture
	case typeText
	case getSpeech
	case getLastSpeech
	case getNextSpeechIndex
	case waitForSpeech
	case waitForSpeechToFinish
	case getBraille
	case getFocusInfo
	case getState
	case setState
	case getConfig
	case setConfig
	case announce
	case askUser
	case waitForUserReply
	case getLog
	case getLogPosition
	case waitForLog
	case setLogLevel
	case getGuidance
	case getDocumentSnapshot
	case bye
}
