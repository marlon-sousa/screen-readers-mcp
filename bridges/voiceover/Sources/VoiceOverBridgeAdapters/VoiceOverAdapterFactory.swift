// ROLE: adapter -- IMPLEMENTS the AdapterFactory domain port. THE ONLY PLACE
// THAT KNOWS WHAT A CAPTURE MODE MEANS, because the mode is not known until
// `hello` has been read and this is what `hello` calls.
//
// BUILT BY: Wiring. CALLED BY: the Hello handler, once per session.
//
// IT NO LONGER REFUSES ANYTHING, AND THAT IS 13.6. Until this entry a silent
// session was refused outright, with a named test that had to be deleted by
// whoever made the promise keepable -- because `silent` is not a preference, it
// is a PROMISE ABOUT A HUMAN'S EARS: the reader keeps talking, the human hears
// nothing, and the agent reads what was said. 13.5 could keep the last clause
// and neither of the others, and half a promise is the more dangerous kind:
// capture that works is exactly what would have made a claimed silence look
// plausible.
//
// WHAT MAKES IT KEEPABLE NOW is the marker file this factory builds -- read by
// the capture voice once per utterance, so a lift lands on the very next thing
// VoiceOver says -- and hard invariant 3 in its macOS form, which is not a
// teardown path at all but an EXPIRY: see SilenceControl and
// MarkerFileSilenceControl for why a `finally` was never enough here.
//
// THE REFUSAL MOVED RATHER THAN VANISHING. A mode is still an instruction a
// bridge may be unable to carry out, and `silent` now fails at the HANDSHAKE
// when the reader edge cannot deliver it -- see the Hello handler, which asks
// the provider lifecycle and refuses by NAMED CONDITION with its recovery. That
// is the same argument in the place that can now actually answer the question:
// this factory builds collaborators, and only the handshake knows whether the
// machine is in a state where they mean anything.
//
// BOTH MODES GET THE SAME COLLABORATORS, and the symmetry is the route's:
// capture is identical either way, the marker channel carries the user's own
// voice in both (Rule 0), the provider lifecycle answers the same questions, and
// a command is dispatched to the reader the same way whether or not the human
// can hear the result. Only what the handshake ASKS for differs. The human
// channel added at 13.10 is the sharpest instance of that symmetry: the
// announcer speaks OUTSIDE VoiceOver, so it works identically in a mode where the
// reader is mute -- which is the mode it exists for.
//
// WHAT IS NOT DECIDED HERE: where any of it lives. The capture path, the marker
// path and the lifecycle are values Wiring resolves, so this class stays the
// place that knows what a MODE means and not the place that knows where files
// are.

import ScreenReaderWire
import VoiceOverBridgeDomain

public final class VoiceOverAdapterFactory: AdapterFactory {
	private let capturePath: String
	private let markerPath: String
	private let lifecycle: any ProviderLifecycle
	private let scripts: any AppleScriptRunner
	private let permissions: any PermissionBroker
	private let poster: any EventPoster
	private let layout: any KeyboardLayout
	private let tree: any AccessibilityTree
	private let frontmost: any FrontmostApplication
	private let trust: any AccessibilityTrust
	private let announcer: any Announcer
	private let prompter: any UserPrompter

	/// `capturePath` is where the capture voice appends its feed; `markerPath` is
	/// where it reads what the bridge is asking of it. Passed in with no defaults,
	/// deliberately: a default here would be an environment read hidden in a
	/// signature, and Wiring is the one place in this bridge that reads the
	/// environment.
	///
	/// The lifecycle is passed in rather than built here because it is the one
	/// collaborator that is NOT per-session: it describes the machine, the same
	/// answer for every session, and building one per handshake would run
	/// `pluginkit` for no reason.
	/// The script runner is passed in for the same reason as the lifecycle: it is
	/// not per-session either. It holds no state at all -- every call is a fresh
	/// subprocess -- so one serves every session, and building one per handshake
	/// would be construction for its own sake.
	///
	/// THE KEYBOARD LAYOUT IS PASSED IN FOR THE DETERMINISM REASON, not the safety
	/// one: reading it changes nothing and asks for nothing, but its answer is
	/// whatever layout the developer happens to be typing on -- so a test built on
	/// the real one would assert against a Brazilian keyboard here and an American
	/// one in CI. It is shared across sessions because its reverse map costs 256
	/// system calls to build and describes the machine rather than the session.
	///
	/// THE PERMISSION BROKER AND THE EVENT POSTER ARE PASSED IN FOR A STRONGER
	/// REASON THAN ANY OF THOSE: no test may ever build the real ones. The real
	/// broker's `request` raises a system consent dialog and leaves this process
	/// on a list that stays granted afterwards, and the real poster types into
	/// whatever window the developer has in front of them. Injecting both is what
	/// lets `Tests/Fakes/Support/ReaderEdge.swift` guarantee that a test cannot
	/// reach either by accident -- the same guarantee it already gives for the
	/// provider lifecycle, which writes the voice VoiceOver speaks with.
	///
	/// THE HUMAN CHANNEL IS INJECTED FOR THE SAFETY REASON AGAIN (13.10): the real
	/// announcer SPEAKS on the developer's machine and the real prompter opens a
	/// window on their screen and takes their focus. Both are per-process and hold
	/// no session state, so the set carries the same two objects for every session
	/// -- and `ReaderEdge.swift` hands every test fakes for them, exactly as it
	/// does for the poster and the broker.
	///
	/// THE FOCUS TRIO IS INJECTED FOR A THIRD REASON AGAIN: not safety, but
	/// DETERMINISM. Reading the accessibility tree and asking who is frontmost
	/// change nothing on the machine -- but their answers are whatever window the
	/// developer had in front of them, so an integration scenario built on the
	/// real ones would assert against the developer's desktop. All three are
	/// per-process and stateless, and `trust` is answered by the very object that
	/// answers `permissions`: one leaf, two interfaces at two layers.
	public init(
		capturePath: String,
		markerPath: String,
		lifecycle: any ProviderLifecycle,
		scripts: any AppleScriptRunner,
		permissions: any PermissionBroker,
		poster: any EventPoster,
		layout: any KeyboardLayout,
		tree: any AccessibilityTree,
		frontmost: any FrontmostApplication,
		trust: any AccessibilityTrust,
		announcer: any Announcer,
		prompter: any UserPrompter
	) {
		self.capturePath = capturePath
		self.markerPath = markerPath
		self.lifecycle = lifecycle
		self.scripts = scripts
		self.permissions = permissions
		self.poster = poster
		self.layout = layout
		self.tree = tree
		self.frontmost = frontmost
		self.trust = trust
		self.announcer = announcer
		self.prompter = prompter
	}

	public func build(mode: CaptureMode) throws -> AdapterSet {
		// A source and a silence control PER SESSION, not per process: a tailer
		// shared between two sessions would deliver each utterance to whichever
		// buffer read first, and a marker shared between them would let one
		// session's teardown lift the other's silence.
		AdapterSet(
			mode: mode,
			speechSource: ContainerFileSpeechSource(tailer: FileLineTailer(path: capturePath)),
			silenceControl: MarkerFileSilenceControl(path: markerPath),
			providerLifecycle: lifecycle,
			// STATELESS, so these two are built per session at no cost and shared
			// with nothing: each is a thin wrapper over the one script runner, and
			// the runner is what actually holds nothing.
			gestureSender: VoiceOverGestureSender(runner: scripts),
			readerLiveness: VoiceOverLiveness(runner: scripts),
			textTyper: AccessibilityTextTyper(poster: poster),
			// STATELESS TOO, and built per session over the two shared seams beneath
			// it. THE LAYOUT IS SHARED AND THE PRESSER IS NOT, which is the ordinary
			// split in this file: the layout holds a cache worth keeping across
			// sessions, and the presser holds nothing at all.
			keyPresser: CGKeystrokePresser(layout: layout, poster: poster),
			// SHARED, LIKE THE LIFECYCLE, because it describes this PROCESS's
			// standing with the system rather than anything about a session -- and
			// because building one here would be a second place in the bridge that
			// touches the permission machinery, when the point of 13.8 is that only
			// a command handler ever does.
			permissions: permissions,
			// STATELESS TOO, so one is built per session over three shared seams.
			// IT IS HANDED `trust` AND NOT `permissions`, and that is the shape 13.9
			// settled: focus READS whether the grant is held, to pick a route, and
			// must never be able to ask for it. Handing it the domain port would put
			// `request` within reach of the one command whose whole promise is that
			// it does not.
			focusInspector: VoiceOverFocusInspector(
				tree: tree, scripts: scripts, frontmost: frontmost, trust: trust
			),
			// SHARED, LIKE THE LIFECYCLE AND THE BROKER, and for the plainest of the
			// three reasons: one process has one loudspeaker and one screen. Two
			// announcers would be two synthesizers talking over each other, and two
			// prompters would each hold half the tickets.
			announcer: announcer,
			userPrompter: prompter
		)
	}
}
