// Mirrors Sources/VoiceOverBridgeDomain/Controllers/Commands/TypeText.swift.
//
// ONE PROPERTY CARRIES MOST OF THIS FILE, and it is 13.8's whole claim: THE
// ACCESSIBILITY GRANT IS ASKED FOR ONLY BY A COMMAND THAT IS ABOUT TO POST A
// SYSTEM EVENT -- this one, and since 13.17 a KEYSTROKE `pressGesture`, which
// asserts its half in `PressGestureTests`. A test can only check that with a
// broker that counts requests separately from status reads, which is what
// FakePermissionBroker is for -- and none of these tests touches the real grant,
// because the real one raises a system dialog and changes the developer's
// machine permanently.
//
// The second property is the one protocol.md §5 puts on this command: THE TEXT
// IS NEVER LOGGED AND `typed` IS A LENGTH. Typing is exactly how a secret is
// entered, so both the result and the transcript carry a count.

import Fakes
import ScreenReaderWire
import Testing

@testable import VoiceOverBridgeDomain

@Suite("TypeText")
struct TypeTextTests {
	private let handler = TypeTextHandler()

	/// A session with a reader edge of doubles, in whichever mode the test wants.
	private func context(
		mode: CaptureMode = .live,
		typer: FakeTextTyper = FakeTextTyper(),
		permissions: FakePermissionBroker = FakePermissionBroker(),
		transcript: FakeTranscript = FakeTranscript(),
		announcer: FakeAnnouncer = FakeAnnouncer()
	) -> SessionContext {
		let context = SessionContext(
			clock: FakeClock(), transcript: transcript, attended: true, close: { _ in })
		context.mode = mode
		context.adapters = fakeAdapterSet(
			mode: mode, textTyper: typer, permissions: permissions, announcer: announcer)
		context.speech = SpeechBuffer(clock: FakeClock())
		return context
	}

	private func request(_ text: String, graceMs: Int = 0, announce: String = "") -> Request {
		Request(
			id: 1, cmd: Command.typeText.rawValue,
			params: [
				"text": .string(text),
				"graceMs": .int(graceMs),
				"announce": .string(announce),
			])
	}

	// -- the injection ---------------------------------------------------------

	@Test("the text reaches the typer WHOLE and untouched, control characters included")
	func theTextIsHandedOverUnchanged() throws {
		// protocol.md §5: `text` is opaque content, routed without interpretation.
		// A newline is a newline and not Return, and nothing here submits anything.
		let typer = FakeTextTyper()
		_ = try handler.execute(context(typer: typer), request("one\ntwo\ttab"))
		#expect(typer.typed == ["one\ntwo\ttab"])
	}

	@Test("`typed` counts UNICODE SCALARS, which is what the other two bindings count")
	func typedIsAScalarCount() throws {
		// The field means the same number in all three bindings or it means
		// nothing: lane 1 reports Python's `len` and the server's conformance
		// scenario asserts a rune count. Swift's `String.count` would count
		// GRAPHEME CLUSTERS and disagree silently on a decomposed character.
		let decomposed = "e\u{0301}"  // "e" + combining acute -- one cluster, two scalars
		let value = try handler.execute(context(), request(decomposed))
		#expect(try #require(value as? TypeResult).typed == 2)
		#expect(decomposed.count == 1, "the trap this test exists for")
	}

	@Test("a typer that fails is reported as an error, and the session survives it")
	func aFailedInjectionIsReported() throws {
		let typer = FakeTextTyper()
		typer.failure = TypingError("the system would not create a keyboard event")
		do {
			_ = try handler.execute(context(typer: typer), request("hello"))
			Issue.record("expected the injection to fail")
		} catch let error as CommandError {
			#expect(error.description.contains("keyboard event"))
		}
	}

	// -- the lazy grant, which is what this entry is FOR ------------------------

	@Test("a session that already holds the grant asks for NOTHING")
	func anExistingGrantIsNotRequested() throws {
		let permissions = FakePermissionBroker(state: .granted)
		_ = try handler.execute(context(permissions: permissions), request("hello"))
		#expect(permissions.requests.isEmpty)
		#expect(permissions.statusReads == [.accessibility])
	}

	@Test("the grant is REQUESTED on a typeText that does not already have it")
	func theGrantIsRequestedWhenTyping() throws {
		// One of the two places in the bridge that may ask. Everything else -- the
		// handshake, a COMMAND-NAME gesture, a speech read, a focus read -- goes past
		// without a request, which is what makes "this session was never asked for
		// Accessibility" a checkable statement rather than an intention.
		let permissions = FakePermissionBroker(state: .notGranted)
		let typer = FakeTextTyper()
		#expect(throws: CommandError.self) {
			try handler.execute(context(typer: typer, permissions: permissions), request("hello"))
		}
		#expect(permissions.requests == [.accessibility])
		// And nothing was typed, because nothing could have been: an event posted
		// without the grant is dropped with no error anywhere, so a handler that
		// typed anyway would report a success that did nothing.
		#expect(typer.typed.isEmpty)
	}

	@Test("a request the human grants goes straight on to type")
	func aGrantedRequestProceeds() throws {
		// What it looks like when somebody is at the machine and says yes.
		let permissions = FakePermissionBroker(state: .notGranted)
		permissions.onRequest = { permissions.state = .granted }
		let typer = FakeTextTyper()
		_ = try handler.execute(context(typer: typer, permissions: permissions), request("hello"))
		#expect(permissions.requests == [.accessibility])
		#expect(typer.typed == ["hello"])
	}

	@Test("a request that is not granted says NOT YET, names the recovery, and offers gestures")
	func aRefusedRequestSaysWhatToDo() throws {
		// macOS raises a dialog that sends the human to System Settings, and they
		// act on it long after the call returned -- so reporting a REFUSAL would
		// send an agent looking for a decision nobody has made.
		let permissions = FakePermissionBroker(state: .notGranted)
		do {
			_ = try handler.execute(context(permissions: permissions), request("hello"))
			Issue.record("expected typing to be refused without the grant")
		} catch let error as CommandError {
			#expect(error.description.contains(Permission.accessibility.rawValue))
			#expect(error.description.contains("System Settings"))
			// The SSH wrinkle, because an agent driving this machine remotely will
			// otherwise be looking for an entry named after the app.
			#expect(error.description.contains("sshd-keygen-wrapper"))
			// And the half of input that still works without any grant at all.
			#expect(error.description.contains("pressGesture"))
			#expect(error.description.contains("nothing was typed"))
		}
	}

	// -- the text is never logged ----------------------------------------------

	@Test("the transcript records a LENGTH, before the injection, and never the text")
	func theTranscriptRecordsALengthOnly() throws {
		// A transcript is a file a human reads afterwards, so a password in it is a
		// password on disk. Recorded BEFORE the injection for the reason `gesture`
		// is: the call anyone is looking for is the one that went wrong.
		let transcript = FakeTranscript()
		let typer = FakeTextTyper()
		typer.failure = TypingError("boom")
		_ = try? handler.execute(
			context(typer: typer, transcript: transcript), request("hunter2"))
		#expect(transcript.typedLengths == [7])
		#expect(!transcript.notes.contains { $0.contains("hunter2") })
	}

	// -- the grace window ------------------------------------------------------

	@Test("the window spans what was said while typing, and the entries carry their indices")
	func theWindowSpansTheTyping() throws {
		let typer = FakeTextTyper()
		let ctx = context(typer: typer)
		let buffer = try #require(ctx.speech)
		typer.onType = { _ in buffer.append(CapturedUtterance(text: "h")) }
		let value = try handler.execute(ctx, request("h", graceMs: 50))
		let result = try #require(value as? TypeResult)
		#expect(result.speechFrom == 1)
		#expect(result.speechTo == 2)
		#expect(result.speech.map(\.index) == [1])
	}

	@Test("an empty window is a FACT about an instant, not a claim that nothing was said")
	func anEmptyWindowIsNotAClaim() throws {
		// protocol.md §7.3: a result says what had arrived by a stated instant and
		// where to resume, so there is no `complete` flag to compute.
		let value = try handler.execute(context(), request("hello"))
		let result = try #require(value as? TypeResult)
		#expect(result.speech.isEmpty)
		#expect(result.speechFrom == result.speechTo)
	}

	@Test("`graceMs` DEFAULTS TO 0 here, where a gesture's defaults to 100")
	func theDefaultGraceIsZero() throws {
		// Not an oversight: with "speak typed characters" on, typing emits one
		// utterance per character and none of them is worth waiting for. The
		// default lives in the wire binding, so this asserts the shape a request
		// that omits the field decodes to.
		let bare = Request(id: 1, cmd: Command.typeText.rawValue, params: ["text": .string("hi")])
		#expect(try bare.params(as: TypeParams.self).graceMs == 0)
		#expect(PressGestureParams(gestures: []).graceMs == 100)
		// And the handler honours it without waiting on a clock nothing advances.
		_ = try handler.execute(context(), bare)
	}

	@Test("`state` is never sampled: this bridge announces no `state` capability")
	func stateIsAlwaysNil() throws {
		let value = try handler.execute(context(), request("hello"))
		#expect(try #require(value as? TypeResult).state == nil)
	}

	// -- announce, on exactly the terms pressGesture uses -----------------------

	@Test("the announce IS SPOKEN, in BOTH modes -- 13.10 made that keepable")
	func announceIsSpokenInEitherMode() throws {
		// Until the human channel existed this was REFUSED in a silent session and
		// merely noted in a live one, because there was nothing to say it on. The
		// Announcer speaks outside VoiceOver, so both modes now warn the person
		// before their window is typed into.
		for mode in [CaptureMode.silent, .live] {
			let announcer = FakeAnnouncer()
			let typer = FakeTextTyper()
			_ = try handler.execute(
				context(mode: mode, typer: typer, announcer: announcer),
				request("hello", announce: "about to type"))
			#expect(announcer.spoken == ["about to type"])
			#expect(typer.typed == ["hello"])
		}
	}

	@Test("a warning that could not be spoken TYPES NOTHING and asks for no grant")
	func anUnspeakableWarningStopsEverything() throws {
		// The ordering proof, and the reason `HumanWarning.honour` is the first line
		// of the handler: if the human cannot be told what is about to happen to
		// their machine, nothing happens to it -- and no consent dialog is left
		// behind either, because the warning is honoured before the grant is asked
		// for.
		let announcer = FakeAnnouncer()
		announcer.fails = true
		let typer = FakeTextTyper()
		let permissions = FakePermissionBroker()
		#expect(throws: CommandError.self) {
			try handler.execute(
				context(mode: .silent, typer: typer, permissions: permissions, announcer: announcer),
				request("hello", announce: "about to type"))
		}
		#expect(typer.typed.isEmpty)
		#expect(permissions.requests.isEmpty)
		#expect(permissions.statusReads.isEmpty)
	}

	// -- the flags the dispatch loop reads -------------------------------------

	@Test("it declares that it MOVES the user's machine")
	func itMutatesTheReader() {
		#expect(handler.mutatesReader)
		#expect(!handler.availableBeforeHello)
		#expect(handler.resetsInactivity)
	}

	@Test("typed before `hello`, it says so rather than crashing")
	func withoutAReaderEdgeItSaysSo() throws {
		let bare = SessionContext(
			clock: FakeClock(), transcript: FakeTranscript(), attended: true, close: { _ in })
		#expect(throws: CommandError.self) {
			try handler.execute(bare, request("hello"))
		}
	}
}
