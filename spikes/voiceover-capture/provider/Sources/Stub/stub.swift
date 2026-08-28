// SPIKE (spec 0041, group A). The extension executable is a stub on purpose.
//
// A speech provider is loaded two different ways and BOTH have to work:
//   - out of process, as an app extension, which is what axassetsd does when it
//     enumerates voices; that path uses NSExtensionPrincipalClass.
//   - in process, dlopened into whichever app is speaking -- VoiceOver included;
//     that path uses the AudioComponentBundle key, and it can only find the
//     class if the class lives in a FRAMEWORK rather than in this executable.
//
// Measured: with the audio unit compiled into the appex executable, voice
// ENUMERATION worked and every actual synthesis failed with CoreSynthesizer
// "Utterance encountered error ... retryFallbackVoice". Hence the framework.
import VOCaptureVoice

@_cdecl("vocapture_stub_anchor")
public func anchor() -> UnsafeRawPointer {
	// Forces the linker to keep the framework: without a reference the AU class
	// would never be registered in the out-of-process path.
	unsafeBitCast(AudioUnitFactory.self, to: UnsafeRawPointer.self)
}
