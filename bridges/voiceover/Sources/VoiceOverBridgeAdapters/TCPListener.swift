// ROLE: adapter implementing the Listener seam over loopback TCP.
// BUILT BY: Wiring. USED BY: BridgeServer.
// Loopback only, and deliberately not a parameter: remote TCP would be remote keystroke injection on a machine somebody depends on.
public final class TCPListener: Listener {
	public static let loopback = "127.0.0.1"

	private let port: Int
	private let binder: any LoopbackBinder
	private var bound: Int?
	private var closed = false

	public var endpoint: String { "\(TCPListener.loopback):\(bound ?? port)" }

	public init(port: Int, binder: any LoopbackBinder) {
		self.port = port
		self.binder = binder
	}

	public func open() throws {
		bound = try binder.bind(host: TCPListener.loopback, port: port)
		closed = false
	}

	public func accept() throws -> any Transport {
		if closed {
			throw ListenerClosed()
		}
		do {
			return try binder.accept()
		} catch is PollTimeout {
			throw PollTimeout()
		} catch {
			if closed {
				throw ListenerClosed()
			}
			throw error
		}
	}

	public func close() {
		closed = true
		binder.close()
	}
}
