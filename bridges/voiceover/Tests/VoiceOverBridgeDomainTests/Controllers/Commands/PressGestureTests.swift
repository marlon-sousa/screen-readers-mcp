// Mirrors Sources/VoiceOverBridgeDomain/Controllers/Commands/PressGesture.swift.

import Fakes
import ScreenReaderWire
import Testing

@testable import VoiceOverBridgeDomain

@Suite("PressGesture")
struct PressGestureTests {
	private let handler = PressGestureHandler()

	private func context(
		mode: CaptureMode = .live,
		liveness: FakeReaderLiveness = FakeReaderLiveness(),
		keys: FakeKeyPresser = FakeKeyPresser(),
		permissions: FakePermissionBroker = FakePermissionBroker(),
		transcript: FakeTranscript = FakeTranscript(),
		announcer: FakeAnnouncer = FakeAnnouncer(),
		readerModifier: FakeReaderModifierSetting = FakeReaderModifierSetting()
	) -> SessionContext {
		let context = SessionContext(
			clock: FakeClock(), transcript: transcript, attended: true, close: { _ in })
		context.mode = mode
		context.adapters = fakeAdapterSet(
			mode: mode, readerLiveness: liveness, keyPresser: keys,
			readerModifier: readerModifier, permissions: permissions, announcer: announcer)
		context.speech = SpeechBuffer(clock: FakeClock())
		return context
	}

	private func request(
		_ gestures: [String], graceMs: Int = 0, announce: String = ""
	) -> Request {
		Request(
			id: 1, cmd: Command.pressGesture.rawValue,
			params: [
				"gestures": .array(gestures.map { .string($0) }),
				"graceMs": .int(graceMs),
				"announce": .string(announce),
			])
	}

	@Test("the keys go out IN ORDER, which is half of what the command promises")
	func gesturesAreDispatchedInOrder() throws {
		let keys = FakeKeyPresser()
		let value = try handler.execute(context(keys: keys), request(["vo+m", "command+l"]))
		let result = try #require(value as? GestureResult)
		#expect(keys.describedPresses == ["control+option+m", "command+l"])
		#expect(result.pressed.map(\.gesture) == keys.describedPresses)
	}

	@Test("every gesture is recorded in the transcript BEFORE it is sent")
	func everyGestureIsTranscribed() throws {
		let transcript = FakeTranscript()
		let keys = FakeKeyPresser()
		keys.failures["command+l"] = KeyPressFailure("boom")
		_ = try? handler.execute(
			context(keys: keys, transcript: transcript), request(["vo+m", "command+l"]))
		#expect(transcript.gestures == ["control+option+m", "command+l"])
	}

	@Test("a press that fails aborts the REMAINDER of the batch")
	func aFailedPressAbortsTheRest() throws {
		let keys = FakeKeyPresser()
		keys.failures["command+ç"] = KeyPressFailure("no key produces that")
		#expect(throws: CommandError.self) {
			try handler.execute(context(keys: keys), request(["vo+m", "command+ç", "command+l"]))
		}
		#expect(keys.describedPresses == ["control+option+m", "command+ç"])
	}

	@Test("A COMMAND NAME IS REFUSED, AND THE REFUSAL NAMES THE ROUTE A PERSON TAKES")
	func aCommandNameIsRefused() throws {
		let keys = FakeKeyPresser()
		do {
			_ = try handler.execute(context(keys: keys), request(["go to desktop"]))
			Issue.record("expected 'go to desktop' to be refused")
		} catch let error as CommandError {
			#expect(error.description.contains("go to desktop"))
			#expect(error.description.contains("vo+m"))
			#expect(error.description.contains("Commands menu"))
		}
		#expect(keys.pressed.isEmpty)
	}

	@Test("an id this reader cannot take is refused BEFORE any of the batch is dispatched")
	func aRefusedIdStopsTheWholeBatch() throws {
		let keys = FakeKeyPresser()
		#expect(throws: CommandError.self) {
			try handler.execute(context(keys: keys), request(["vo+m", "VO-D"]))
		}
		#expect(keys.pressed.isEmpty)
	}

	@Test("a MALFORMED KEYSTROKE stops the batch too, and says what is wrong with the id")
	func aMalformedKeystrokeStopsTheWholeBatch() throws {
		let keys = FakeKeyPresser()
		do {
			_ = try handler.execute(context(keys: keys), request(["vo+m", "cmd+l"]))
			Issue.record("expected 'cmd+l' to be refused")
		} catch let error as CommandError {
			#expect(error.description.contains("is not a modifier"))
		}
		#expect(keys.pressed.isEmpty)
	}

	@Test("A KEYSTROKE GOES TO THE KEY PRESSER, which is the only place a gesture goes")
	func aKeystrokeTakesTheSystemRoute() throws {
		let keys = FakeKeyPresser()
		let value = try handler.execute(context(keys: keys), request(["command+l"]))
		let result = try #require(value as? GestureResult)

		#expect(keys.describedPresses == ["command+l"])
		#expect(result.pressed.map(\.gesture) == ["command+l"])
	}

	@Test("a batch may mix chords, `vo` chords and bare keys, and they go out in order")
	func aBatchMayMixEveryShapeOfKeystroke() throws {
		let keys = FakeKeyPresser()
		let value = try handler.execute(
			context(keys: keys), request(["command+l", "vo+f3", "kb:enter"]))
		let result = try #require(value as? GestureResult)

		#expect(keys.describedPresses == ["command+l", "control+option+f3", "enter"])
		#expect(result.pressed.map(\.gesture) == ["command+l", "control+option+f3", "kb:enter"])
	}

	@Test("A BARE KEY NEEDS ITS `kb:` PREFIX, and the refusal names the spelling")
	func aBareKeyNeedsItsPrefix() throws {
		let keys = FakeKeyPresser()
		do {
			_ = try handler.execute(context(keys: keys), request(["enter"]))
			Issue.record("expected 'enter' to be refused")
		} catch let error as CommandError {
			#expect(error.description.contains("kb:enter"))
		}
		#expect(keys.pressed.isEmpty)
	}

	@Test("the transcript records what the bridge UNDERSTOOD, not what it was handed")
	func theTranscriptRecordsTheUnderstanding() throws {
		let transcript = FakeTranscript()
		_ = try handler.execute(context(transcript: transcript), request(["Command+L", "vo+m"]))
		#expect(transcript.gestures == ["command+l", "control+option+m"])
	}

	@Test("a keystroke this machine cannot press is reported with the id that failed")
	func anUnpressableKeystrokeIsNamed() throws {
		let keys = FakeKeyPresser()
		keys.failures["command+ç"] = KeyPressFailure(
			"the keyboard layout active on this machine has no key that produces 'ç'")
		do {
			_ = try handler.execute(context(keys: keys), request(["command+ç"]))
			Issue.record("expected the press to fail")
		} catch let error as CommandError {
			#expect(error.description.contains("'command+ç' could not be pressed"))
			#expect(error.description.contains("no key that produces"))
		}
	}

	@Test("A GESTURE ASKS FOR THE ACCESSIBILITY GRANT, exactly as a `typeText` does")
	func aKeystrokeAsksForTheGrant() throws {
		let permissions = FakePermissionBroker(state: .granted)
		let keys = FakeKeyPresser()
		_ = try handler.execute(
			context(keys: keys, permissions: permissions), request(["command+l"]))
		#expect(permissions.statusReads == [.accessibility])
		#expect(permissions.requests.isEmpty)
		#expect(keys.describedPresses == ["command+l"])
	}

	@Test("AN EMPTY BATCH ASKS THE BROKER NOTHING AT ALL")
	func anEmptyBatchNeverTouchesTheBroker() throws {
		let permissions = FakePermissionBroker(state: .notGranted)
		_ = try handler.execute(context(permissions: permissions), request([]))
		#expect(permissions.requests.isEmpty)
		#expect(permissions.statusReads.isEmpty)
	}

	@Test("WITHOUT THE GRANT, NOTHING IS PRESSED, and no other route is offered")
	func withoutTheGrantNothingMoves() throws {
		let permissions = FakePermissionBroker(state: .notGranted)
		let keys = FakeKeyPresser()
		do {
			_ = try handler.execute(
				context(keys: keys, permissions: permissions), request(["vo+m", "command+l"]))
			Issue.record("expected the missing grant to refuse the batch")
		} catch let error as CommandError {
			#expect(error.description.contains("System Settings"))
			#expect(error.description.contains("nothing was pressed"))
			#expect(!error.description.contains("COMMAND NAMES"))
		}
		#expect(permissions.requests == [.accessibility])
		#expect(keys.pressed.isEmpty)
	}

	@Test("each press owns the span the ring stood at either side of ITS dispatch")
	func eachPressOwnsItsOwnSpan() throws {
		let keys = FakeKeyPresser()
		let ctx = context(keys: keys)
		let buffer = try #require(ctx.speech)
		keys.onPress = { keystroke in
			buffer.append(CapturedUtterance(text: "said after \(keystroke.described)"))
		}
		let value = try handler.execute(ctx, request(["vo+m", "command+l"], graceMs: 50))
		let pressed = try #require(value as? GestureResult).pressed
		#expect(pressed.count == 2)
		#expect(pressed[0].speechFrom == 1)
		#expect(pressed[0].speechTo == 2)
		#expect(pressed[1].speechFrom == 2)
		#expect(pressed[1].speechTo == 3)
	}

	@Test("a gesture that said nothing has an EMPTY span rather than a missing one")
	func aSilentGestureHasAnEmptySpan() throws {
		let value = try handler.execute(context(), request(["vo+m"], graceMs: 0))
		let result = try #require(value as? GestureResult)
		let press = try #require(result.pressed.first)
		#expect(press.speechFrom == press.speechTo)
		#expect(result.speech.isEmpty)
	}

	@Test("the reported window spans the WHOLE batch, and the entries carry their own indices")
	func theWindowSpansTheBatch() throws {
		let keys = FakeKeyPresser()
		let ctx = context(keys: keys)
		let buffer = try #require(ctx.speech)
		keys.onPress = { _ in buffer.append(CapturedUtterance(text: "spoken")) }
		let value = try handler.execute(ctx, request(["vo+m", "command+l"], graceMs: 50))
		let gesture = try #require(value as? GestureResult)
		#expect(gesture.speechFrom == 1)
		#expect(gesture.speechTo == 3)
		#expect(gesture.speech.map(\.index) == [1, 2])
	}

	@Test("`state` is never sampled: this bridge announces no `state` capability")
	func stateIsAlwaysNil() throws {
		let value = try handler.execute(context(), request(["vo+m"]))
		let result = try #require(value as? GestureResult)
		#expect(result.state == nil)
	}

	@Test("a press failure on a machine with no reader says so, and says how to start one")
	func aMissingReaderIsNamedOnAFailure() throws {
		let keys = FakeKeyPresser()
		keys.failures["control+option+m"] = KeyPressFailure("the event could not be posted")
		do {
			_ = try handler.execute(
				context(liveness: FakeReaderLiveness(isRunning: false), keys: keys), request(["vo+m"]))
			Issue.record("expected the press to fail")
		} catch let error as CommandError {
			#expect(error.description.contains("the event could not be posted"))
			#expect(error.description.contains("not running at all"))
			#expect(error.description.contains("Command-F5"))
		}
	}

	@Test("the same failure with the reader present is reported as itself")
	func aPressFailureWithAHealthyReaderIsReportedAsItself() throws {
		let keys = FakeKeyPresser()
		keys.failures["control+option+m"] = KeyPressFailure("the event could not be posted")
		do {
			_ = try handler.execute(
				context(liveness: FakeReaderLiveness(isRunning: true), keys: keys), request(["vo+m"]))
			Issue.record("expected the press to fail")
		} catch let error as CommandError {
			#expect(error.description.contains("the event could not be posted"))
			#expect(!error.description.contains("not running at all"))
		}
	}

	@Test("liveness is NOT asked on a healthy run, because the answer costs a lookup")
	func livenessIsNotAskedWhenNothingFailed() throws {
		let liveness = FakeReaderLiveness()
		_ = try handler.execute(context(liveness: liveness), request(["vo+m", "command+l"]))
		#expect(liveness.asked == 0)
	}

	@Test("liveness is not asked for a REFUSED id either -- that is the agent's mistake")
	func livenessIsNotAskedForARefusedId() throws {
		let liveness = FakeReaderLiveness()
		_ = try? handler.execute(context(liveness: liveness), request(["go to desktop"]))
		#expect(liveness.asked == 0)
	}

	@Test("the announce IS SPOKEN, in BOTH modes -- 13.10 made that keepable")
	func announceIsSpokenInEitherMode() throws {
		for mode in [CaptureMode.silent, .live] {
			let announcer = FakeAnnouncer()
			let keys = FakeKeyPresser()
			_ = try handler.execute(
				context(mode: mode, keys: keys, announcer: announcer),
				request(["vo+d"], announce: "moving to the desktop"))
			#expect(announcer.spoken == ["moving to the desktop"])
			#expect(keys.describedPresses == ["control+option+d"])
		}
	}

	@Test("a warning that could not be spoken PRESSES NOTHING")
	func anUnspeakableWarningStopsEverything() throws {
		let announcer = FakeAnnouncer()
		announcer.fails = true
		let keys = FakeKeyPresser()
		do {
			_ = try handler.execute(
				context(mode: .silent, keys: keys, announcer: announcer),
				request(["vo+d"], announce: "moving to the desktop"))
			Issue.record("expected the gesture to be refused when the human could not be warned")
		} catch let error as CommandError {
			#expect(error.description.contains("could not be warned"))
			#expect(error.description.contains("empty"))
		}
		#expect(keys.pressed.isEmpty)
	}

	@Test("whitespace is not an announcement, so nothing is said and nothing is refused")
	func whitespaceAnnounceIsAbsence() throws {
		let keys = FakeKeyPresser()
		_ = try handler.execute(
			context(mode: .silent, keys: keys), request(["vo+d"], announce: "   "))
		#expect(keys.describedPresses == ["control+option+d"])
	}

	@Test("it declares that it MOVES the user's machine")
	func itMutatesTheReader() {
		#expect(handler.mutatesReader)
		#expect(!handler.availableBeforeHello)
		#expect(handler.resetsInactivity)
	}

	@Test("pressed before `hello`, it says so rather than crashing")
	func withoutAReaderEdgeItSaysSo() throws {
		let bare = SessionContext(
			clock: FakeClock(), transcript: FakeTranscript(), attended: true, close: { _ in })
		#expect(throws: CommandError.self) {
			try handler.execute(bare, request(["vo+m"]))
		}
	}

	@Test("`vo+m` GOES TO THE KEY PRESSER, resolved against what the machine says")
	func voReachesTheKeyPresser() throws {
		let keys = FakeKeyPresser()
		_ = try PressGestureHandler().execute(context(keys: keys), request(["vo+m"]))

		#expect(
			keys.pressed == [
				Keystroke(
					modifiers: [.control, .option], keys: [.character("m")],
					holdsReaderModifier: true)
			])
	}

	@Test("THE BINDING IS READ PER CALL, not once and remembered")
	func theBindingIsReadEveryTime() throws {
		let modifier = FakeReaderModifierSetting()
		let context = context(readerModifier: modifier)
		_ = try PressGestureHandler().execute(context, request(["vo+m", "vo+d"]))
		#expect(modifier.reads == 1)
		_ = try PressGestureHandler().execute(context, request(["vo+m"]))
		#expect(modifier.reads == 2)
	}

	@Test("A REFUSED `vo` PRESSES NOTHING AT ALL, even from the end of a batch")
	func aRefusedVoPressesNothing() {
		let keys = FakeKeyPresser()
		let context = context(keys: keys, readerModifier: FakeReaderModifierSetting(.capsLock))
		#expect(throws: CommandError.self) {
			_ = try PressGestureHandler().execute(context, request(["command+l", "vo+m"]))
		}
		#expect(keys.pressed.isEmpty)
	}

	@Test("the refusal reaches the agent with the reason, not a bare failure")
	func theRefusalCarriesItsReason() {
		let context = context(readerModifier: FakeReaderModifierSetting(.capsLock))
		do {
			_ = try PressGestureHandler().execute(context, request(["vo+m"]))
			Issue.record("expected a refusal")
		} catch let failure as CommandError {
			#expect(failure.description.contains("CAPS LOCK"))
		} catch {
			Issue.record("unexpected error: \(error)")
		}
	}

	@Test("what the transcript and the result record is the RESOLVED spelling")
	func theRecordSaysWhatWentOut() throws {
		let transcript = FakeTranscript()
		let context = context(transcript: transcript)
		let result = try PressGestureHandler().execute(context, request(["vo+m"]))

		#expect(transcript.gestures == ["control+option+m"])
		let pressed = try #require(result as? GestureResult).pressed
		#expect(pressed.map(\.gesture) == ["control+option+m"])
	}

	@Test("a `vo` chord costs the Accessibility grant, like any other keystroke")
	func voCostsTheGrant() throws {
		let permissions = FakePermissionBroker(state: .notGranted)
		let context = context(permissions: permissions)
		#expect(throws: CommandError.self) {
			_ = try PressGestureHandler().execute(context, request(["vo+m"]))
		}
		#expect(permissions.requests == [Permission.accessibility])
	}
}
