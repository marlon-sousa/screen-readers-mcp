// ROLE: entity, a single-producer, single-consumer ring of float samples between the re-synthesis thread
// and the realtime audio thread.
// USED BY: CaptureController, which owns it; AVFoundationSynthesizer writes it and CaptureAudioUnit's
// render block drains it.
// It must stay final, so the render block's calls are statically dispatched.
// `drain` only tries the lock and returns nothing on contention, because a blocked audio thread stalls speech.
// The producer must hold the lock briefly: on VoiceOver on macOS 15 a per-sample copy loop cost 449 dropped
// render blocks in eight seconds of speech, so `append` copies in at most two bulk runs.

import Foundation
import os

public final class AudioRing {
	private let capacity: Int
	private let storage: UnsafeMutablePointer<Float>
	private let lock: UnsafeMutablePointer<os_unfair_lock>
	private var writeIndex = 0
	private var readIndex = 0
	private var producerFinished = false

	/// Incremented outside the lock, so it races with `resetCounters`; it is a diagnostic.
	public private(set) var contentionDrops = 0
	public private(set) var underruns = 0
	public private(set) var overflowDrops = 0
	public private(set) var drainedTotal = 0

	public init(capacity: Int) {
		self.capacity = capacity
		self.storage = UnsafeMutablePointer<Float>.allocate(capacity: capacity)
		self.storage.initialize(repeating: 0, count: capacity)
		self.lock = UnsafeMutablePointer<os_unfair_lock>.allocate(capacity: 1)
		self.lock.initialize(to: os_unfair_lock())
	}

	deinit {
		storage.deallocate()
		lock.deallocate()
	}

	public func append(_ samples: UnsafePointer<Float>, count: Int) {
		os_unfair_lock_lock(lock)
		defer { os_unfair_lock_unlock(lock) }
		let free = (readIndex + capacity - writeIndex - 1) % capacity
		let usable = min(count, free)
		if usable < count { overflowDrops += count - usable }
		guard usable > 0 else { return }
		let firstRun = min(usable, capacity - writeIndex)
		storage.advanced(by: writeIndex).update(from: samples, count: firstRun)
		if usable > firstRun {
			storage.update(from: samples.advanced(by: firstRun), count: usable - firstRun)
		}
		writeIndex = (writeIndex + usable) % capacity
	}

	public func resetCounters() {
		os_unfair_lock_lock(lock)
		contentionDrops = 0
		underruns = 0
		overflowDrops = 0
		drainedTotal = 0
		os_unfair_lock_unlock(lock)
	}

	public var available: Int {
		os_unfair_lock_lock(lock)
		defer { os_unfair_lock_unlock(lock) }
		return (writeIndex + capacity - readIndex) % capacity
	}

	public var isFinished: Bool {
		os_unfair_lock_lock(lock)
		defer { os_unfair_lock_unlock(lock) }
		return producerFinished
	}

	public func fadeOutTail(_ count: Int) {
		os_unfair_lock_lock(lock)
		defer { os_unfair_lock_unlock(lock) }
		let available = (writeIndex + capacity - readIndex) % capacity
		let ramp = min(count, available)
		guard ramp > 1 else { return }
		for step in 0..<ramp {
			let index = (writeIndex - ramp + step + capacity) % capacity
			storage[index] *= Float(ramp - 1 - step) / Float(ramp - 1)
		}
	}

	public func truncateWithFade(_ count: Int) {
		os_unfair_lock_lock(lock)
		defer { os_unfair_lock_unlock(lock) }
		let available = (writeIndex + capacity - readIndex) % capacity
		let keep = min(count, available)
		if keep > 1 {
			for step in 0..<keep {
				let index = (readIndex + step) % capacity
				storage[index] *= Float(keep - 1 - step) / Float(keep - 1)
			}
		}
		writeIndex = (readIndex + keep) % capacity
		producerFinished = true
	}

	public func markFinished() {
		os_unfair_lock_lock(lock)
		producerFinished = true
		os_unfair_lock_unlock(lock)
	}

	public func reset() {
		os_unfair_lock_lock(lock)
		writeIndex = 0
		readIndex = 0
		producerFinished = false
		os_unfair_lock_unlock(lock)
	}

	public func drain(into destination: UnsafeMutablePointer<Float>, count: Int) -> (filled: Int, done: Bool) {
		guard os_unfair_lock_trylock(lock) else {
			contentionDrops += 1
			return (0, false)
		}
		defer { os_unfair_lock_unlock(lock) }
		let available = (writeIndex + capacity - readIndex) % capacity
		let filled = min(count, available)
		if filled > 0 {
			let firstRun = min(filled, capacity - readIndex)
			destination.update(from: storage.advanced(by: readIndex), count: firstRun)
			if filled > firstRun {
				destination.advanced(by: firstRun).update(from: storage, count: filled - firstRun)
			}
			readIndex = (readIndex + filled) % capacity
		}
		drainedTotal += filled
		let done = producerFinished && readIndex == writeIndex
		if filled < count && !done { underruns += 1 }
		return (filled, done)
	}
}
