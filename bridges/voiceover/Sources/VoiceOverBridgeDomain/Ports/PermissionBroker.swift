// ROLE: port -- what this bridge is allowed to do to the machine, and the one place it may ask for more.
// IMPLEMENTED BY: TCCPermissionBroker, over `AXIsProcessTrusted`; FakePermissionBroker.
// BUILT BY: Wiring, once per process.
// USED BY: the TypeText and PressGesture controllers (`request`), and ReaderEdgeSetup and the launcher (`status`).
// Only those two handlers may call `request`, never Wiring or the handshake, so connecting never raises a consent dialog.
public enum Permission: String, Equatable, Sendable, CaseIterable {
	case accessibility

	public var summary: String {
		switch self {
		case .accessibility:
			return "this bridge is not allowed to synthesize keyboard input on this machine"
		}
	}

	public var recovery: String {
		switch self {
		case .accessibility:
			return
				"grant it under System Settings > Privacy & Security > Accessibility and send the "
				+ "command again. If this bridge was started over SSH, the entry to allow is named "
				+ "/usr/libexec/sshd-keygen-wrapper rather than the app -- macOS attributes the "
				+ "request to the SSH session, and allowing it allows every SSH session on the machine"
		}
	}

	public var described: String {
		"\(rawValue): \(summary). Recovery: \(recovery)."
	}
}

public enum PermissionState: String, Equatable, Sendable {
	case granted
	case notGranted
}

public protocol PermissionBroker: AnyObject {
	/// Asks for nothing and shows no dialog, so it is safe on any path.
	func status(of permission: Permission) -> PermissionState

	/// `notGranted` here means not yet, never refused: the human acts on the dialog after this returns.
	func request(_ permission: Permission) -> PermissionState
}
