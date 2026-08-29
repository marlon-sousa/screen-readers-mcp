// SPIKE (spec 0041, groups A, B, C). Not production code, and deliberately not
// shaped like it: there are no ports here, because this answers questions rather
// than implementing a bridge.
//
// This is a speech synthesis provider audio unit. macOS hands one of these every
// utterance ANY client asks a voice of ours to speak -- VoiceOver included -- as
// SSML, before any audio exists. Group A asks whether that feed is real,
// complete, ordered and faithful; this file is the instrument that measures it.
//
// Every observation goes out two ways, on purpose:
//   1. os_log, subsystem "voiceover-capture-spike" -- always available, works
//      under the sandbox, read with `log stream`.
//   2. an append to a JSON-lines file, which is probe B2's route and is the one
//      an actual bridge would read. Measured: it lands in the extension's own
//      container and an ordinary unsandboxed process can read it.
//
// Audio is REAL by default (see PassThrough): pointing VoiceOver at a voice that
// renders silence would mute the machine's owner.

import AVFoundation
import AudioToolbox
import Foundation
import os

let spikeLog = Logger(subsystem: "voiceover-capture-spike", category: "provider")

/// Where route 2 appends. Under the sandbox this resolves inside the extension's
/// container; loaded into another process it would follow that process's home,
/// which is itself worth seeing in the log.
let captureLogPath: String =
	ProcessInfo.processInfo.environment["VOCAPTURE_LOG"]
	?? NSHomeDirectory() + "/voiceover-capture-spike.jsonl"

/// Drop this file beside the log to render silence instead of speech. Silent
/// capture is what the bridge would eventually want; it is OPT-IN here so that
/// the default cannot leave a screen reader mute.
let silentModeMarkerPath = NSHomeDirectory() + "/voiceover-capture-silent"

/// Returns the failure reason rather than throwing, so a sandbox denial is data
/// instead of a crash inside the extension.
func appendLine(_ line: String) -> String? {
	guard let data = (line + "\n").data(using: .utf8) else { return "utf8" }
	let url = URL(fileURLWithPath: captureLogPath)
	do {
		if FileManager.default.fileExists(atPath: captureLogPath) {
			let handle = try FileHandle(forWritingTo: url)
			defer { try? handle.close() }
			try handle.seekToEnd()
			try handle.write(contentsOf: data)
		} else {
			try data.write(to: url)
		}
		return nil
	} catch {
		return String(describing: error)
	}
}

func jsonLine(_ fields: [String: Any]) -> String {
	guard let data = try? JSONSerialization.data(withJSONObject: fields, options: [.sortedKeys]),
		let text = String(data: data, encoding: .utf8)
	else { return "{\"event\":\"encode-failed\"}" }
	return text
}

func note(_ fields: [String: Any]) {
	var fields = fields
	fields["at"] = Date().timeIntervalSince1970
	let line = jsonLine(fields)
	if let failure = appendLine(line) {
		spikeLog.error("\(line, privacy: .public) file-write-failed=\(failure, privacy: .public)")
	} else {
		spikeLog.log("\(line, privacy: .public)")
	}
}

public final class CaptureAudioUnit: AVSpeechSynthesisProviderAudioUnit {
	private let format: AVAudioFormat
	private let outputBus: AUAudioUnitBus
	private var busses: AUAudioUnitBusArray!

	private let ring: AudioRing
	private let passThrough: PassThrough

	/// Scratch the render block hands back when the host supplies no buffer of
	/// its own. Allocated once, because the render block may not allocate.
	private let scratch: UnsafeMutablePointer<Float>
	private let scratchCapacity = 4096

	/// Monotonic per-process counter. A4 asks whether two identical consecutive
	/// utterances arrive as two events; without a sequence number the log could
	/// not tell them apart either, which would measure our instrument rather than
	/// VoiceOver.
	private let counter = OSAllocatedUnfairLock(initialState: 0)

	@objc override init(
		componentDescription: AudioComponentDescription,
		options: AudioComponentInstantiationOptions = []
	) throws {
		guard let format = AVAudioFormat(standardFormatWithSampleRate: 22050, channels: 1) else {
			throw NSError(domain: "voiceover-capture-spike", code: 1)
		}
		self.format = format
		self.outputBus = try AUAudioUnitBus(format: format)
		// 30 seconds. VoiceOver utterances are short; the headroom is for the case
		// where the render block is not being called at all, which is a failure we
		// want to survive rather than crash on.
		self.ring = AudioRing(capacity: Int(format.sampleRate) * 30)
		self.passThrough = PassThrough(ring: ring, outputFormat: format)
		self.scratch = UnsafeMutablePointer<Float>.allocate(capacity: scratchCapacity)
		self.scratch.initialize(repeating: 0, count: scratchCapacity)
		try super.init(componentDescription: componentDescription, options: options)
		self.busses = AUAudioUnitBusArray(audioUnit: self, busType: .output, busses: [outputBus])
		note([
			"event": "audio-unit-created",
			"log_path": captureLogPath,
			"silent": FileManager.default.fileExists(atPath: silentModeMarkerPath),
		])
	}

	deinit { scratch.deallocate() }

	public override var outputBusses: AUAudioUnitBusArray { busses }

	/// The host settles the real format here, and it is not necessarily the one
	/// declared at init. Logged, because a wrong assumption about sample rate is
	/// heard as glitching rather than reported as an error.
	public override func allocateRenderResources() throws {
		try super.allocateRenderResources()
		let format = outputBus.format
		passThrough.adoptOutputFormat(format)
		note([
			"event": "allocate-render-resources",
			"sample_rate": format.sampleRate,
			"channels": Int(format.channelCount),
			"interleaved": format.isInterleaved,
			"max_frames": Int(maximumFramesToRender),
		])
	}

	/// The voice this extension registers system-wide. VoiceOver lists it in
	/// VoiceOver Utility -> Speech alongside Apple's own, which is what makes
	/// probe A1 a question about VoiceOver rather than about AVSpeechSynthesizer.
	///
	/// pt-BR leads the primary languages because a reader only offers voices for
	/// the language it is speaking, and this machine's VoiceOver speaks Portuguese
	/// -- an en-US-only voice would never appear in its list at all.
	public override var speechVoices: [AVSpeechSynthesisProviderVoice] {
		get {
			note(["event": "speech-voices-read"])
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

	/// **The probe.** One call per utterance, before any audio is rendered.
	public override func synthesizeSpeechRequest(_ request: AVSpeechSynthesisProviderRequest) {
		let seq = counter.withLock { value -> Int in
			value += 1
			return value
		}
		let silent = FileManager.default.fileExists(atPath: silentModeMarkerPath)
		var fields: [String: Any] = [
			"event": "synthesize",
			"seq": seq,
			"ssml": request.ssmlRepresentation,
			"voice": request.voice.identifier,
			"silent": silent,
		]
		if silent {
			ring.reset()
			ring.markFinished()
		} else {
			let decision = passThrough.begin(ssml: request.ssmlRepresentation)
			fields["passthrough_voice"] = decision.voice
			fields["passthrough_language"] = decision.language
			fields["prebuffer_ms"] = passThrough.prebuffer()
		}
		note(fields)
	}

	/// A3: is interruption observable, and distinguishable from completion?
	public override func cancelSpeechRequest() {
		var fields: [String: Any] = [
			"event": "cancel",
			"contention_drops": ring.contentionDrops,
			"underruns": ring.underruns,
			"overflow_drops": ring.overflowDrops,
		]
		if let source = passThrough.sourceFormat {
			fields["source_rate"] = source.sampleRate
			fields["source_channels"] = Int(source.channelCount)
			fields["converted"] = source != passThrough.currentOutputFormat
		}
		note(fields)
		passThrough.cancel()
	}

	public override var internalRenderBlock: AUInternalRenderBlock {
		let ring = self.ring
		let scratch = self.scratch
		let scratchCapacity = self.scratchCapacity
		return { actionFlags, _, frameCount, _, outputData, _, _ in
			// Realtime thread: no IO, no allocation, no logging. B3.
			let buffers = UnsafeMutableAudioBufferListPointer(outputData)
			guard buffers.count > 0 else { return noErr }

			// Fill the host's ENTIRE request. Capping this at the scratch size left
			// the tail of every large block untouched -- audible as glitching, and
			// invisible in any log.
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

			let (filled, done) = ring.drain(into: destination, count: renderFrames)
			if filled < renderFrames {
				destination.advanced(by: filled).update(repeating: 0, count: renderFrames - filled)
			}

			// A host asking for more than one channel gets the same mono signal in
			// each, rather than one channel of speech and one of silence.
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
