// Mirrors Sources/CaptureVoice/Domain/Entities/AudioRing.swift.
//
// The ring is the one place in this module where a mistake is HEARD rather than
// reported, so every rule its header states is asserted here: wrap-around,
// overflow accounting, the two fades, the done semantics the render block relies
// on, and that the consumer never waits for the producer.

import Foundation
import Testing

@testable import CaptureVoice

@Suite("AudioRing")
struct AudioRingTests {
	/// Drains `count` samples and hands back what arrived. Every test reads the
	/// ring through this, so no test writes pointer arithmetic of its own.
	func drain(_ ring: AudioRing, _ count: Int) -> (samples: [Float], done: Bool) {
		var buffer = [Float](repeating: .nan, count: count)
		let result = buffer.withUnsafeMutableBufferPointer { pointer in
			ring.drain(into: pointer.baseAddress!, count: count)
		}
		return (Array(buffer.prefix(result.filled)), result.done)
	}

	func append(_ ring: AudioRing, _ samples: [Float]) {
		var samples = samples
		samples.withUnsafeMutableBufferPointer { pointer in
			ring.append(pointer.baseAddress!, count: pointer.count)
		}
	}

	@Test("what goes in comes out, in order")
	func roundTrip() {
		let ring = AudioRing(capacity: 16)
		append(ring, [1, 2, 3, 4])
		#expect(ring.available == 4)
		let drained = drain(ring, 4)
		#expect(drained.samples == [1, 2, 3, 4])
		#expect(drained.done == false)
		#expect(ring.drainedTotal == 4)
	}

	@Test("a write that runs off the end wraps, and the order survives it")
	func wrapAround() {
		// Capacity 8, so the second append starts at index 5 and wraps at 8.
		let ring = AudioRing(capacity: 8)
		append(ring, [1, 2, 3, 4, 5])
		_ = drain(ring, 5)
		append(ring, [6, 7, 8, 9, 10])
		#expect(drain(ring, 5).samples == [6, 7, 8, 9, 10])
	}

	@Test("samples that do not fit are DROPPED and counted, not silently lost")
	func overflowIsAccounted() {
		// One slot is always kept free to tell full from empty, so eight capacity
		// holds seven samples.
		let ring = AudioRing(capacity: 8)
		append(ring, [1, 2, 3, 4, 5, 6, 7, 8, 9, 10])
		#expect(ring.overflowDrops == 3)
		#expect(ring.available == 7)
	}

	@Test("a short answer while the producer is still going is an underrun")
	func underrunIsCounted() {
		let ring = AudioRing(capacity: 16)
		append(ring, [1, 2])
		let drained = drain(ring, 8)
		#expect(drained.samples == [1, 2])
		#expect(drained.done == false)
		#expect(ring.underruns == 1)
	}

	@Test("a short answer AFTER the producer finished is not an underrun -- it is the end")
	func theEndIsNotAnUnderrun() {
		let ring = AudioRing(capacity: 16)
		append(ring, [1, 2])
		ring.markFinished()
		let drained = drain(ring, 8)
		#expect(drained.done == true)
		#expect(ring.underruns == 0)
	}

	@Test("done is only true once the queue is EMPTY, not merely because the producer stopped")
	func doneWaitsForTheLastSample() {
		let ring = AudioRing(capacity: 16)
		append(ring, [1, 2, 3, 4])
		ring.markFinished()
		#expect(drain(ring, 2).done == false)
		#expect(drain(ring, 2).done == true)
	}

	@Test("fadeOutTail ramps the newest samples to zero, and leaves the rest alone")
	func fadeOutTailRamps() {
		// Speech does not end at a zero crossing; an utterance that simply stops
		// clicks, and here every utterance ends in a cancel.
		let ring = AudioRing(capacity: 32)
		append(ring, Array(repeating: 1, count: 8))
		ring.fadeOutTail(4)
		let drained = drain(ring, 8).samples
		#expect(drained.prefix(4) == [1, 1, 1, 1])
		#expect(drained[4] == 1)
		#expect(drained[7] == 0)
		#expect(drained[5] > drained[6])
	}

	@Test("a ramp of one sample or none changes nothing")
	func fadeOutTailIgnoresDegenerateRamps() {
		let ring = AudioRing(capacity: 32)
		append(ring, [1, 1, 1])
		ring.fadeOutTail(1)
		#expect(drain(ring, 3).samples == [1, 1, 1])
	}

	@Test("truncateWithFade keeps a short ramp, drops the rest, and ends the utterance")
	func truncateWithFadeIsCancellationWithoutTheClick() {
		let ring = AudioRing(capacity: 256)
		append(ring, Array(repeating: 1, count: 100))
		ring.truncateWithFade(4)
		#expect(ring.isFinished)
		#expect(ring.available == 4)
		let drained = drain(ring, 8)
		#expect(drained.samples.count == 4)
		#expect(drained.samples.first == 1)
		#expect(drained.samples.last == 0)
		#expect(drained.done == true)
	}

	@Test("truncating an empty ring still ends the utterance")
	func truncateWithNothingQueued() {
		let ring = AudioRing(capacity: 32)
		ring.truncateWithFade(4)
		#expect(ring.isFinished)
		#expect(ring.available == 0)
		#expect(drain(ring, 4).done == true)
	}

	@Test("reset clears the queue and reopens the utterance; resetCounters clears only the counters")
	func resets() {
		let ring = AudioRing(capacity: 8)
		append(ring, [1, 2, 3, 4, 5, 6, 7, 8])
		ring.markFinished()
		#expect(ring.overflowDrops == 1)
		ring.reset()
		#expect(ring.available == 0)
		#expect(ring.isFinished == false)
		#expect(ring.overflowDrops == 1)
		ring.resetCounters()
		#expect(ring.overflowDrops == 0)
	}

	@Test("the consumer never waits for the producer", .timeLimit(.minutes(1)))
	func consumerNeverBlocks() {
		// The rule this asserts is a SAFETY one: the render block runs on the audio
		// thread, so it uses trylock and takes a dropout rather than a stall. What
		// is checked is that a consumer racing a busy producer still terminates
		// promptly AND that nothing arrives out of order or twice -- a dropped
		// block must cost silence, never corruption.
		let total = 20_000
		let ring = AudioRing(capacity: 4096)
		let producer = Thread {
			var next: Float = 1
			while Int(next) <= total {
				var chunk = [Float]()
				for _ in 0..<64 where Int(next) <= total {
					chunk.append(next)
					next += 1
				}
				chunk.withUnsafeMutableBufferPointer { pointer in
					guard let base = pointer.baseAddress, pointer.count > 0 else { return }
					ring.append(base, count: pointer.count)
				}
				usleep(50)
			}
			ring.markFinished()
		}
		producer.start()

		var received: [Float] = []
		let deadline = Date().addingTimeInterval(20)
		var done = false
		while !done, Date() < deadline {
			let drained = drain(ring, 128)
			received.append(contentsOf: drained.samples)
			done = drained.done
		}
		#expect(done, "the consumer did not reach the end of the utterance in time")
		// Whatever survived must be a strictly increasing run: the ring may DROP on
		// overflow, but it must never reorder or duplicate.
		#expect(received == received.sorted())
		#expect(Set(received).count == received.count)
		#expect(received.count + ring.overflowDrops == total)
	}
}
