// ROLE: adapter seam -- deliver the lines appended to a file, as they arrive.
//
// NOT A DOMAIN PORT: the domain has no idea captured speech comes from a file at
// all. This is the seam BETWEEN two adapters, which is the only kind of port
// that lives under `adapters/`.
//
// USED BY: ContainerFileSpeechSource, which holds every decision about what a
// line MEANS and is unit-tested against a fake tailer -- so the capture feed's
// logic is proven with no extension, no container and no VoiceOver.
// IMPLEMENTED BY: FileLineTailer (the real file, on its own thread) and
// FakeLineTailer (Tests/Fakes), which delivers lines a test hands it.
//
// DELIVERY IS A PUSH, not a poll the caller drives, because the session thread
// spends its life blocked reading the channel: nothing would ever ask. Whose
// thread `onLine` runs on is the implementation's business, and the SpeechBuffer
// is what makes that safe.
public protocol LineTailer: AnyObject {
	/// Begin delivering COMPLETE lines appended after the file's current end.
	///
	/// After the current end, deliberately: the extension appends to one file
	/// across every launch of the reader, so a tailer that started at byte zero
	/// would replay days of old speech into a new session's buffer as though the
	/// reader had just said it.
	///
	/// A partial line is held until its newline arrives. A file that does not
	/// exist yet is not an error -- see `SpeechSource.start` for why that is the
	/// normal case rather than the broken one.
	func start(_ onLine: @escaping (String) -> Void)

	/// Stop delivering. Idempotent, and never throws: teardown calls it.
	func stop()
}
