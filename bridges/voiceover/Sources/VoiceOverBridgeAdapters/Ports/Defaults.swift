// ROLE: adapter seam -- a small persistent key/value store for this application.
// IMPLEMENTED BY: UserDefaultsStore and FakeDefaults.
// USED BY: UserDefaultsBridgeConfig, which decides the keys, the defaults and what to do with a stored value that no longer makes sense.
// Typed reads return nil for "not set", which the adapter above turns into a default.

public protocol Defaults: AnyObject {
	func string(_ key: String) -> String?
	func integer(_ key: String) -> Int?
	func boolean(_ key: String) -> Bool?
	func set(_ key: String, _ value: String)
	func set(_ key: String, _ value: Int)
	func set(_ key: String, _ value: Bool)
}
