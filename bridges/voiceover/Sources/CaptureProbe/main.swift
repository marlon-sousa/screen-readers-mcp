// ROLE: diagnostic executable -- KEPT, per spec 0046's amendment to board 13.2.
//
// A standalone client that exercises the provider WITHOUT involving VoiceOver, so
// "the extension never ran" and "VoiceOver did not pick our voice" stay separable
// failures. That makes it a live-checklist DEPENDENCY -- it is what answers "is
// the capture voice published?" without a human squinting at a settings pane --
// and a checklist's dependencies are versioned rather than improvised.
//
//   probe list          -- is our voice visible to AVSpeechSynthesisVoice?
//   probe speak <text>  -- speak it through our voice and wait
//   probe components    -- raw AudioComponent enumeration for type 'ausp'
//   probe refresh       -- ask the system to re-read provider voices
//   probe passthrough   -- run the REAL capture path, outside the extension
//
// It prints, and that is its whole purpose: a human runs it from a terminal and
// reads the answer. Nothing inside CaptureVoice prints -- see that module's
// headers for why.
import AVFoundation
import CaptureVoice
import Foundation

// The system does NOT publish the identifier the extension declares: it prefixes
// the extension's bundle id. Resolve by suffix rather than hard-coding either
// form -- and take the suffix from the module, so there is one spelling of it.
let ourSuffix = ourVoiceIdentifier

func ourVoice() -> AVSpeechSynthesisVoice? {
	AVSpeechSynthesisVoice.speechVoices().first { $0.identifier.hasSuffix(ourSuffix) }
}
let args = Array(CommandLine.arguments.dropFirst())

func listVoices() {
	let voices = AVSpeechSynthesisVoice.speechVoices()
	print("total voices: \(voices.count)")
	for voice in voices where voice.identifier.hasSuffix(ourSuffix) || voice.name.contains("Capture") {
		print("FOUND ours: \(voice.name) [\(voice.identifier)] lang=\(voice.language) quality=\(voice.quality.rawValue)")
	}
}

final class Delegate: NSObject, AVSpeechSynthesizerDelegate {
	var finished = false
	func speechSynthesizer(_ s: AVSpeechSynthesizer, didFinish u: AVSpeechUtterance) {
		print("delegate: didFinish")
		finished = true
	}
	func speechSynthesizer(_ s: AVSpeechSynthesizer, didCancel u: AVSpeechUtterance) {
		print("delegate: didCancel")
		finished = true
	}
	func speechSynthesizer(_ s: AVSpeechSynthesizer, didStart u: AVSpeechUtterance) {
		print("delegate: didStart")
	}
}

switch args.first {
case "list", nil:
	listVoices()
case "speak":
	guard let voice = ourVoice() else {
		print("our voice is NOT constructible by identifier -- extension not visible")
		exit(2)
	}
	print("using \(voice.name) [\(voice.identifier)]")
	let synth = AVSpeechSynthesizer()
	let delegate = Delegate()
	synth.delegate = delegate
	let utterance = AVSpeechUtterance(string: args.count > 1 ? args[1] : "one two three")
	utterance.voice = voice
	synth.speak(utterance)
	let deadline = Date().addingTimeInterval(10)
	while !delegate.finished && Date() < deadline {
		RunLoop.current.run(until: Date().addingTimeInterval(0.1))
	}
	print(delegate.finished ? "completed" : "TIMED OUT after 10s")
// Handled below, each in its own block, because each was appended as its own
// question during the spike. Named here so that a good subcommand does not print
// a usage banner above its own output -- which reads exactly like a failure.
case "components", "refresh", "passthrough":
	break
default:
	print("usage: probe [list|speak <text>|components|refresh|passthrough]")
}

// Raw AudioComponent enumeration for type 'ausp'. If our provider is absent HERE,
// the audio component registrar never saw the appex -- a different failure from
// "VoiceOver ignored it".
func fourCC(_ value: OSType) -> String {
	let bytes = [UInt8((value >> 24) & 0xff), UInt8((value >> 16) & 0xff), UInt8((value >> 8) & 0xff), UInt8(value & 0xff)]
	return String(bytes: bytes, encoding: .ascii) ?? "????"
}

if args.first == "components" {
	var description = AudioComponentDescription(
		componentType: kAudioUnitType_SpeechSynthesizer,
		componentSubType: 0, componentManufacturer: 0, componentFlags: 0, componentFlagsMask: 0)
	var component = AudioComponentFindNext(nil, &description)
	var count = 0
	while let found = component {
		var descr = AudioComponentDescription()
		AudioComponentGetDescription(found, &descr)
		var name: Unmanaged<CFString>?
		AudioComponentCopyName(found, &name)
		count += 1
		print("  \(fourCC(descr.componentType)) \(fourCC(descr.componentSubType)) \(fourCC(descr.componentManufacturer))  \(name?.takeRetainedValue() as String? ?? "")")
		component = AudioComponentFindNext(found, &description)
	}
	print("speech-synthesizer components: \(count)")
}

// The step the voice list will not happen without. A provider's voices do not
// appear merely because the extension registered -- something has to ask the
// system to re-read them, and that is this class method.
if args.first == "refresh" {
	AVSpeechSynthesisProviderVoice.updateSpeechVoices()
	print("requested updateSpeechVoices(); waiting 3s")
	RunLoop.current.run(until: Date().addingTimeInterval(3))
	listVoices()
}

/// Prints what the controller emitted. The probe is the one place a CaptureEvent
/// is meant to reach a human directly.
final class PrintingSink: UtteranceSink {
	func emit(_ event: CaptureEvent) {
		print("  event \(event.kind.rawValue): \(event.fields.sorted { $0.key < $1.key })")
	}
}

/// The probe never renders silence: it is asking whether re-synthesis WORKS.
struct AlwaysSpeaking: CaptureModeSource {
	var isSilent: Bool { false }
}

// Exercise the re-synthesis path OUTSIDE the extension, through the REAL
// controller and the real adapters. This is how the capture path is checked
// without asking the maintainer to point his only screen reader at an untested
// voice -- if the audio is wrong here, it would be wrong there, and the machine
// would go quiet.
if args.first == "passthrough" {
	let text = args.count > 1 ? args[1] : "um dois tres"
	let language = args.count > 2 ? args[2] : "pt-BR"
	let ssml = "<speak xml:lang=\"\(language)\">\(text)</speak>"
	guard let format = AVAudioFormat(standardFormatWithSampleRate: 22050, channels: 1) else { exit(3) }
	let ring = AudioRing(capacity: 22050 * 30)
	let synthesizer = AVFoundationSynthesizer(outputFormat: format)
	let controller = CaptureController(
		sink: PrintingSink(),
		synthesizer: synthesizer,
		catalogue: AVSpeechVoiceCatalogue(),
		mode: AlwaysSpeaking(),
		ring: ring,
		ourVoiceIdentifier: ourVoiceIdentifier
	)
	print("ssml: \(ssml)")

	// WARM THE CATALOGUE FIRST, and the reason is the trap this line exists to
	// close. The first AVSpeechSynthesisVoice(language:) in a process costs about
	// 150 ms and every one after it costs 0.4 ms, so a stopwatch started before it
	// reports a PROCESS START-UP cost as though it were per-utterance latency --
	// 0.35 s where the same code measured 0.21 s. Spec 0041's C4 numbers were
	// taken after the lookup, so this keeps the probe comparable to them, and the
	// extension pays this cost at construction (CaptureController.warmUp) rather
	// than on its first utterance.
	controller.warmUp()

	let started = Date()
	// OFF THE MAIN THREAD, and this is not a detail -- it is the difference
	// between a measurement and a constant.
	//
	// `speak` waits for the first samples before returning, because the render
	// block has no way to say "not ready yet" and somebody has to wait. In the
	// extension that wait happens on the system's request thread, which is not a
	// run loop thread, and the synthesizer's buffer callbacks arrive regardless.
	// In a command-line tool the main thread IS the run loop, so waiting on it
	// starves the very callbacks it is waiting for: every measurement came back
	// as the 2.0 s prebuffer budget plus overhead, whatever the utterance.
	//
	// So the probe calls the controller the way the extension does, and pumps the
	// run loop here while draining -- which is also what the spike's probe did,
	// by not calling the prebuffer wait at all.
	DispatchQueue.global(qos: .userInitiated).async {
		controller.capture(ssml: ssml, requestedBy: ourVoiceIdentifier)
	}

	// The ADDED LATENCY is the wait before the first sample exists -- an agent
	// driving a reader feels this on every utterance.
	var firstSampleAt: Date?
	var samples: [Float] = []
	let chunk = 1024
	var scratch = [Float](repeating: 0, count: chunk)
	let deadline = Date().addingTimeInterval(15)
	var done = false
	while !done && Date() < deadline {
		let result = scratch.withUnsafeMutableBufferPointer { buffer -> (filled: Int, done: Bool) in
			ring.drain(into: buffer.baseAddress!, count: chunk)
		}
		if result.filled > 0 {
			if firstSampleAt == nil { firstSampleAt = Date() }
			samples.append(contentsOf: scratch[0..<result.filled])
		}
		done = result.done
		if result.filled == 0 && !done { RunLoop.current.run(until: Date().addingTimeInterval(0.02)) }
	}

	let seconds = Double(samples.count) / format.sampleRate
	let peak = samples.map { abs($0) }.max() ?? 0
	print("frames: \(samples.count)  seconds: \(String(format: "%.2f", seconds))  peak: \(String(format: "%.3f", peak))")
	let latency = (firstSampleAt ?? Date()).timeIntervalSince(started)
	print("first sample after: \(String(format: "%.3f", latency))s  total wall: \(String(format: "%.3f", Date().timeIntervalSince(started)))s")
	print("finished cleanly: \(done)   contention drops: \(ring.contentionDrops)")

	let out = URL(fileURLWithPath: NSTemporaryDirectory() + "voiceover-capture-passthrough.wav")
	if !samples.isEmpty,
		let file = try? AVAudioFile(forWriting: out, settings: format.settings),
		let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)) {
		buffer.frameLength = AVAudioFrameCount(samples.count)
		samples.withUnsafeBufferPointer { source in
			buffer.floatChannelData![0].update(from: source.baseAddress!, count: samples.count)
		}
		try? file.write(from: buffer)
		print("wrote \(out.path)")
	}
}
