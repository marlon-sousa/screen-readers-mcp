// SPIKE (spec 0041, group A). The extension's principal class.
//
// Named to match Apple's own speech providers, which is not decoration: reading
// SiriAUSP.appex and MauiAUSP.appex on macOS 15.0 is where this bundle's whole
// shape came from -- NSExtensionPointIdentifier com.apple.AudioUnit-Speech, an
// AudioComponents entry of type "ausp" tagged "Speech Synthesizer", and an
// NSExtensionPrincipalClass of "<module>.AudioUnitFactory". That is ground truth
// for this OS version rather than a recalled doc, per the repo's rule about
// reading the real source.

import AudioToolbox
import AVFoundation
import Foundation

public final class AudioUnitFactory: NSObject, AUAudioUnitFactory {
	private var audioUnit: AUAudioUnit?

	public func beginRequest(with context: NSExtensionContext) {
		spikeLog.log("begin-request")
	}

	public func createAudioUnit(with componentDescription: AudioComponentDescription) throws -> AUAudioUnit {
		let unit = try CaptureAudioUnit(componentDescription: componentDescription, options: [])
		audioUnit = unit
		return unit
	}
}
