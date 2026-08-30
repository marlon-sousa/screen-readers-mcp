// ROLE: adapter seam -- which voices this MACHINE publishes, by identifier.
//
// NOT A DOMAIN PORT: the domain asks "has the capture voice been published?" and
// does not know that the answer is a list from a speech framework.
//
// IMPLEMENTED BY: SystemPublishedVoices (a leaf) and FakePublishedVoices
// (Tests/Fakes). USED BY: PluginKitProviderLifecycle, which is the one place
// that decides what the list MEANS.
//
// SYSTEM-WIDE PUBLICATION IS NOT THE SAME QUESTION AS "DOES VOICEOVER OFFER IT",
// and the distance between them is exactly spec 0047's finding 6: the voice was
// absent from VoiceOver's own picker at the same moment this list reported 191
// voices with ours among them, with the extension registered and its process
// alive. Nothing observable from outside the reader distinguishes that from
// health, which is why `ProviderState.published` names a condition it cannot
// rule out rather than promoting itself to `selected`.
//
// IT IS ALSO WHERE THE PUBLISHED IDENTIFIER IS DISCOVERED RATHER THAN
// CONSTRUCTED. The system publishes our voice as the extension's bundle id
// followed by the one the audio unit declared, so the published string never
// equals what the unit said (spec 0041, A1) -- matching by SUFFIX against this
// list yields the identifier the system actually used, which is the one that has
// to be written into the preference.

public protocol PublishedVoices: AnyObject {
	func identifiers() -> [String]
}
