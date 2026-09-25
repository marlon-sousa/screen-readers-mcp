// ROLE: adapter, the extension's principal class.
// build.sh writes this class name into the .appex's Info.plist and the system resolves it by string,
// so renaming the class or the module without editing build.sh makes the voice silently never appear.

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
