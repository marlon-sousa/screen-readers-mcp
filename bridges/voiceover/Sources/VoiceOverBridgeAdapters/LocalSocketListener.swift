// ROLE: adapter implementing the Listener seam on the local endpoint, holding every obligation the wire protocol places on a POSIX listener.
// BUILT BY: Wiring, when the configured connection mode is the local endpoint.
// USED BY: BridgeServer, through the seam.

import VoiceOverBridgeDomain

public final class LocalSocketListener: Listener {
	private let name: String
	private let dirs: LocalSocketDirs
	private let binder: any LocalSocketBinder
	private var path: String?
	private var closed = false

	public var endpoint: String { path ?? name }

	public init(name: String, dirs: LocalSocketDirs, binder: any LocalSocketBinder) {
		self.name = name
		self.dirs = dirs
		self.binder = binder
	}

	public func open() throws {
		let socketPath = try LocalSocketPath.path(for: name, in: dirs)
		// Mode 0700 is what limits the endpoint to this user; skipped for an endpoint given as a path, whose directory the user chose.
		if LocalSocketPath.isBareName(name) {
			try binder.createDirectory(at: LocalSocketPath.directory(in: dirs), mode: 0o700)
		}
		// Unlink before binding, never as recovery from EADDRINUSE, which would unlink a socket another bridge is listening on.
		binder.removeFile(at: socketPath)
		try binder.bind(to: socketPath)
		path = socketPath
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
			// close() from another thread fails a blocked accept; that is the end-of-life signal, not an error.
			if closed {
				throw ListenerClosed()
			}
			throw error
		}
	}

	public func close() {
		closed = true
		binder.close()
		// Removed after the socket closes, so nothing can connect to a path already gone.
		if let path {
			binder.removeFile(at: path)
		}
	}
}
