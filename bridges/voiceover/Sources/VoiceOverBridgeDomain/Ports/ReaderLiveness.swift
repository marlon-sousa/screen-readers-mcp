// ROLE: port -- is the reader running at all?
// IMPLEMENTED BY: VoiceOverLiveness, over the RunningApplications seam; FakeReaderLiveness.
// BUILT BY: VoiceOverAdapterFactory.
// USED BY: ReaderEdgeSetup's reader-running rung, and the PressGesture handler only after a press has failed.
// A healthy answer says nothing about the application under test: a wedged Finder looks like a dead reader from outside.
public protocol ReaderLiveness: AnyObject {
	/// Not a claim that the reader is well: a running reader may still ignore synthesized key events.
	func readerIsRunning() -> Bool

	/// A request: only `readerIsRunning` afterwards is evidence, because macOS returns from `open` before the launch.
	func activate()
}
