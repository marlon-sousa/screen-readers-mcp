// ROLE: adapter seam listing the voices this machine publishes, by identifier.
// IMPLEMENTED BY: SystemPublishedVoices and FakePublishedVoices.
// USED BY: PluginKitProviderLifecycle, which decides what the list means.
// Publication here does not mean VoiceOver offers the voice: on macOS 15 it was missing from VoiceOver's picker while this list contained it.

public protocol PublishedVoices: AnyObject {
	func identifiers() -> [String]

	/// Asks the system to re-read its providers' voices; a newly registered provider's voices do not appear until something asks.
	/// Register, refresh, wait for the voice to appear, and only then restart the reader, or the restarted reader has no such voice.
	/// Asynchronous: it returns at once, so the caller polls.
	func refresh()
}
