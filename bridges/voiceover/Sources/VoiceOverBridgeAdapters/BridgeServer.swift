// ROLE: an adapter-layer CONTROLLER -- the orchestrator of the connection edge.
//
// IT IS NOT IN THE DOMAIN, and the test for that is its collaborators: a
// Listener and a Transport, both adapter seams the domain must never see. So it
// lives out here with them -- the same doctrine as JsonLinesChannel, one level
// further out.
//
// HOLDS: a Listener, and a factory that turns an accepted Transport into a
// Session. It owns the server thread.
// BUILT BY: Wiring. USED BY: the launcher today and the control dialog when it
// lands, which is why start, stop and an observable status are the whole public
// surface.
//
// ONE SESSION AT A TIME: accept, build, run it inline on the server thread, go
// back to accepting. It touches nothing a session owns -- the promise that a
// teardown restores what the session changed is the Session's, kept in its own
// `defer`.
//
// NO SESSION FAULT MAY BREAK THE SERVER. That is lane 1's crashed-client lesson
// carried over rather than re-learned: a client that dies mid-command must cost
// its own session and nothing else, so the accept loop catches around the whole
// of one session and goes back to accepting.
//
// THE JOIN IS BOUNDED, because the caller may be the main thread -- a dialog's
// Stop button, or the app terminating. Teardown is cooperative, so a handler
// that blocks delays the thread's exit; losing a daemon thread whose listener is
// already closed is the lesser harm next to an application that has stopped
// responding.

import Foundation
import VoiceOverBridgeDomain

/// What Wiring supplies: "a Transport becomes a Session". Everything else a
/// session needs is bound in the closure, so this class never learns what a
/// session is made of.
public typealias SessionFactory = (any Transport) -> Session

public final class BridgeServer {
	/// How long `stop()` waits for the server thread.
	static let stopTimeout: Double = 5.0

	private var listener: any Listener
	private let sessionFactory: SessionFactory
	private let eventBus: (any EventBus)?

	/// One lock guards every field the server thread and a caller thread both
	/// touch: the status pair, the live session, the stopping flag.
	private let lock = NSLock()
	private var state: ServerState = .stopped
	private var endpoint: String?
	private var activeSession: Session?
	private var stopping = false
	private var finished: DispatchSemaphore?

	public init(
		listener: any Listener,
		sessionFactory: @escaping SessionFactory,
		eventBus: (any EventBus)? = nil
	) {
		self.listener = listener
		self.sessionFactory = sessionFactory
		self.eventBus = eventBus
	}

	// -- public API ----------------------------------------------------------

	public var status: ServerStatus {
		lock.lock()
		defer { lock.unlock() }
		return ServerStatus(state: state, endpoint: endpoint)
	}

	/// Bind, report listening, and spawn the accept loop. A no-op if already
	/// running.
	///
	/// BINDING HAPPENS ON THE CALLER'S THREAD, deliberately: a bind failure -- a
	/// port in use, an unwritable directory -- is thrown to whoever asked for the
	/// bridge rather than dying quietly inside a thread nobody is watching.
	public func start(listener replacement: (any Listener)? = nil) throws {
		lock.lock()
		if state != .stopped {
			lock.unlock()
			return
		}
		if let replacement {
			listener.close()
			listener = replacement
		}
		do {
			try listener.open()
		} catch {
			lock.unlock()
			throw error
		}
		endpoint = listener.endpoint
		state = .listening
		stopping = false
		let done = DispatchSemaphore(value: 0)
		finished = done
		lock.unlock()

		let thread = Thread { [weak self] in
			self?.serve()
			done.signal()
		}
		thread.name = "voiceoverMcpBridge-server"
		thread.start()
		notify()
	}

	/// Stop accepting and end any live session. Idempotent, and blocking until
	/// the server thread has finished or the bound wait has elapsed.
	///
	/// MUST NOT BE CALLED FROM THE SERVER THREAD: it waits on that thread.
	public func stop() {
		lock.lock()
		let session = activeSession
		let done = finished
		stopping = true
		lock.unlock()

		session?.requestTeardown(.external)
		listener.close()
		if let done {
			_ = done.wait(timeout: .now() + BridgeServer.stopTimeout)
		}

		lock.lock()
		state = .stopped
		endpoint = nil
		activeSession = nil
		stopping = false
		finished = nil
		lock.unlock()
		notify()
	}

	/// The live session's context, or nil. Read under the lock like every other
	/// accessor here, because the caller is another thread and the writer is the
	/// accept loop.
	public func currentSessionContext() -> SessionContext? {
		lock.lock()
		let session = activeSession
		lock.unlock()
		return session?.sessionContext
	}

	// -- the accept loop (runs on the server thread) -------------------------

	private func serve() {
		while !isStopping() {
			let transport: any Transport
			do {
				transport = try listener.accept()
			} catch is PollTimeout {
				continue // idle poll; loop back and re-check the stop flag
			} catch is ListenerClosed {
				break // stop() closed the listener
			} catch {
				break // an unexpected listener fault: stop, do not spin
			}
			runSession(over: transport)
		}
		// An abnormal exit -- a listener fault rather than stop() -- still has to
		// leave an honest status and release the endpoint. The stop() path already
		// owns both, so this only acts when it was not stop() that got us here.
		if !isStopping() {
			listener.close()
			lock.lock()
			state = .stopped
			endpoint = nil
			activeSession = nil
			lock.unlock()
			notify()
		}
	}

	private func runSession(over transport: any Transport) {
		let session = sessionFactory(transport)
		lock.lock()
		activeSession = session
		state = .sessionActive
		let stoppingNow = stopping
		lock.unlock()
		notify()

		// stop() may have raced in before the session was registered; if so it saw
		// nothing to tear down, so we do it here and run() returns at once.
		if stoppingNow {
			session.requestTeardown(.external)
		}
		session.run()

		lock.lock()
		activeSession = nil
		if !stopping {
			state = .listening
		}
		lock.unlock()
		// Only announce the return to listening; the stop() path announces STOPPED
		// itself, and announcing both would report a state that lasted no time.
		if !isStopping() {
			notify()
		}
	}

	private func isStopping() -> Bool {
		lock.lock()
		defer { lock.unlock() }
		return stopping
	}

	private func notify() {
		eventBus?.emit(.serverStatus(status))
	}
}
