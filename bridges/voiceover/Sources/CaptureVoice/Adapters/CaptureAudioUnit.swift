// ROLE: adapter -- the AudioToolbox edge, and this small hexagon's composition
// root.
//
// A speech synthesis provider audio unit. macOS hands one of these every
// utterance ANY client asks a voice of ours to speak -- VoiceOver included -- as
// SSML, before any audio exists. That feed is the premise of the whole VoiceOver
// route, and it is confirmed on macOS 15.0: complete, ordered, faithful, and
// carrying prosody a polled `last phrase` discards (spec 0041, A2).
//
// WHAT IS LEFT IN THIS FILE, now that the four layers the spike ran together are
// separate: bus and format negotiation, the request and cancel entry points, and
// the render block. Everything it is asked to DECIDE it delegates to
// CaptureController, which is testable; what stays here is what cannot be tested
// without an audio device and a screen reader.
//
// AND IT WIRES THE HEXAGON, top to bottom, in `init`: the two sinks behind a
// fan-out, the marker-file mode source, the AVFoundation catalogue and
// synthesizer, the ring, the controller. Read that block to answer "who connects
// what" here.
//
// TWO OF THE SIX LIVE-ROUND FIXES ARE HERE, because both are about a THREAD:
//
//  * THE PRIO_DARWIN_BG ESCAPE. runningboardd starts this extension in the
//    background CPU band, which throttles CPU and I/O process-wide -- a dispatch
//    queue's QoS does not undo it. Re-synthesis ran at about 1x realtime under it
//    and 24x after `setpriority`, and 1x leaves no margin at all to feed an audio
//    thread.
//  * THE BOUNDED WAIT INSIDE THE RENDER BLOCK. See the comment at the wait.
//
// The render block's only collaborator is the CONCRETE AudioRing, captured
// outside the closure, so its call is statically dispatched and allocates
// nothing. That is the single binding decision the realtime constraint makes.
//
// NOTHING HERE PRINTS. Observations go through the controller to UtteranceSink;
// os_log is asynchronous, a console write is not, and this is the thread that has
// to start synthesis promptly inside somebody's screen reader.

import AVFoundation
import AudioToolbox
import Foundation

/// The subsystem every log line and every queue in this module is named after.
public let captureSubsystem = "org.screen-readers-mcp.voiceover"

/// THE IDENTIFIER THIS PROVIDER PUBLISHES, and the one VoiceChoice excludes.
///
/// The system does NOT publish it as declared: it prefixes the extension's bundle
/// id, so what appears in `speechVoices()` is
/// `<extension bundle id>.<this>`. Anything resolving our voice must therefore
/// match by SUFFIX, never by equality with what the unit declared.
///
/// It still says `spike` because the whole bundle identity is deliberately frozen
/// at what the maintainer's VoiceOver is currently pointed at -- see README.md,
/// "The bundle identity is frozen on purpose".
public let ourVoiceIdentifier = "org.screen-readers-mcp.spike.capture"

/// Where the container-file sink appends. Under the sandbox this resolves inside
/// the extension's own container, which is the only door out (spec 0041, B1/B2).
public let captureLogPath: String =
	ProcessInfo.processInfo.environment["VOCAPTURE_LOG"]
	?? NSHomeDirectory() + "/voiceover-capture.jsonl"

/// THE BRIDGE'S CHANNEL INTO THIS EXTENSION: one small JSON file, refreshed
/// while a session lives, saying whether to render silence and in whose voice to
/// speak when not. OPT-IN, so the default cannot be the setting that mutes a
/// screen reader -- and a LEASE, so a bridge that died leaves the machine
/// talking without any code of ours having to run. See
/// MarkerFileCaptureModeSource for both halves.
///
/// The override exists for the same reason `VOCAPTURE_LOG`'s does, and is read
/// the same way: a developer can point both halves at one temporary directory
/// and exercise capture mode with no reader at all. Under the sandbox, where the
/// system launches this extension, neither variable is set and both fall back to
/// the container.
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

	/// Scratch the render block hands back when the host supplies no buffer of
	/// its own. Allocated once, because the render block may not allocate.
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
		// 30 seconds. VoiceOver utterances are short; the headroom is for the case
		// where the render block is not being called at all, which is a failure we
		// want to survive rather than crash on.
		let ring = AudioRing(capacity: Int(format.sampleRate) * 30)
		let synthesizer = AVFoundationSynthesizer(outputFormat: format)
		self.ring = ring
		self.synthesizer = synthesizer
		// The wiring. Two sinks because the spike emits two ways on purpose: the
		// container file is what the bridge reads, and os_log works when a sandbox
		// denial makes the file write fail.
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
		// Leave the background band, deliberately. See the header.
		let clearedBackground = setpriority(PRIO_DARWIN_PROCESS, 0, 0)

		try super.init(componentDescription: componentDescription, options: options)
		self.busses = AUAudioUnitBusArray(audioUnit: self, busType: .output, busses: [outputBus])
		// Off the critical path on purpose: this is construction, and the 150 ms it
		// spends is 150 ms the first utterance will not.
		let controller = self.controller
		DispatchQueue.global(qos: .utility).async { controller.warmUp() }
		controller.report(
			CaptureEvent(
				kind: .audioUnitCreated,
				fields: [
					"cleared_darwin_bg": .flag(clearedBackground == 0),
					"log_path": .text(captureLogPath),
					"marker_path": .text(silentModeMarkerPath),
					// Asked of the mode source rather than of the filesystem, so this
					// line reports what the next utterance will actually do -- a marker
					// left behind by a dead bridge reads as pass-through here exactly
					// as it does there.
					"silent": .flag(modeSource.directive.silent),
				]))
	}

	deinit { scratch.deallocate() }

	public override var outputBusses: AUAudioUnitBusArray { busses }

	/// The host settles the real format here, and it is not necessarily the one
	/// declared at init. Reported, because a wrong assumption about sample rate is
	/// heard as glitching rather than raised as an error.
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

	/// The voice this extension registers system-wide. VoiceOver lists it in
	/// VoiceOver Utility -> Speech alongside Apple's own, which is what makes the
	/// whole route a question about VoiceOver rather than about
	/// AVSpeechSynthesizer.
	///
	/// pt-BR leads the primary languages because a reader only offers voices for
	/// the language it is speaking, and this machine's VoiceOver speaks Portuguese
	/// -- an en-US-only voice would never appear in its list at all.
	public override var speechVoices: [AVSpeechSynthesisProviderVoice] {
		get {
			// IT CARRIED NO FIELDS AT ALL UNTIL 13.11, which made it an event that
			// recorded only that something happened. When a live run needed to know
			// what this extension had published -- and under which identity -- the
			// log could not say, and the answer had to be inferred from a later
			// event. An event worth emitting is worth saying something.
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

	/// ONE UTTERANCE IN. Called once per utterance, before any audio is rendered.
	public override func synthesizeSpeechRequest(_ request: AVSpeechSynthesisProviderRequest) {
		controller.capture(ssml: request.ssmlRepresentation, requestedBy: request.voice.identifier)
	}

	/// Interruption, which is the NORMAL path: VoiceOver cancels before every new
	/// utterance, so a bridge must not treat "cancelled" as "something went wrong".
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

			// "Answer nothing" is not in the protocol: the render block must return
			// exactly the frames it was asked for, and its only other channel is an
			// OSStatus that means the utterance FAILED. So when the audio is not
			// ready yet there are two honest choices -- hand back silence, which
			// bakes holes into the sentence, or WAIT here for it.
			//
			// Waiting inside a render block is normally forbidden, because a render
			// block runs on the audio thread against a hard deadline. Measured on
			// macOS 15.0, this host does not pull in realtime: it renders the
			// utterance offline, as fast as it can ask -- 242,688 frames produced,
			// 242,688 delivered, none dropped, and 923 render calls that still came
			// up short. There is no deadline to miss, so waiting is safe -- and it
			// is BOUNDED anyway, so a host that DOES pull in realtime degrades to
			// the old behaviour rather than stalling.
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
