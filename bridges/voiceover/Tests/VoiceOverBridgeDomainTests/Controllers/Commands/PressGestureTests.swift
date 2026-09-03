// Mirrors Sources/VoiceOverBridgeDomain/Controllers/Commands/PressGesture.swift.
//
// Three properties carry most of this file. The first is ATTRIBUTION: each press
// owns the half-open span the ring stood at either side of ITS dispatch, so an
// empty span means "this gesture said nothing" rather than "we read too late" --
// and that is only testable if speech can be made to arrive as a consequence of
// a particular gesture, which is what FakeKeyPresser's `onPress` is for. The
// second is that a FAILURE IS NAMED: spec 0041's requirement is that a bridge on
// this route never answers a machine-level fault with an empty read-back.
//
// THE THIRD WAS THE ROUTING, AND 13.31 RETIRED IT. From 13.17 to 13.31 there were
// two routes -- a command name to the reader at no permission cost, a keystroke to
// the system at the price of the Accessibility grant -- and half this file was
// about which id reached which port. There is one port now: no VoiceOver user can
// type a command name, so neither does a session standing in for one (spec 0055).
//
// WHAT REPLACED THOSE TESTS IS THE REFUSAL, and it is asserted as carefully as the
// routing ever was. An agent carrying guidance from any earlier build will send a
// phrase here, and what it must not conclude is that the act is unreachable.

import Fakes
import ScreenReaderWire
import Testing

@testable import VoiceOverBridgeDomain

@Suite("PressGesture")
struct PressGestureTests {
	private let handler = PressGestureHandler()

	/// A session with a reader edge of doubles, in whichever mode the test wants.
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

	// -- dispatch --------------------------------------------------------------

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
		// Before, not after: the gesture anyone reading a transcript is looking
		// for is the one that hung or crashed the reader, and a record written on
		// success would be missing exactly that one.
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
		// The one after the failure never went out.
		#expect(keys.describedPresses == ["control+option+m", "command+ç"])
	}

	// -- the vocabulary --------------------------------------------------------

	@Test("A COMMAND NAME IS REFUSED, AND THE REFUSAL NAMES THE ROUTE A PERSON TAKES")
	func aCommandNameIsRefused() throws {
		// 13.31's whole change at this layer, and the assertion is about the
		// MESSAGE. `go to desktop` was dispatched to the reader by name until this
		// entry; every document written about this bridge before now says to send
		// exactly that, so the refusal has to teach rather than merely decline.
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
		// The ordering that matters for a mutating command: catching a bad id in
		// position two after position one has already moved the machine would
		// leave the reader somewhere neither side asked for. `VO-D` is the id that
		// is refused for a reason no feature retires -- Apple writes `VO-Shift-M`
		// too, so the hyphen would be a second complete notation.
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
			// The notation was right and the contents were wrong, so the message has
			// to be about the modifier rather than about the Commands menu.
			#expect(error.description.contains("is not a modifier"))
		}
		#expect(keys.pressed.isEmpty)
	}

	@Test("A KEYSTROKE GOES TO THE KEY PRESSER, which is the only place a gesture goes")
	func aKeystrokeTakesTheSystemRoute() throws {
		// 13.17's point, which outlived the alternative it was contrasted with:
		// `command+l` is not a command VoiceOver has, and dispatching it as one
		// failed with `Command does not exist` while the location bar stayed shut.
		let keys = FakeKeyPresser()
		let value = try handler.execute(context(keys: keys), request(["command+l"]))
		let result = try #require(value as? GestureResult)

		#expect(keys.describedPresses == ["command+l"])
		#expect(result.pressed.map(\.gesture) == ["command+l"])
	}

	@Test("a batch may mix chords, `vo` chords and bare keys, and they go out in order")
	func aBatchMayMixEveryShapeOfKeystroke() throws {
		// What driving a Mac actually looks like: open the location bar with a
		// chord, ask the reader where it landed with one of its own, then commit
		// with Return. Every one of them is a key now -- the last was `return key`,
		// dispatched by the reader, until 13.31.
		let keys = FakeKeyPresser()
		let value = try handler.execute(
			context(keys: keys), request(["command+l", "vo+f3", "kb:enter"]))
		let result = try #require(value as? GestureResult)

		#expect(keys.describedPresses == ["command+l", "control+option+f3", "enter"])
		#expect(result.pressed.map(\.gesture) == ["command+l", "control+option+f3", "kb:enter"])
	}

	@Test("A BARE KEY NEEDS ITS `kb:` PREFIX, and the refusal names the spelling")
	func aBareKeyNeedsItsPrefix() throws {
		// It was refused before 13.31 too, for the opposite reason: a lone token
		// was one of the reader's own `… key` commands, which cost no grant, so
		// routing it through the event path would have spent one for nothing. The
		// rule is kept now that the reason is gone, because `kb:enter` is what the
		// transcript writes and what lane 1 writes.
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
		// ONE VERB, WHICH IS LANE 1's SHAPE. NVDA writes `control+o` -- which its
		// reader passes to the application -- and `NVDA+t` -- which it consumes --
		// on identical lines, and a transcript is read across readers.
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

	// -- the grant -------------------------------------------------------------

	@Test("A GESTURE ASKS FOR THE ACCESSIBILITY GRANT, exactly as a `typeText` does")
	func aKeystrokeAsksForTheGrant() throws {
		let permissions = FakePermissionBroker(state: .granted)
		let keys = FakeKeyPresser()
		_ = try handler.execute(
			context(keys: keys, permissions: permissions), request(["command+l"]))
		// Held already, so it is READ and not requested -- which is what makes a
		// session on a granted machine cost nothing.
		#expect(permissions.statusReads == [.accessibility])
		#expect(permissions.requests.isEmpty)
		#expect(keys.describedPresses == ["command+l"])
	}

	@Test("AN EMPTY BATCH ASKS THE BROKER NOTHING AT ALL")
	func anEmptyBatchNeverTouchesTheBroker() throws {
		// The remains of 13.8's lever, and worth keeping as an assertion: the grant
		// is asked for by a batch that is about to move the machine, so a batch that
		// is about to do nothing raises no consent dialog on somebody's machine.
		// From 13.8 to 13.31 this test read `A BATCH OF COMMAND NAMES ASKS THE
		// BROKER NOTHING`, which was the same property when there was a route that
		// cost no grant.
		let permissions = FakePermissionBroker(state: .notGranted)
		_ = try handler.execute(context(permissions: permissions), request([]))
		#expect(permissions.requests.isEmpty)
		#expect(permissions.statusReads.isEmpty)
	}

	@Test("WITHOUT THE GRANT, NOTHING IS PRESSED, and no other route is offered")
	func withoutTheGrantNothingMoves() throws {
		// The check comes before the first dispatch because the injection cannot
		// fail visibly: an event posted by an untrusted process is dropped by the
		// window server with nothing said anywhere, so a batch that pressed half of
		// itself and silently dropped the rest would report a success that did half
		// of what was asked.
		let permissions = FakePermissionBroker(state: .notGranted)
		let keys = FakeKeyPresser()
		do {
			_ = try handler.execute(
				context(keys: keys, permissions: permissions), request(["vo+m", "command+l"]))
			Issue.record("expected the missing grant to refuse the batch")
		} catch let error as CommandError {
			#expect(error.description.contains("System Settings"))
			#expect(error.description.contains("nothing was pressed"))
			// AND IT MUST NOT OFFER THE COMMAND-NAME ROUTE, which is what this message
			// ended with until 13.31. There is no route that works without the grant,
			// and saying otherwise sends an agent to an id that is refused.
			#expect(!error.description.contains("COMMAND NAMES"))
		}
		#expect(permissions.requests == [.accessibility])
		#expect(keys.pressed.isEmpty)
	}

	// -- attribution and the grace window --------------------------------------

	@Test("each press owns the span the ring stood at either side of ITS dispatch")
	func eachPressOwnsItsOwnSpan() throws {
		let keys = FakeKeyPresser()
		let ctx = context(keys: keys)
		let buffer = try #require(ctx.speech)
		// Speech arrives as a CONSEQUENCE of each press, which is the only
		// arrangement in which attribution can be wrong.
		keys.onPress = { keystroke in
			buffer.append(CapturedUtterance(text: "said after \(keystroke.described)"))
		}
		let value = try handler.execute(ctx, request(["vo+m", "command+l"], graceMs: 50))
		let pressed = try #require(value as? GestureResult).pressed
		#expect(pressed.count == 2)
		// Sentinel at 0, so the first real capture is 1 and the second is 2.
		#expect(pressed[0].speechFrom == 1)
		#expect(pressed[0].speechTo == 2)
		#expect(pressed[1].speechFrom == 2)
		#expect(pressed[1].speechTo == 3)
	}

	@Test("a gesture that said nothing has an EMPTY span rather than a missing one")
	func aSilentGestureHasAnEmptySpan() throws {
		// Visible rather than inferred: `speechFrom == speechTo` is the answer,
		// and it is a fact about an instant rather than a claim that the gesture
		// will never say anything.
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

	// -- failures are NAMED ----------------------------------------------------

	// ==========================================================================
	// TWO CONDITIONS, WHERE THERE WERE THREE.
	// ==========================================================================
	//
	// Until 13.31 a failure here could also mean `scriptingChannelDead` -- the
	// reader answering its own name and nothing else -- and separating that from a
	// switched-off AppleScript preference and from a reader that was simply gone
	// took three ports and four tests, because all three failed with identical
	// error numbers. Two of those conditions cannot happen any more: there is no
	// scripting object model in this bridge and no preference gating one.
	//
	// What is left is the read a press cannot make for itself. A `CGEvent` that
	// posts successfully says nothing about whether anything was there to receive
	// it, so the one thing worth adding to a FAILURE is whether the reader exists.

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
			// COMMAND-F5, NOT `killall && open`: the recovery a person at the machine
			// actually performs, and the one the 2026-09-02 field report found works
			// when the pair this repo used to print did not.
			#expect(error.description.contains("Command-F5"))
		}
	}

	@Test("the same failure with the reader present is reported as itself")
	func aPressFailureWithAHealthyReaderIsReportedAsItself() throws {
		// The control for the test above. A reader that is there tells an agent
		// nothing about why an event would not post, so nothing is added.
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

	// -- announce --------------------------------------------------------------

	@Test("the announce IS SPOKEN, in BOTH modes -- 13.10 made that keepable")
	func announceIsSpokenInEitherMode() throws {
		// A SILENT session is the one place `announce` is the human's only channel,
		// because the reader is being rendered mute on their behalf. Until 13.10
		// there was no channel and the promise was REFUSED rather than half-kept;
		// the Announcer speaks outside VoiceOver, so both modes warn them now.
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
		// The ordering proof: the warning is the first thing the handler does, so if
		// the human cannot be told what is about to happen to their machine, nothing
		// happens to it.
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

	// -- the flags the dispatch loop reads -------------------------------------

	@Test("it declares that it MOVES the user's machine")
	func itMutatesTheReader() {
		// The first handler in this bridge that does. An observe-only session
		// refuses it on the strength of this flag alone.
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

	// -- `vo`, read from the machine, which is 13.25 ----------------------------

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
		// Spec 0052 §3.2: somebody who changes their modifier mid-session gets the
		// right keys on the very next press, which is only true if it is asked
		// again. Once per CALL and not once per gesture, so one batch is resolved
		// against one answer.
		let modifier = FakeReaderModifierSetting()
		let context = context(readerModifier: modifier)
		_ = try PressGestureHandler().execute(context, request(["vo+m", "vo+d"]))
		#expect(modifier.reads == 1)
		_ = try PressGestureHandler().execute(context, request(["vo+m"]))
		#expect(modifier.reads == 2)
	}

	@Test("A REFUSED `vo` PRESSES NOTHING AT ALL, even from the end of a batch")
	func aRefusedVoPressesNothing() {
		// The batch is classified before any of it is dispatched, which is what
		// makes the Caps Lock refusal safe rather than half-done: an agent whose
		// third gesture is unpressable does not get the first two.
		let keys = FakeKeyPresser()
		let context = context(keys: keys, readerModifier: FakeReaderModifierSetting(.capsLock))
		#expect(throws: CommandError.self) {
			_ = try PressGestureHandler().execute(context, request(["command+l", "vo+m"]))
		}
		#expect(keys.pressed.isEmpty)
	}

	@Test("the refusal reaches the agent with the reason, not a bare failure")
	func theRefusalCarriesItsReason() {
		// A HANDSHAKE NORMALLY REFUSES THIS MACHINE OUTRIGHT since 13.31 -- rung 1
		// needs a pressable `vo`, and there is no second route to fall back to -- so
		// what this exercises is a modifier that changed WHILE a session ran, which
		// is the case the per-call read exists for.
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
		// Two machines whose `vo` differs must not produce identical records, and
		// this is the one place an agent can see what the binding resolved to.
		let transcript = FakeTranscript()
		let context = context(transcript: transcript)
		let result = try PressGestureHandler().execute(context, request(["vo+m"]))

		// No `kb:` prefix, and that is the existing rule rather than a new one: a
		// resolved `vo` chord HAS modifiers, so it spells itself the way
		// `command+l` does and round-trips without one.
		#expect(transcript.gestures == ["control+option+m"])
		let pressed = try #require(result as? GestureResult).pressed
		#expect(pressed.map(\.gesture) == ["control+option+m"])
	}

	@Test("a `vo` chord costs the Accessibility grant, like any other keystroke")
	func voCostsTheGrant() throws {
		// 13.8's lever as 13.25 and 13.31 left it: a keystroke is a system event
		// whatever spells it, and every gesture is one now.
		let permissions = FakePermissionBroker(state: .notGranted)
		let context = context(permissions: permissions)
		#expect(throws: CommandError.self) {
			_ = try PressGestureHandler().execute(context, request(["vo+m"]))
		}
		#expect(permissions.requests == [Permission.accessibility])
	}
}
