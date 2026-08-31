// ROLE: controller -- `getFocusInfo`: answer "where am I".
//
// BUILT BY: Registry. DRIVES: the FocusInspector port, and nothing else.
//
// `mutatesReader` STAYS FALSE. Reading focus moves nothing on the user's
// machine, so an observe-only session (spec 0017) is welcome to it -- which is
// most of the point of the command: it is how an agent checks what a gesture
// did without pressing anything else.
//
// IT NEVER REQUESTS A PERMISSION, AND THIS IS THE ENTRY'S ONE STANDING CLAIM.
// The Accessibility grant is asked for from exactly one place in this bridge,
// the TypeText controller, on a `typeText` (13.8). Focus answers RICHER when
// that grant is already held and thinner when it is not, and the difference is
// decided inside the adapter by a read that shows no dialog -- so a session that
// only presses commands, reads speech and asks where it is never triggers a
// request. Adding a broker call here would spend the lane's one design lever;
// `Tests/Integration/SessionRoundTripTests.swift` asserts that nobody has.
//
// THE SHAPE HAS NOWHERE TO SAY WHICH ROUTE ANSWERED, and that is the wire's
// (protocol.md §5), not an omission here: an agent reading an empty `role` and
// no `states` cannot tell "this bridge has no Accessibility grant" from "the
// element has none". the control dialog will draw the permission row a human reads, and
// 13.11's guidance document is where an agent is told. `FocusInfoResult`'s own
// header carries the same warning.
//
// AND `state` STAYS OUT ENTIRELY. `getState` was amended off this entry on
// 2026-08-29: VoiceOver's 45 toggles are richly drivable and almost none is
// readable, so this bridge announces no `state` capability and answers focus
// with focus (spec 0046 part 2).

import ScreenReaderWire

public final class GetFocusInfoHandler: CommandHandler {
	public init() {}

	public func execute(_ context: SessionContext, _ request: Request) throws -> any Encodable {
		let adapters = try readerEdge(context)
		let focus: FocusSnapshot
		do {
			focus = try adapters.focusInspector.focusInfo()
		} catch let failure as FocusError {
			throw CommandError("the focus could not be read: \(failure.description)")
		}
		return FocusInfoResult(
			name: focus.name,
			role: focus.role,
			states: focus.states,
			// PRESENT AND NULLABLE, both of them: the result type encodes the keys
			// by hand so that "no value" travels as `null` rather than as a missing
			// field. Passing the snapshot's optionals straight through is what makes
			// that distinction survive from the reader edge to the wire.
			value: focus.value,
			appModule: focus.appModule
		)
	}

	private func readerEdge(_ context: SessionContext) throws -> AdapterSet {
		guard let adapters = context.adapters else {
			throw CommandError("focus was read before `hello` built the reader edge")
		}
		return adapters
	}
}
