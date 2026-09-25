// ROLE: adapter implementing the LineTailer seam over a real file, on a thread of its own.
// USED BY: ContainerFileSpeechSource.
// BUILT BY: VoiceOverAdapterFactory.
// Polled, because a DispatchSource watch on a descriptor this process holds does not see the extension's writes, which reopen the file.

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

		// Attach and seek before returning: the agent acts right after the handshake, and an utterance appended before the attach would be lost.
		// Seeking to the end skips speech from earlier launches; a file that does not exist yet is opened later, from the top.
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

	/// Splits complete lines and carries the partial tail; a line that is not valid UTF-8 is a torn write and is dropped.
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
		// Re-based so the slice's start index does not grow without bound.
		pending = Data(pending)
		return complete
	}
}
