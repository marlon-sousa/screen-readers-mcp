// ROLE: controller -- `getFocusInfo`: answer "where am I".
// BUILT BY: Registry. DRIVES: the FocusInspector port, and nothing else.
// It never requests a permission; the adapter decides how rich an answer to give from a read
// that shows no dialog.

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
