// ROLE: adapter -- IMPLEMENTS the Listener seam on the local endpoint, and holds
// EVERY OBLIGATION protocol.md §1 places on a POSIX listener.
//
// DEPENDS ON: the LocalSocketBinder seam, never on the socket API, which is what
// makes those obligations assertions rather than comments -- its test drives a
// fake binder and reads back the calls in order.
// BUILT BY: Wiring, when the configured connection mode is the local endpoint.
// USED BY: BridgeServer, through the seam.
//
// THE THREE OBLIGATIONS, AND WHY EACH IS A DECISION RATHER THAN A CALL:
//  1. CREATE THE DIRECTORY MODE 0700. That permission is where the endpoint's
//     "only this user" property comes from -- the whole security argument for
//     the local endpoint, in one number. A socket in a world-writable directory
//     is a bridge anybody on the machine can drive.
//  2. UNLINK BEFORE BINDING. A socket file outlives the process that made it, so
//     without this a bridge cannot restart: bind answers "address already in
//     use" about a socket nothing is listening on.
//  3. UNLINK ON THE WAY OUT, best effort. A file left behind reads to a dialing
//     server as "listening", and the dial then fails; unlinking keeps that to a
//     crash rather than a routine outcome.
//
// THE PATH IS DERIVED IN THE DOMAIN, NOT HERE. LocalSocketPath computes it from
// values the caller read, because the server computes the same path from the
// same published rule and the two must agree exactly or never meet.

import VoiceOverBridgeDomain

public final class LocalSocketListener: Listener {
	private let name: String
	private let dirs: LocalSocketDirs
	private let binder: any LocalSocketBinder
	private var path: String?
	private var closed = false

	public var endpoint: String { path ?? name }

	/// `name` is the endpoint's bare NAME, and `dirs` is the environment the
	/// caller read. Neither is looked up here: this class must be constructible
	/// in a test with no home directory and no environment at all.
	public init(name: String, dirs: LocalSocketDirs, binder: any LocalSocketBinder) {
		self.name = name
		self.dirs = dirs
		self.binder = binder
	}

	public func open() throws {
		let socketPath = try LocalSocketPath.path(for: name, in: dirs)
		// Obligation 1. Skipped for an endpoint written out as a path, which is
		// the deliberate override spec 0044 keeps: a user who named a directory
		// has said where it goes, and creating a parent they did not ask for
		// would be this adapter deciding something the override took away from it.
		if LocalSocketPath.isBareName(name) {
			try binder.createDirectory(at: LocalSocketPath.directory(in: dirs), mode: 0o700)
		}
		// Obligation 2, and it happens BEFORE the bind rather than after a failed
		// one: recovering from EADDRINUSE by unlinking and retrying would also
		// unlink a socket another bridge is listening on right now.
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
			// close() from another thread makes a blocked accept fail; from here
			// that is not an error but the seam's own end-of-life signal.
			if closed {
				throw ListenerClosed()
			}
			throw error
		}
	}

	public func close() {
		closed = true
		binder.close()
		// Obligation 3. After the socket is closed, so nothing can connect to a
		// path that has already been removed, and unconditionally, because this
		// is the path that runs when the bridge is being shut down properly.
		if let path {
			binder.removeFile(at: path)
		}
	}
}
