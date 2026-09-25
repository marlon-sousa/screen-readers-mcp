// ROLE: leaf, the .appex executable; the audio unit lives in the CaptureVoice framework (see Package.swift).

import CaptureVoice

@_cdecl("capture_voice_stub_anchor")
public func anchor() -> UnsafeRawPointer {
	// Keeps the framework linked: without a reference the out-of-process path never registers the class.
	unsafeBitCast(AudioUnitFactory.self, to: UnsafeRawPointer.self)
}
