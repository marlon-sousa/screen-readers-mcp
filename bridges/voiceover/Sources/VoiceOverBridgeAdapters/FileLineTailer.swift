// ROLE: adapter -- IMPLEMENTS the LineTailer seam over a real file, on a thread
// of its own.
//
// USED BY: ContainerFileSpeechSource, which is the only thing that knows what a
// line means. BUILT BY: VoiceOverAdapterFactory, from the path Wiring resolved.
//
// AN AMENDMENT TO SPEC 0046's 13.5 LAYOUT, with its why. The layout calls this a
// LEAF -- "real reads on the container file" -- and a leaf makes no decisions
// and gets no test. This one makes three, and each fails silently rather than
// loudly:
//
//   * WHERE TO START. The extension appends to one file across every launch of
//     the reader, so a tailer that began at byte zero would replay days of old
//     speech into a fresh session as though the reader had just said it. It
//     starts at the file's END -- unless the file does not exist yet, in which
//     case everything written to it is new by definition.
//   * WHERE A LINE ENDS. A read can land mid-line, and an utterance split across
//     two reads is either lost or delivered as two. The partial tail is held
//     until its newline arrives.
//   * WHEN THE FILE APPEARS. The extension creates it the first time the reader
//     speaks through our voice, which is routinely after the session began, so
//     "not there" is a state to keep polling through rather than a failure.
//
// The alternative was another seam beneath this one so that the decisions could
// sit above a leaf that only calls the OS. That is the shape the repo prefers,
// and it was not taken here for one reason: the decisions above are all about
// what a real file does -- appearing late, growing between reads, splitting a
// line across two -- and a fake seam would only ever prove they behave as the
// fake was written to behave. So this is an ADAPTER WITH A TEST, and its test
// drives a real file in a temporary directory, exactly as this lane's socket
// scenarios drive real sockets for the same reason.
//
// POLLED, NOT WATCHED. A DispatchSource file watch fires on writes to a
// descriptor we hold, and the writer here is another process that opens the file
// afresh; polling is what the spike measured working. The cadence is a
// deliberate floor on the feed's latency -- and the one number in this class a
// live run should be measured against (spec 0046, open question 3).

import Foundation

public final class FileLineTailer: LineTailer {
	private let path: String
	private let pollInterval: TimeInterval

	private let lock = NSLock()
	private var running = false

	/// Bytes read but not yet terminated by a newline.
	private var pending = Data()

	public init(path: String, pollInterval: TimeInterval = 0.05) {
		self.path = path
		self.pollInterval = pollInterval
	}

	public func start(_ onLine: @escaping (String) -> Void) {
		lock.lock()
		if running {
			lock.unlock()
			return
		}
		running = true
		lock.unlock()

		// ATTACHED SYNCHRONOUSLY, BEFORE THIS METHOD RETURNS, and that is not
		// tidiness: the handshake starts capture and the agent acts immediately
		// after it, so anything appended between the two must already be on the
		// right side of the seek. Attaching on the new thread instead left that
		// to the scheduler, and the utterance an action caused -- the only one a
		// test is ever waiting for -- was the one that could go missing.
		//
		// The seek is what makes it "from the end": the capture voice appends to
		// one file across every launch of the reader, and a tailer that began at
		// byte zero would pour days of old speech into a fresh session. A file
		// that does not exist yet is opened by the loop instead, from the top,
		// because everything in it will be newer than this session.
		let attached = FileHandle(forReadingAtPath: path)
		if let attached {
			_ = try? attached.seekToEnd()
		}
		let thread = Thread { [weak self] in self?.follow(attached, onLine) }
		thread.name = "voiceover-capture-tail"
		thread.start()
	}

	public func stop() {
		lock.lock()
		running = false
		lock.unlock()
	}

	private var isRunning: Bool {
		lock.lock()
		defer { lock.unlock() }
		return running
	}

	private func follow(_ attached: FileHandle?, _ onLine: @escaping (String) -> Void) {
		var handle = attached
		defer { try? handle?.close() }

		while isRunning {
			// Only ever taken when the file did not exist at start: the extension
			// creates it the first time the reader speaks through our voice, which
			// is routinely after a session began.
			if handle == nil {
				handle = FileHandle(forReadingAtPath: path)
			}
			if let handle {
				let data = (try? handle.readToEnd()) ?? Data()
				if !data.isEmpty {
					for line in lines(from: data) where !line.isEmpty {
						onLine(line)
					}
				}
			}
			Thread.sleep(forTimeInterval: pollInterval)
		}
	}

	/// Split `data` into complete lines, carrying any partial tail forward.
	///
	/// A line that is not valid UTF-8 is dropped rather than replaced with
	/// substitution characters: the feed is JSON written by one known producer,
	/// so mojibake means a torn write, and half an utterance read as words would
	/// be worse than none.
	private func lines(from data: Data) -> [String] {
		pending.append(data)
		var complete: [String] = []
		while let newline = pending.firstIndex(of: UInt8(ascii: "\n")) {
			let raw = pending[pending.startIndex..<newline]
			pending = pending[pending.index(after: newline)...]
			if let text = String(data: raw, encoding: .utf8) {
				complete.append(text)
			}
		}
		// Re-based so the slice's start index does not grow without bound over a
		// long session.
		pending = Data(pending)
		return complete
	}
}
