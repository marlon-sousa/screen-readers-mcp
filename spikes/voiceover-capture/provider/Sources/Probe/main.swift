// SPIKE (spec 0041). A standalone client that exercises the provider WITHOUT
// involving VoiceOver, so "the extension never ran" and "VoiceOver did not pick
// our voice" stay separable failures.
//
//   probe list          -- is our voice visible to AVSpeechSynthesisVoice?
//   probe speak <text>  -- speak it through our voice and wait
import AVFoundation
import Foundation

// The system does NOT publish the identifier the extension declares: it prefixes
// the extension's bundle id, so our "org.screen-readers-mcp.spike.capture" is
// published as "<extension bundle id>.org.screen-readers-mcp.spike.capture".
// Resolve by suffix rather than hard-coding either form.
let ourSuffix = "org.screen-readers-mcp.spike.capture"

func ourVoice() -> AVSpeechSynthesisVoice? {
	AVSpeechSynthesisVoice.speechVoices().first { $0.identifier.hasSuffix(ourSuffix) }
}
let args = Array(CommandLine.arguments.dropFirst())

func listVoices() {
	let voices = AVSpeechSynthesisVoice.speechVoices()
	print("total voices: \(voices.count)")
	for voice in voices where voice.identifier.contains("screen-readers-mcp") || voice.name.contains("Capture") {
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
default:
	print("usage: probe [list|speak <text>]")
}

// Appended: raw AudioComponent enumeration for type 'ausp'. If our provider is
// absent HERE, the audio component registrar never saw the appex -- a different
// failure from "VoiceOver ignored it".
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

// Appended: the step the voice list will not happen without. A provider's voices
// do not appear merely because the extension registered -- something has to ask
// the system to re-read them, and that is this class method.
if args.first == "refresh" {
	AVSpeechSynthesisProviderVoice.updateSpeechVoices()
	print("requested updateSpeechVoices(); waiting 3s")
	RunLoop.current.run(until: Date().addingTimeInterval(3))
	listVoices()
}

// Appended: exercise the re-synthesis path OUTSIDE the extension. This is how
// probe C4's logic is checked without asking the maintainer to point his only
// screen reader at an untested voice -- if the audio is wrong here, it would be
// wrong there, and the machine would go quiet.
if args.first == "passthrough" {
	let text = args.count > 1 ? args[1] : "um dois tres"
	let language = args.count > 2 ? args[2] : "pt-BR"
	let ssml = "<speak xml:lang=\"\(language)\">\(text)</speak>"
	guard let format = AVAudioFormat(standardFormatWithSampleRate: 22050, channels: 1) else { exit(3) }
	let ring = AudioRing(capacity: 22050 * 30)
	let passThrough = PassThrough(ring: ring, outputFormat: format)
	let decision = passThrough.begin(ssml: ssml)
	print("ssml: \(ssml)")
	print("re-spoken with: \(decision.voice)  language: \(decision.language)")

	// C4 asks for the ADDED LATENCY, which is the wait before the first sample
	// exists -- an agent driving a reader feels this on every utterance.
	let started = Date()
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
