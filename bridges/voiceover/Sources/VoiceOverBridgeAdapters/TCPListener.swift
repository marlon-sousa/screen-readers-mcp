// ROLE: adapter -- IMPLEMENTS the Listener seam over loopback TCP: the
// alternative the control dialog selects when a socket file is awkward.
//
// DEPENDS ON: the LoopbackBinder seam. BUILT BY: Wiring. USED BY: BridgeServer.
//
// LOOPBACK ONLY, AND IT IS NOT A PARAMETER -- Decided (spec 0007, and
// protocol.md §1 for every bridge). Remote TCP is remote keystroke injection and
// remote config writes on a machine somebody depends on, and it is deferred
// behind its own security entry. So the host is a constant in this file: an
// address that could be passed in is an address that will one day be passed in.
//
// THE ONE DECISION IS THAT CONSTANT, plus reporting the port actually bound --
// which differs from the port asked for whenever the caller asked for 0, and a
// test that wants a free port asks for exactly that.

public final class TCPListener: Listener {
	/// The only address this bridge will ever bind. See the header.
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
