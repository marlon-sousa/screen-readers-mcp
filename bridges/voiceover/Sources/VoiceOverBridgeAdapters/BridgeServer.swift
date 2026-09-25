// ROLE: adapter-layer controller of the connection edge, owning the server thread.
// BUILT BY: Wiring.
// USED BY: the BridgeListener launcher.
// One session at a time, run inline on the server thread.
// No session fault may break the server: the accept loop catches around each whole session.
// The wait in `stop()` is bounded, because the caller may be the main thread.

import Foundation
import VoiceOverBridgeDomain

public typealias SessionFactory = (any Transport) -> Session

public final class BridgeServer {
	static let stopTimeout: Double = 5.0

	private var listener: any Listener
	private let sessionFactory: SessionFactory
	private let eventBus: (any EventBus)?

	/// Guards every field the server thread and a caller thread both touch.
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


	public var status: ServerStatus {
		lock.lock()
		defer { lock.unlock() }
		return ServerStatus(state: state, endpoint: endpoint)
	}

	/// Binds on the caller's thread, so a bind failure is thrown to the caller.
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

	/// Must not be called from the server thread: it waits on that thread.
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

	public func currentSessionContext() -> SessionContext? {
		lock.lock()
		let session = activeSession
		lock.unlock()
		return session?.sessionContext
	}


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
		// A listener fault, not stop(), ended the loop, so the status and the endpoint are released here.
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
