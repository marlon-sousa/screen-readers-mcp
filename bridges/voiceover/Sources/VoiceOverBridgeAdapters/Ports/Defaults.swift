// ROLE: adapter seam -- a small persistent key/value store for this application.
//
// NOT A DOMAIN PORT: the domain asks for its settings (`BridgeConfig`) and does
// not know they are `UserDefaults`, a plist, or anything else.
//
// IMPLEMENTED BY: UserDefaultsStore (a leaf) and FakeDefaults (Tests/Fakes).
// USED BY: UserDefaultsBridgeConfig, which is the one place that decides what
// the keys are called, what the defaults are, and what to do with a stored value
// that no longer makes sense.
//
// THE SEAM EXISTS SO THE DEFAULTS ARE TESTABLE WITHOUT WRITING ANY, and that is
// the same argument as lane 1's `ConfigFile` seam under `IniBridgeConfig`: a
// test that reached the real store would leave droppings in the developer's own
// preferences, and one that used a scratch suite would still be exercising
// Foundation rather than our rules.
//
// TYPED READS RETURN OPTIONALS, because "not set" is a real answer the adapter
// above turns into a default. A seam that returned 0 for a missing port number
// would make an unconfigured machine indistinguishable from one configured
// wrongly.

public protocol Defaults: AnyObject {
	func string(_ key: String) -> String?
	func integer(_ key: String) -> Int?
	func boolean(_ key: String) -> Bool?
	func set(_ key: String, _ value: String)
	func set(_ key: String, _ value: Int)
	func set(_ key: String, _ value: Bool)
}
