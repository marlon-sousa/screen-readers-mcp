// ROLE: controller for `pressGesture`: presses the given gestures in order, then reports what
// the reader said.
// BUILT BY: Registry. DRIVES: CommandVocabulary, the KeyPresser and PermissionBroker ports, the
// session's SpeechBuffer and, on a failure only, the ReaderLiveness port.
// Each press's span is where the ring stood either side of that key going out, so speech caused
// by one gesture can land after the next went out and be credited to it.

import Foundation
import ScreenReaderWire

public final class PressGestureHandler: CommandHandler {
	public let mutatesReader = true

	public init() {}

	public func execute(_ context: SessionContext, _ request: Request) throws -> any Encodable {
		let params = try request.params(as: PressGestureParams.self)
		let adapters = try readerEdge(context)
		let buffer = try context.speechBuffer()
		let grace = Double(max(0, params.graceMs)) / 1000.0

		// Warned before the vocabulary check and before any dispatch: if the human cannot be told,
		// nothing happens to their machine.
		try HumanWarning.honour(context, params.announce)

		// Read once per call, not cached: a change applies on the next call, and every id in one batch
		// resolves against one answer.
		let readerModifier = adapters.readerModifier.modifier()

		// Every id is classified before the first goes out, so a refused id presses nothing at all.
		let gestures = try params.gestures.map { gesture -> Keystroke in
			do {
				return try CommandVocabulary.classify(gesture, readerModifier: readerModifier)
			} catch let refusal as GestureIdRefused {
				throw CommandError(refusal.description)
			}
		}

		// Once per batch, and not at all for an empty one, so `press_gesture []` raises no consent dialog.
		if !gestures.isEmpty {
			try AccessibilityGrant.ensure(adapters.permissions, orElse: "nothing was pressed")
		}

		let startIndex = buffer.nextIndex()
		var pressed: [GesturePress] = []
		for gesture in gestures {
			// Taken before dispatch: the coordinate the ring stood at when this gesture went out.
			let pressFrom = buffer.nextIndex()
			// The canonical spelling, so `Command+L` is recorded and reported as `command+l`.
			let identifier = CommandVocabulary.identifier(for: gesture)
			context.transcript.gesture(identifier)
			try dispatch(gesture, identifier, adapters)
			_ = buffer.collectSince(pressFrom, grace: grace)
			pressed.append(
				GesturePress(gesture: identifier, speechFrom: pressFrom, speechTo: buffer.nextIndex())
			)
		}

		// One read of the whole window, so the answer cannot disagree with itself.
		let read = buffer.entriesSince(startIndex)
		return GestureResult(
			pressed: pressed,
			speech: Observation.speechEntries(read.entries),
			speechFrom: read.fromIndex,
			speechTo: read.toIndex,
			// Nil: this bridge announces no `state` capability.
			state: nil
		)
	}

	private func readerEdge(_ context: SessionContext) throws -> AdapterSet {
		guard let adapters = context.adapters else {
			throw CommandError("a gesture was pressed before `hello` built the reader edge")
		}
		return adapters
	}

	/// Press one gesture, and name what went wrong if it would not go.
	/// A posted `CGEvent` says nothing about whether anything received it, so a failure adds whether
	/// the reader is running; a press nobody hears is not an error.
	private func dispatch(
		_ keystroke: Keystroke, _ identifier: String, _ adapters: AdapterSet
	) throws {
		do {
			try adapters.keyPresser.press(keystroke)
		} catch let failure as KeyPressFailure {
			throw CommandError(explain(failure, identifier, adapters))
		}
	}

	/// Turn a press failure into something an agent can act on.
	private func explain(
		_ failure: KeyPressFailure, _ identifier: String, _ adapters: AdapterSet
	) -> String {
		guard adapters.readerLiveness.readerIsRunning() else {
			return
				"'\(identifier)' could not be pressed: \(failure.description). VoiceOver is also not "
				+ "running at all, which is very probably the whole story. Recovery: ask the human at "
				+ "this machine to start VoiceOver -- Command-F5 is what a person presses -- and try "
				+ "again."
		}
		return "'\(identifier)' could not be pressed: \(failure.description)"
	}
}
