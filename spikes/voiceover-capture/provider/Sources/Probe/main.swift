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
