// ROLE: adapter at the AudioToolbox edge, and this module's composition root: `init` wires the hexagon.
// macOS 15 hands this unit every utterance any client asks our voice to speak, VoiceOver included,
// as SSML before any audio exists.
// Nothing in this module prints: this thread must start synthesis promptly, and only os_log is asynchronous.

import AVFoundation
import AudioToolbox
import Foundation

public let captureSubsystem = "org.screen-readers-mcp.voiceover"

/// The system publishes it prefixed with the extension's bundle id, so anything resolving our voice
/// must match by suffix. It is frozen: see README.md, "The bundle identity is frozen on purpose".
public let ourVoiceIdentifier = "org.screen-readers-mcp.spike.capture"

public let captureLogPath: String =
	ProcessInfo.processInfo.environment["VOCAPTURE_LOG"]
	?? NSHomeDirectory() + "/voiceover-capture.jsonl"

/// The bridge's channel into this extension; see MarkerFileCaptureModeSource.
public let silentModeMarkerPath: String =
	ProcessInfo.processInfo.environment["VOCAPTURE_MARKER"]
	?? NSHomeDirectory() + "/voiceover-capture-silent"

public final class CaptureAudioUnit: AVSpeechSynthesisProviderAudioUnit {
	private let format: AVAudioFormat
	private let outputBus: AUAudioUnitBus
	private var busses: AUAudioUnitBusArray!

	private let ring: AudioRing
	private let synthesizer: AVFoundationSynthesizer
	private let controller: CaptureController

	/// Allocated once, because the render block may not allocate.
	private let scratch: UnsafeMutablePointer<Float>
	private let scratchCapacity = 4096

	@objc override init(
		componentDescription: AudioComponentDescription,
		options: AudioComponentInstantiationOptions = []
	) throws {
		guard let format = AVAudioFormat(standardFormatWithSampleRate: 22050, channels: 1) else {
			throw NSError(domain: captureSubsystem, code: 1)
		}
		self.format = format
		self.outputBus = try AUAudioUnitBus(format: format)
		// 30 seconds, so a render block that is not being called at all is survived rather than crashed on.
		let ring = AudioRing(capacity: Int(format.sampleRate) * 30)
		let synthesizer = AVFoundationSynthesizer(outputFormat: format)
		self.ring = ring
		self.synthesizer = synthesizer
		// The container file is what the bridge reads; os_log still works when a sandbox denial fails the file write.
		let modeSource = MarkerFileCaptureModeSource(path: silentModeMarkerPath)
		self.controller = CaptureController(
			sink: FanOutUtteranceSink([
				ContainerFileUtteranceSink(path: captureLogPath, subsystem: captureSubsystem),
				OsLogUtteranceSink(subsystem: captureSubsystem, category: "capture"),
			]),
			synthesizer: synthesizer,
			catalogue: AVSpeechVoiceCatalogue(),
			mode: modeSource,
			ring: ring,
			ourVoiceIdentifier: ourVoiceIdentifier
		)
		self.scratch = UnsafeMutablePointer<Float>.allocate(capacity: scratchCapacity)
		self.scratch.initialize(repeating: 0, count: scratchCapacity)
		// runningboardd starts this extension in the background band, which throttles it whatever a queue's QoS:
		// on macOS 15 re-synthesis ran at about 1x realtime under it and 24x after `setpriority`.
		let clearedBackground = setpriority(PRIO_DARWIN_PROCESS, 0, 0)

		try super.init(componentDescription: componentDescription, options: options)
		self.busses = AUAudioUnitBusArray(audioUnit: self, busType: .output, busses: [outputBus])
		// Off the critical path; see CaptureController.warmUp.
		let controller = self.controller
		DispatchQueue.global(qos: .utility).async { controller.warmUp() }
		controller.report(
			CaptureEvent(
				kind: .audioUnitCreated,
				fields: [
					"cleared_darwin_bg": .flag(clearedBackground == 0),
					"log_path": .text(captureLogPath),
					"marker_path": .text(silentModeMarkerPath),
					// Asked of the mode source, so a stale marker reads as pass-through here exactly as it does there.
					"silent": .flag(modeSource.directive.silent),
				]))
	}

	deinit { scratch.deallocate() }

	public override var outputBusses: AUAudioUnitBusArray { busses }

	public override func allocateRenderResources() throws {
		try super.allocateRenderResources()
		let format = outputBus.format
		synthesizer.adoptOutputFormat(format)
		controller.report(
			CaptureEvent(
				kind: .allocateRenderResources,
				fields: [
					"sample_rate": .number(format.sampleRate),
					"channels": .count(Int(format.channelCount)),
					"interleaved": .flag(format.isInterleaved),
					"max_frames": .count(Int(maximumFramesToRender)),
				]))
	}

	/// pt-BR leads because a reader offers only voices for the language it speaks, and this machine's
	/// VoiceOver speaks Portuguese.
	public override var speechVoices: [AVSpeechSynthesisProviderVoice] {
		get {
			controller.report(
				CaptureEvent(
					kind: .speechVoicesRead,
					fields: [
						"offered": .count(1),
						"identifier": .text(ourVoiceIdentifier),
					]))
			return [
				AVSpeechSynthesisProviderVoice(
					name: "Capture Spike",
					identifier: ourVoiceIdentifier,
					primaryLanguages: ["pt-BR", "en-US"],
					supportedLanguages: ["pt-BR", "en-US"]
				)
			]
		}
		set {}
	}

	public override func synthesizeSpeechRequest(_ request: AVSpeechSynthesisProviderRequest) {
		controller.capture(ssml: request.ssmlRepresentation, requestedBy: request.voice.identifier)
	}

	/// VoiceOver cancels before every new utterance, so a cancel is the normal path, not a failure.
	public override func cancelSpeechRequest() {
		controller.cancel()
	}

	public override var internalRenderBlock: AUInternalRenderBlock {
		let ring = self.ring
		let scratch = self.scratch
		let scratchCapacity = self.scratchCapacity
		return { actionFlags, _, frameCount, _, outputData, _, _ in
			// Realtime thread: no IO, no allocation, no logging.
			let buffers = UnsafeMutableAudioBufferListPointer(outputData)
			guard buffers.count > 0 else { return noErr }

			// Fill the host's entire request: an untouched tail is audible as glitching and invisible in any log.
			let frames = Int(frameCount)
			let usingScratch = buffers[0].mData == nil
			let renderFrames = usingScratch ? min(frames, scratchCapacity) : frames

			let destination: UnsafeMutablePointer<Float>
			if let provided = buffers[0].mData {
				destination = provided.assumingMemoryBound(to: Float.self)
			} else {
				destination = scratch
				buffers[0].mData = UnsafeMutableRawPointer(scratch)
				buffers[0].mDataByteSize = UInt32(renderFrames * MemoryLayout<Float>.size)
			}

			// The render block must return every frame asked for, and its only other answer means the utterance failed.
			// VoiceOver on macOS 15 renders offline rather than in realtime (242,688 frames delivered, none dropped,
			// 923 render calls still short), so waiting here is safe; the wait is bounded for a host that is realtime.
			var (filled, done) = ring.drain(into: destination, count: renderFrames)
			if filled < renderFrames, !done {
				let waitUntil = Date().addingTimeInterval(0.25)
				while filled < renderFrames, !done, Date() < waitUntil {
					usleep(500)
					let more = ring.drain(
						into: destination.advanced(by: filled), count: renderFrames - filled)
					filled += more.filled
					done = more.done
				}
			}
			if filled < renderFrames {
				destination.advanced(by: filled).update(repeating: 0, count: renderFrames - filled)
			}

			if buffers.count > 1 {
				for index in 1..<buffers.count {
					if let other = buffers[index].mData {
						other.assumingMemoryBound(to: Float.self).update(from: destination, count: renderFrames)
					} else {
						buffers[index].mData = UnsafeMutableRawPointer(destination)
						buffers[index].mDataByteSize = UInt32(renderFrames * MemoryLayout<Float>.size)
					}
				}
			}

			if done {
				actionFlags.pointee = .offlineUnitRenderAction_Complete
			}
			return noErr
		}
	}
}
