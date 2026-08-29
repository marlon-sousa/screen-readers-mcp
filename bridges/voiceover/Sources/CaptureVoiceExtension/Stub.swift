// ROLE: leaf -- the .appex executable, and it is a stub on purpose.
//
// A speech provider is loaded two different ways and BOTH have to work:
//   - OUT OF PROCESS, as an app extension, which is what axassetsd does when it
//     enumerates voices; that path uses NSExtensionPrincipalClass.
//   - IN PROCESS, dlopened into whichever app is speaking -- VoiceOver included;
//     that path can only find the class if the class lives in a FRAMEWORK rather
//     than in this executable.
//
// Measured on macOS 15.0: with the audio unit compiled into the appex
// executable, voice ENUMERATION worked and every actual synthesis failed with
// CoreSynthesizer "Utterance encountered error ... retryFallbackVoice" -- silently,
// with the listener simply hearing another voice. Hence the framework, and hence
// this file.
//
// Its entry point is _NSExtensionMain, not main(): build.sh passes that linker
// flag, which is the one thing Xcode would otherwise supply invisibly. So this is
// a LIBRARY target in Package.swift -- SwiftPM's job here is to prove it compiles
// and links, not to produce the bundle, which SwiftPM cannot do.

import CaptureVoice

@_cdecl("capture_voice_stub_anchor")
public func anchor() -> UnsafeRawPointer {
	// Forces the linker to keep the framework: without a reference the AU class
	// would never be registered in the out-of-process path.
	unsafeBitCast(AudioUnitFactory.self, to: UnsafeRawPointer.self)
}
