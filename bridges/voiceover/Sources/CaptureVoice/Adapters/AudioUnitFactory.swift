// ROLE: adapter -- the extension's principal class.
//
// Named to match Apple's own speech providers, which is not decoration: reading
// SiriAUSP.appex and MauiAUSP.appex on macOS 15.0 is where this bundle's whole
// shape came from -- NSExtensionPointIdentifier com.apple.AudioUnit-Speech, an
// AudioComponents entry of type "ausp" tagged "Speech Synthesizer", and an
// NSExtensionPrincipalClass of "<module>.AudioUnitFactory". That is ground truth
// for this OS version rather than a recalled doc, per the repo's rule about
// reading the real source.
//
// build.sh writes that class name into the .appex's Info.plist, so RENAMING THIS
// CLASS OR THE MODULE MEANS EDITING THE SCRIPT -- the system resolves it by
// string and a mismatch fails silently, with the voice simply never appearing.

import AVFoundation
import AudioToolbox
import Foundation
import os

public final class AudioUnitFactory: NSObject, AUAudioUnitFactory {
	private let log = Logger(subsystem: captureSubsystem, category: "provider")
	private var audioUnit: AUAudioUnit?

	public func beginRequest(with context: NSExtensionContext) {
		log.log("begin-request")
	}

	public func createAudioUnit(with componentDescription: AudioComponentDescription) throws -> AUAudioUnit {
		let unit = try CaptureAudioUnit(componentDescription: componentDescription, options: [])
		audioUnit = unit
		return unit
	}
}
