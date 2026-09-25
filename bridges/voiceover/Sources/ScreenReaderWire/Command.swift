// ROLE: entity, the command vocabulary the contract defines, including commands this bridge never implements.

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
