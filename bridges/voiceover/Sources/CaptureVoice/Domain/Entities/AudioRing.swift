// ROLE: entity -- AUDIO OUTPUT. A single-producer, single-consumer ring of float
// samples between the thread that re-synthesizes audio and the realtime thread
// that has to hand samples to the system.
//
// Pure: it does no IO and knows nothing about AVFoundation. Owned by
// CaptureController, written by AVFoundationSynthesizer, and read by
// CaptureAudioUnit's render block -- which captures it CONCRETELY, outside the
// closure, so the call is statically dispatched. That is the one binding
// decision the realtime constraint actually makes (spec 0046, part 3); every
// other collaborator in this module is free to be a protocol.
//
// `final`, and it must stay final.
//
// THE CONSUMER NEVER WAITS. It uses os_unfair_lock_trylock: if the producer holds
// the lock at that instant, the render block emits silence for that one block
// rather than blocking the audio thread. A dropout is a glitch; a blocked audio
// thread stalls everything the machine is saying.
//
// AND THE PRODUCER MUST NOT HOLD THE LOCK LONG, which is the same rule read from
// the other side. A per-sample copy loop held it for thousands of iterations per
// buffer and cost 449 dropped render blocks in eight seconds of live VoiceOver
// speech -- audible. `append` copies in at most two bulk runs for exactly that
// reason, and the measurement is why this is a rule rather than a preference.
//
// `os` is imported for the LOCK PRIMITIVE only. There is no logging in the
// domain: that is an adapter behind UtteranceSink.

import Foundation
import os

public final class AudioRing {
	private let capacity: Int
	private let storage: UnsafeMutablePointer<Float>
	private let lock: UnsafeMutablePointer<os_unfair_lock>
	private var writeIndex = 0
	private var readIndex = 0
	private var producerFinished = false

	/// Counted so a dropout is reportable rather than merely audible.
	///
	/// Incremented on the failed-trylock path, which is by definition outside the
	/// lock, so this one counter races with `resetCounters`. Deliberate: it is a
	/// diagnostic, and making it exact would mean an atomic on the audio thread to
	/// improve a number nobody acts on to single-digit precision.
	public private(set) var contentionDrops = 0
	/// Render blocks that wanted samples, were not finished, and got fewer than
	/// asked. This is glitching, measured at its source.
	public private(set) var underruns = 0
	/// Samples the producer could not fit -- the other way audio goes missing.
	public private(set) var overflowDrops = 0
	/// Total samples actually handed to the audio thread. Compared against what
	/// the synthesizer produced, this separates "the audio never arrived" from
	/// "the audio played and we simply never said it was over".
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

	/// Producer side. Blocking is fine here -- this is not the audio thread -- but
	/// how LONG it blocks is not, because the consumer only ever TRIES the lock.
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

	/// Samples queued and not yet rendered.
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

	/// Ramps the most recently written samples down to zero.
	///
	/// Speech does not end at a zero crossing, and an utterance that simply stops
	/// mid-waveform is heard as a click. In an ATTENDED session -- a person
	/// listening while an agent drives -- those clicks are the product, not a
	/// cosmetic detail, so the ramp belongs here rather than in a "nice to have"
	/// list.
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

	/// Cancellation, without the click. Keeps a short ramp of what is queued,
	/// fades it to zero and declares the utterance over, instead of cutting the
	/// waveform off where it happens to be. Cancellation is EVERY utterance here,
	/// so this path is the common one.
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

	/// Consumer side, called from the render block. Returns how many samples were
	/// filled and whether the utterance is over.
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
