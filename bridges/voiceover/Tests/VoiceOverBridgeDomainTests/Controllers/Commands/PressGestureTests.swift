// Mirrors Sources/VoiceOverBridgeDomain/Controllers/Commands/PressGesture.swift.
//
// Three properties carry most of this file. The first is ATTRIBUTION: each press
// owns the half-open span the ring stood at either side of ITS dispatch, so an
// empty span means "this gesture said nothing" rather than "we read too late" --
// and that is only testable if speech can be made to arrive as a consequence of
// a particular gesture, which is what FakeGestureSender's `onPress` is for. The
// second is that a FAILURE IS NAMED: spec 0041's requirement is that a bridge on
// this route never answers a machine-level fault with an empty read-back.
//
// THE THIRD ARRIVED WITH 13.17 AND IS THE ROUTING: one command, two routes, and
// the id decides. A command name goes to the reader and costs no permission; a
// keystroke goes to the system and costs the Accessibility grant. Both halves
// are asserted here -- that each id reaches the right port, and that a batch of
// COMMAND NAMES still goes past a counting broker without being asked anything,
// which is 13.8's lever as this entry narrowed it.

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
		sender: FakeGestureSender = FakeGestureSender(),
		liveness: FakeReaderLiveness = FakeReaderLiveness(),
		keys: FakeKeyPresser = FakeKeyPresser(),
		permissions: FakePermissionBroker = FakePermissionBroker(),
		transcript: FakeTranscript = FakeTranscript(),
		announcer: FakeAnnouncer = FakeAnnouncer(),
		readerModifier: FakeReaderModifierSetting = FakeReaderModifierSetting(),
		readerScripting: FakeReaderScriptingSetting = FakeReaderScriptingSetting()
	) -> SessionContext {
		let context = SessionContext(
			clock: FakeClock(), transcript: transcript, attended: true, close: { _ in })
		context.mode = mode
		context.adapters = fakeAdapterSet(
			mode: mode, gestureSender: sender, readerLiveness: liveness, keyPresser: keys,
			readerModifier: readerModifier, readerScripting: readerScripting,
			permissions: permissions, announcer: announcer)
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

	@Test("the commands go out IN ORDER, which is half of what the command promises")
	func commandsAreDispatchedInOrder() throws {
		let sender = FakeGestureSender()
		let value = try handler.execute(
			context(sender: sender), request(["go to desktop", "describe item in voiceover cursor"]))
		let result = try #require(value as? GestureResult)
		#expect(sender.pressed == ["go to desktop", "describe item in voiceover cursor"])
		#expect(result.pressed.map(\.gesture) == sender.pressed)
	}

	@Test("every command is recorded in the transcript BEFORE it is sent")
	func everyCommandIsTranscribed() throws {
		// Before, not after: the command anyone reading a transcript is looking
		// for is the one that hung or crashed the reader, and a record written on
		// success would be missing exactly that one.
		let transcript = FakeTranscript()
		let sender = FakeGestureSender()
		sender.failures["mute sound toggle"] = .failed("boom")
		_ = try? handler.execute(
			context(sender: sender, transcript: transcript),
			request(["go to desktop", "mute sound toggle"]))
		#expect(transcript.gestures == ["go to desktop", "mute sound toggle"])
	}

	@Test("an unknown command aborts the REMAINDER of the batch")
	func anUnknownCommandAbortsTheRest() throws {
		let sender = FakeGestureSender()
		sender.failures["no such command at all"] = .unknownCommand("no such command at all")
		#expect(throws: CommandError.self) {
			try handler.execute(
				context(sender: sender),
				request(["go to desktop", "no such command at all", "mute sound toggle"]))
		}
		// The one after the failure never went out.
		#expect(sender.pressed == ["go to desktop", "no such command at all"])
	}

	// -- the vocabulary --------------------------------------------------------

	@Test("an id this reader cannot take is refused BEFORE any of the batch is dispatched")
	func aRefusedIdStopsTheWholeBatch() throws {
		// The ordering that matters for a mutating command: catching a bad id in
		// position two after position one has already moved the machine would
		// leave the reader somewhere neither side asked for. `VO-D` is the id that
		// is still refused after 13.17, because "VO" is whatever the user bound
		// their VoiceOver modifier to.
		let sender = FakeGestureSender()
		let keys = FakeKeyPresser()
		#expect(throws: CommandError.self) {
			try handler.execute(context(sender: sender, keys: keys), request(["go to desktop", "VO-D"]))
		}
		#expect(sender.pressed.isEmpty)
		#expect(keys.pressed.isEmpty)
	}

	@Test("a MALFORMED KEYSTROKE stops the batch too, and says what is wrong with the id")
	func aMalformedKeystrokeStopsTheWholeBatch() throws {
		let sender = FakeGestureSender()
		let keys = FakeKeyPresser()
		do {
			_ = try handler.execute(
				context(sender: sender, keys: keys), request(["go to desktop", "cmd+l"]))
			Issue.record("expected 'cmd+l' to be refused")
		} catch let error as CommandError {
			// The notation was right and the contents were wrong, so the message has
			// to be about the modifier rather than about sending a command name.
			#expect(error.description.contains("is not a modifier"))
		}
		#expect(sender.pressed.isEmpty)
		#expect(keys.pressed.isEmpty)
	}

	// -- the two routes, which is what 13.17 added ------------------------------

	@Test("A KEYSTROKE GOES TO THE KEY PRESSER AND NOT TO THE READER")
	func aKeystrokeTakesTheSystemRoute() throws {
		// The entry's whole point: `command+l` is not a command VoiceOver has, and
		// dispatching it as one would fail with `Command does not exist` while the
		// location bar stayed shut.
		let sender = FakeGestureSender()
		let keys = FakeKeyPresser()
		let value = try handler.execute(
			context(sender: sender, keys: keys), request(["command+l"]))
		let result = try #require(value as? GestureResult)

		#expect(sender.pressed.isEmpty)
		#expect(keys.describedPresses == ["command+l"])
		#expect(result.pressed.map(\.gesture) == ["command+l"])
	}

	@Test("a batch may MIX the two, and each id takes its own route in order")
	func aBatchMayMixBothRoutes() throws {
		// What driving a Mac actually looks like: open the location bar with a
		// chord, ask the reader where it landed, then commit with the reader's own
		// `return key` -- which costs no grant and is why the last one goes to the
		// SENDER rather than the presser.
		let sender = FakeGestureSender()
		let keys = FakeKeyPresser()
		let value = try handler.execute(
			context(sender: sender, keys: keys),
			request(["command+l", "describe item with keyboard focus", "return key"]))
		let result = try #require(value as? GestureResult)

		#expect(sender.pressed == ["describe item with keyboard focus", "return key"])
		#expect(keys.describedPresses == ["command+l"])
		// The result reports all three, in the order they were sent, whichever
		// route each took -- because which route carried it is the bridge's
		// business and not the agent's.
		#expect(
			result.pressed.map(\.gesture)
				== ["command+l", "describe item with keyboard focus", "return key"])
	}

	@Test("A KEY WITH NO MODIFIERS IS A COMMAND NAME, and that is the cheap route on purpose")
	func aBareKeyStaysWithTheReader() throws {
		// The `+` is the whole discriminator, so a lone key is never a keystroke --
		// which is the right answer rather than an accident of the rule. The
		// vocabulary contains 30 commands ending in `key` (`return key`, `tab key`,
		// the four arrows, `f1 key` to `f12 key`), the reader dispatches them
		// itself, and they cost NO Accessibility grant. Routing them through the
		// event path would spend the grant for a keypress that never needed it.
		let sender = FakeGestureSender()
		let keys = FakeKeyPresser()
		let permissions = FakePermissionBroker(state: .notGranted)
		_ = try handler.execute(
			context(sender: sender, keys: keys, permissions: permissions),
			request(["return key", "tab key"]))
		#expect(sender.pressed == ["return key", "tab key"])
		#expect(keys.pressed.isEmpty)
		#expect(permissions.requests.isEmpty)
	}

	@Test("the transcript records what the bridge UNDERSTOOD, in one verb for both routes")
	func theTranscriptRecordsBothRoutesTheSameWay() throws {
		// ONE VERB, WHICH IS LANE 1's SHAPE. NVDA writes `control+o` -- which its
		// reader passes to the application -- and `NVDA+t` -- which it consumes --
		// on identical lines, and a transcript is read across readers. The notation
		// itself says which route it took.
		let transcript = FakeTranscript()
		_ = try handler.execute(
			context(transcript: transcript), request(["Command+L", "go to desktop"]))
		#expect(transcript.gestures == ["command+l", "go to desktop"])
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

	@Test("a mid-batch keystroke failure aborts the REMAINDER, like an unknown command")
	func aKeystrokeFailureAbortsTheRest() throws {
		let sender = FakeGestureSender()
		let keys = FakeKeyPresser()
		keys.failures["command+ç"] = KeyPressFailure("no key produces that")
		#expect(throws: CommandError.self) {
			try handler.execute(
				context(sender: sender, keys: keys),
				request(["go to desktop", "command+ç", "mute sound toggle"]))
		}
		#expect(sender.pressed == ["go to desktop"])
	}

	// -- the grant, which is 13.8's lever as 13.17 narrowed it -------------------

	@Test("A BATCH OF COMMAND NAMES ASKS THE BROKER NOTHING AT ALL")
	func commandNamesNeverTouchTheBroker() throws {
		// The property worth having, and the one this entry had to keep. Pressing
		// the reader's own commands is an AppleEvent; nothing about it needs
		// Accessibility, and a bridge that asked anyway would raise a consent
		// dialog on somebody's machine for a command that never needed one.
		let permissions = FakePermissionBroker(state: .notGranted)
		_ = try handler.execute(
			context(permissions: permissions),
			request(["go to desktop", "describe item in voiceover cursor"]))
		#expect(permissions.requests.isEmpty)
		#expect(permissions.statusReads.isEmpty)
	}

	@Test("A KEYSTROKE ASKS FOR THE ACCESSIBILITY GRANT, exactly as a `typeText` does")
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

	@Test("WITHOUT THE GRANT, NOTHING IS PRESSED -- not even the command names in the batch")
	func withoutTheGrantNothingMoves() throws {
		// The check comes before the first dispatch because the injection cannot
		// fail visibly: an event posted by an untrusted process is dropped by the
		// window server with nothing said anywhere, so a batch that pressed its
		// command names and then silently dropped its chord would report a success
		// that did half of what was asked.
		let permissions = FakePermissionBroker(state: .notGranted)
		let sender = FakeGestureSender()
		let keys = FakeKeyPresser()
		do {
			_ = try handler.execute(
				context(sender: sender, keys: keys, permissions: permissions),
				request(["go to desktop", "command+l"]))
			Issue.record("expected the missing grant to refuse the batch")
		} catch let error as CommandError {
			#expect(error.description.contains("System Settings"))
			#expect(error.description.contains("nothing was pressed"))
			// And it names the route that still works without the grant, because an
			// agent that cannot type can still drive the reader.
			#expect(error.description.contains("COMMAND NAMES"))
		}
		#expect(permissions.requests == [.accessibility])
		#expect(sender.pressed.isEmpty)
		#expect(keys.pressed.isEmpty)
	}

	// -- attribution and the grace window --------------------------------------

	@Test("each press owns the span the ring stood at either side of ITS dispatch")
	func eachPressOwnsItsOwnSpan() throws {
		let sender = FakeGestureSender()
		let ctx = context(sender: sender)
		let buffer = try #require(ctx.speech)
		// Speech arrives as a CONSEQUENCE of each command, which is the only
		// arrangement in which attribution can be wrong.
		sender.onPress = { command in
			buffer.append(CapturedUtterance(text: "said after \(command)"))
		}
		let value = try handler.execute(
			ctx, request(["go to desktop", "mute sound toggle"], graceMs: 50))
		let pressed = try #require(value as? GestureResult).pressed
		#expect(pressed.count == 2)
		// Sentinel at 0, so the first real capture is 1 and the second is 2.
		#expect(pressed[0].speechFrom == 1)
		#expect(pressed[0].speechTo == 2)
		#expect(pressed[1].speechFrom == 2)
		#expect(pressed[1].speechTo == 3)
	}

	@Test("a command that said nothing has an EMPTY span rather than a missing one")
	func aSilentCommandHasAnEmptySpan() throws {
		// Visible rather than inferred: `speechFrom == speechTo` is the answer,
		// and it is a fact about an instant rather than a claim that the command
		// will never say anything.
		let value = try handler.execute(context(), request(["mute sound toggle"], graceMs: 0))
		let result = try #require(value as? GestureResult)
		let press = try #require(result.pressed.first)
		#expect(press.speechFrom == press.speechTo)
		#expect(result.speech.isEmpty)
	}

	@Test("the reported window spans the WHOLE batch, and the entries carry their own indices")
	func theWindowSpansTheBatch() throws {
		let sender = FakeGestureSender()
		let ctx = context(sender: sender)
		let buffer = try #require(ctx.speech)
		sender.onPress = { _ in buffer.append(CapturedUtterance(text: "spoken")) }
		let value = try handler.execute(
			ctx, request(["go to desktop", "mute sound toggle"], graceMs: 50))
		let gesture = try #require(value as? GestureResult)
		#expect(gesture.speechFrom == 1)
		#expect(gesture.speechTo == 3)
		#expect(gesture.speech.map(\.index) == [1, 2])
	}

	@Test("`state` is never sampled: this bridge announces no `state` capability")
	func stateIsAlwaysNil() throws {
		let value = try handler.execute(context(), request(["go to desktop"]))
		let result = try #require(value as? GestureResult)
		#expect(result.state == nil)
	}

	// -- failures are NAMED ----------------------------------------------------

	@Test("a dead scripting channel is reported as the NAMED condition, with its recovery")
	func aDeadChannelIsNamed() throws {
		let sender = FakeGestureSender()
		sender.failures["go to desktop"] = .scriptingChannelDead
		let liveness = FakeReaderLiveness(isRunning: true)
		do {
			_ = try handler.execute(
				context(sender: sender, liveness: liveness), request(["go to desktop"]))
			Issue.record("expected the dispatch to fail")
		} catch let error as CommandError {
			#expect(error.description.contains(ReaderCondition.scriptingChannelDead.rawValue))
			// SPELLED AS A PAIR since 13.20: `killall` on its own was measured NOT to
			// bring the reader back, and a recovery that stopped there would leave a
			// blind person with no screen reader.
			#expect(error.description.contains(readerRestartCommand))
		}
		#expect(liveness.asked == 1)
	}

	@Test("a reader that answers nothing at all is a DIFFERENT report from a dead channel")
	func aSilentReaderIsADifferentReport() throws {
		// The distinction the liveness port exists for: half-alive needs a reader
		// restart, gone needs the reader started at all, and reporting one for the
		// other wastes somebody's afternoon.
		let sender = FakeGestureSender()
		sender.failures["go to desktop"] = .scriptingChannelDead
		do {
			_ = try handler.execute(
				context(sender: sender, liveness: FakeReaderLiveness(isRunning: false)),
				request(["go to desktop"]))
			Issue.record("expected the dispatch to fail")
		} catch let error as CommandError {
			#expect(!error.description.contains(ReaderCondition.scriptingChannelDead.rawValue))
			#expect(error.description.contains("is not running at all"))
			// COMMAND-F5, NOT `killall && open`: the recovery a person at the machine
			// actually performs, and the one the 2026-09-02 field report found works
			// when the pair this repo used to print did not.
			#expect(error.description.contains("Command-F5"))
		}
	}

	// ==========================================================================
	// 13.26: THREE CONDITIONS FAIL WITH IDENTICAL ERROR NUMBERS, AND THE MIDDLE
	// ONE WAS A SHIPPED DEFECT.
	// ==========================================================================
	//
	// Measured live on 2026-09-02 with the AppleScript switch OFF: `return
	// commander` fails -1728 and `perform command` fails -1708 -- EXACTLY the pair
	// a wedged reader answers with, which `VoiceOverGestureSender` maps to
	// `scriptingChannelDead`. So the bridge told a blind person to restart their
	// screen reader to repair a switch they had deliberately turned off, and every
	// clause of the sentence was true. Only the PREFERENCE separates the two, and
	// this bridge was already reading it and never consulting it here.

	@Test("with the AppleScript switch OFF, the reader is not blamed and the KEY is named")
	func aSwitchedOffChannelIsNotAWedgedReader() throws {
		let sender = FakeGestureSender()
		sender.failures["go to desktop"] = .scriptingChannelDead
		let scripting = FakeReaderScriptingSetting(setting: .disabled)
		do {
			_ = try handler.execute(
				context(sender: sender, readerScripting: scripting), request(["go to desktop"]))
			Issue.record("expected the dispatch to fail")
		} catch let error as CommandError {
			// THE RECOVERY IT MUST NOT GIVE. A restart repairs nothing here, and
			// following it costs a blind person their screen reader for no reason.
			#expect(!error.description.contains(readerRestartCommand))
			#expect(!error.description.contains(ReaderCondition.scriptingChannelDead.rawValue))
			// What it must say instead: the switch, that the reader is fine, and the
			// route that does work on this machine.
			#expect(error.description.contains("AppleScript"))
			#expect(error.description.contains("running and healthy"))
			#expect(error.description.lowercased().contains("press the key"))
		}
	}

	@Test("an UNREADABLE switch is reported as unreadable, never as switched off")
	func anUnreadableSwitchIsItsOwnAnswer() throws {
		// The same rule the setting's own port makes: "I could not look" is not "it
		// is off", and an agent told the wrong one sends a human to a settings pane
		// that may already be right.
		let sender = FakeGestureSender()
		sender.failures["go to desktop"] = .scriptingChannelDead
		do {
			_ = try handler.execute(
				context(sender: sender, readerScripting: FakeReaderScriptingSetting(setting: .unknown)),
				request(["go to desktop"]))
			Issue.record("expected the dispatch to fail")
		} catch let error as CommandError {
			#expect(error.description.contains("not readable"))
			#expect(!error.description.contains("switched off"))
		}
	}

	@Test("with the switch ON, a dead object model is still reported as one")
	func aGenuinelyDeadChannelIsStillNamed() throws {
		// The control for the two above: this is spec 0041's measured state, it is
		// the one case a restart actually repairs, and 13.26 must not have made it
		// unreportable.
		let sender = FakeGestureSender()
		sender.failures["go to desktop"] = .scriptingChannelDead
		do {
			_ = try handler.execute(
				context(sender: sender, readerScripting: FakeReaderScriptingSetting(setting: .enabled)),
				request(["go to desktop"]))
			Issue.record("expected the dispatch to fail")
		} catch let error as CommandError {
			#expect(error.description.contains(ReaderCondition.scriptingChannelDead.rawValue))
			#expect(error.description.contains(readerRestartCommand))
		}
	}

	@Test("the expert is told it can ASK a human for the switch, and where")
	func theSwitchCanBeRequestedFromAHuman() throws {
		// Marlon, 2026-09-02: "Then the expert can, if they need, request apple
		// script permission, and this has to be given by a human." There is no
		// mechanism to build -- no API sets that switch -- so the affordance is this
		// sentence, at the moment an agent discovers it wants the route.
		let sender = FakeGestureSender()
		sender.failures["go to desktop"] = .scriptingChannelDead
		do {
			_ = try handler.execute(
				context(sender: sender, readerScripting: FakeReaderScriptingSetting(setting: .disabled)),
				request(["go to desktop"]))
			Issue.record("expected the dispatch to fail")
		} catch let error as CommandError {
			#expect(error.description.contains("ask_user"))
			#expect(error.description.contains("VoiceOver Utility > General"))
			#expect(error.description.contains("reconnect"))
		}
	}

	@Test("a reader that is GONE is diagnosed before the switch is even read")
	func aMissingReaderOutranksTheSwitch() throws {
		// Order matters: on a machine with the switch off AND no reader, telling the
		// agent to press a key would be telling it to press keys at nothing.
		let sender = FakeGestureSender()
		sender.failures["go to desktop"] = .scriptingChannelDead
		let scripting = FakeReaderScriptingSetting(setting: .disabled)
		do {
			_ = try handler.execute(
				context(
					sender: sender, liveness: FakeReaderLiveness(isRunning: false),
					readerScripting: scripting),
				request(["go to desktop"]))
			Issue.record("expected the dispatch to fail")
		} catch let error as CommandError {
			#expect(error.description.contains("is not running at all"))
			#expect(scripting.reads == 0)
		}
	}

	@Test("liveness is NOT asked on a healthy run, because every ask is a subprocess")
	func livenessIsNotAskedWhenNothingFailed() throws {
		let liveness = FakeReaderLiveness()
		_ = try handler.execute(
			context(liveness: liveness), request(["go to desktop", "mute sound toggle"]))
		#expect(liveness.asked == 0)
	}

	@Test("liveness is not asked for an UNKNOWN command either -- that is the agent's mistake")
	func livenessIsNotAskedForAnUnknownCommand() throws {
		let sender = FakeGestureSender()
		sender.failures["nope at all"] = .unknownCommand("nope at all")
		let liveness = FakeReaderLiveness()
		_ = try? handler.execute(
			context(sender: sender, liveness: liveness), request(["nope at all"]))
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
			let sender = FakeGestureSender()
			_ = try handler.execute(
				context(mode: mode, sender: sender, announcer: announcer),
				request(["go to desktop"], announce: "moving to the desktop"))
			#expect(announcer.spoken == ["moving to the desktop"])
			#expect(sender.pressed == ["go to desktop"])
		}
	}

	@Test("a warning that could not be spoken PRESSES NOTHING")
	func anUnspeakableWarningStopsEverything() throws {
		// The ordering proof: the warning is the first thing the handler does, so if
		// the human cannot be told what is about to happen to their machine, nothing
		// happens to it.
		let announcer = FakeAnnouncer()
		announcer.fails = true
		let sender = FakeGestureSender()
		do {
			_ = try handler.execute(
				context(mode: .silent, sender: sender, announcer: announcer),
				request(["go to desktop"], announce: "moving to the desktop"))
			Issue.record("expected the gesture to be refused when the human could not be warned")
		} catch let error as CommandError {
			#expect(error.description.contains("could not be warned"))
			#expect(error.description.contains("empty"))
		}
		#expect(sender.pressed.isEmpty)
	}

	@Test("whitespace is not an announcement, so nothing is said and nothing is refused")
	func whitespaceAnnounceIsAbsence() throws {
		let sender = FakeGestureSender()
		_ = try handler.execute(
			context(mode: .silent, sender: sender), request(["go to desktop"], announce: "   "))
		#expect(sender.pressed == ["go to desktop"])
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
			try handler.execute(bare, request(["go to desktop"]))
		}
	}

	// -- `vo`, read from the machine, which is 13.25 ----------------------------

	@Test("`vo+m` GOES TO THE KEY PRESSER, resolved against what the machine says")
	func voReachesTheKeyPresser() throws {
		let keys = FakeKeyPresser()
		let sender = FakeGestureSender()
		let context = context(sender: sender, keys: keys)
		_ = try PressGestureHandler().execute(context, request(["vo+m"]))

		#expect(sender.pressed.isEmpty)
		#expect(
			keys.pressed == [Keystroke(modifiers: [.control, .option], keys: [.character("m")])])
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
		let sender = FakeGestureSender()
		let context = context(
			sender: sender, keys: keys, readerModifier: FakeReaderModifierSetting(.capsLock))
		#expect(throws: CommandError.self) {
			_ = try PressGestureHandler().execute(
				context, request(["go to dock", "command+l", "vo+m"]))
		}
		#expect(sender.pressed.isEmpty)
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
			#expect(failure.description.contains("command name"))
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
		// 13.8's lever as this entry leaves it: a keystroke is a system event
		// whatever spells it, so `vo+m` asks exactly as `command+l` does -- and
		// that is the trade spec 0052 §3.6 states rather than discovers.
		let permissions = FakePermissionBroker(state: .notGranted)
		let context = context(permissions: permissions)
		#expect(throws: CommandError.self) {
			_ = try PressGestureHandler().execute(context, request(["vo+m"]))
		}
		#expect(permissions.requests == [Permission.accessibility])
	}
}
