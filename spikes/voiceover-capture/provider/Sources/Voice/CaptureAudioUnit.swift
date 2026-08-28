// SPIKE (spec 0041, group A). Not production code, and deliberately not shaped
// like it: there are no ports here, because this answers questions rather than
// implementing a bridge.
//
// This is a speech synthesis provider audio unit. macOS hands one of these every
// utterance ANY client asks a voice of ours to speak -- VoiceOver included -- as
// SSML, before any audio exists. Group A asks whether that feed is real,
// complete, ordered and faithful; this file is the instrument that measures it.
//
// Every observation goes out two ways, on purpose:
//   1. os_log, subsystem "voiceover-capture-spike" -- always available, works
//      under the sandbox, read with `log stream`.
//   2. an append to a JSON-lines file -- which is probe B1/B2's question. The
//      file write is EXPECTED to fail once the sandbox is on; when it does, the
//      failure itself is logged through route 1, which is the measurement.

import AVFoundation
import AudioToolbox
import Foundation
import os

let spikeLog = Logger(subsystem: "voiceover-capture-spike", category: "provider")

/// Where route 2 appends. Overridable so the harness can point it at the spike
/// directory instead of a temp path nobody can find later.
let captureLogPath: String =
	ProcessInfo.processInfo.environment["VOCAPTURE_LOG"]
	?? NSHomeDirectory() + "/voiceover-capture-spike.jsonl"

/// Route 2. Returns the errno-ish reason on failure rather than throwing, so a
/// sandbox denial is data instead of a crash inside the extension.
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

public final class CaptureAudioUnit: AVSpeechSynthesisProviderAudioUnit {
	private let format: AVAudioFormat
	private let outputBus: AUAudioUnitBus
	private var busses: AUAudioUnitBusArray!

	/// Monotonic per-process counter. A4 asks whether two identical consecutive
	/// utterances arrive as two events; without a sequence number the log could
	/// not tell them apart either, which would measure our instrument rather
	/// than VoiceOver.
	private let counter = OSAllocatedUnfairLock(initialState: 0)

	/// Set by synthesizeSpeechRequest, read by the render block. The render
	/// block is realtime and must not allocate or do IO (probe B3) -- so all it
	/// ever does with this is read a frame budget and clear it.
	private let pending = OSAllocatedUnfairLock(initialState: 0)

	@objc override init(
		componentDescription: AudioComponentDescription,
		options: AudioComponentInstantiationOptions = []
	) throws {
		guard let format = AVAudioFormat(standardFormatWithSampleRate: 22050, channels: 1) else {
			throw NSError(domain: "voiceover-capture-spike", code: 1)
		}
		self.format = format
		self.outputBus = try AUAudioUnitBus(format: format)
		try super.init(componentDescription: componentDescription, options: options)
		self.busses = AUAudioUnitBusArray(audioUnit: self, busType: .output, busses: [outputBus])
		note(["event": "audio-unit-created", "log_path": captureLogPath])
	}

	public override var outputBusses: AUAudioUnitBusArray { busses }

	/// The voice this extension registers system-wide. VoiceOver lists it in
	/// VoiceOver Utility -> Speech alongside Apple's own, which is what makes
	/// probe A1 a question about VoiceOver rather than about AVSpeechSynthesizer.
	public override var speechVoices: [AVSpeechSynthesisProviderVoice] {
		get {
			// Logged because "the voice never appeared" has two very different
			// causes -- the system never asked us, or it asked and discarded the
			// answer -- and only this line tells them apart.
			note(["event": "speech-voices-read"])
			return [
				AVSpeechSynthesisProviderVoice(
					name: "Capture Spike",
					identifier: "org.screen-readers-mcp.spike.capture",
					primaryLanguages: ["en-US"],
					supportedLanguages: ["en-US", "pt-BR"]
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
		note([
			"event": "synthesize",
			"seq": seq,
			"ssml": request.ssmlRepresentation,
			"voice": request.voice.identifier,
		])
		// Enough frames that an interruption has a window to land in (A3).
		pending.withLock { $0 = Int(format.sampleRate) }
	}

	/// A3: is interruption observable, and distinguishable from completion?
	public override func cancelSpeechRequest() {
		note(["event": "cancel"])
		pending.withLock { $0 = 0 }
	}

	public override var internalRenderBlock: AUInternalRenderBlock {
		let pending = self.pending
		return { actionFlags, _, frameCount, _, outputData, _, _ in
			// Realtime thread: no IO, no allocation, no logging. B3.
			let buffers = UnsafeMutableAudioBufferListPointer(outputData)
			for buffer in buffers {
				memset(buffer.mData, 0, Int(buffer.mDataByteSize))
			}
			let remaining = pending.withLock { value -> Int in
				value = max(0, value - Int(frameCount))
				return value
			}
			if remaining == 0 {
				actionFlags.pointee = .offlineUnitRenderAction_Complete
			}
			return noErr
		}
	}

	private func note(_ fields: [String: Any]) {
		var fields = fields
		fields["at"] = Date().timeIntervalSince1970
		let line = jsonLine(fields)
		if let failure = appendLine(line) {
			spikeLog.error("\(line, privacy: .public) file-write-failed=\(failure, privacy: .public)")
		} else {
			spikeLog.log("\(line, privacy: .public)")
		}
	}
}
