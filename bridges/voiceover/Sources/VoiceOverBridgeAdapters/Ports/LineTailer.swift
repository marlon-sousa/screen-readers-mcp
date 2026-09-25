// ROLE: adapter seam delivering the lines appended to a file, as they arrive.
// USED BY: ContainerFileSpeechSource.
// IMPLEMENTED BY: FileLineTailer and FakeLineTailer.
// `onLine` may run on any thread; the SpeechBuffer is what makes that safe.
public protocol LineTailer: AnyObject {
	/// Delivers complete lines appended after the file's current end; a file that does not exist yet is not an error.
	func start(_ onLine: @escaping (String) -> Void)

	/// Stop delivering. Idempotent, and never throws: teardown calls it.
	func stop()
}
