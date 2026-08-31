// ROLE: adapter seam -- may this process read another application's
// accessibility tree?
//
// NOT A DOMAIN PORT, AND THE DIFFERENCE IS THE WHOLE REASON THIS FILE EXISTS.
// `PermissionBroker` is the domain's port for permissions and it is the right
// shape for what the domain does with them: 13.8's TypeText controller checks
// one and then REQUESTS it, which is a decision about a human's machine and
// belongs in a controller. Focus asks a narrower question for a different
// purpose -- it picks a ROUTE -- and a route choice is a decision that belongs
// in the upper adapter, beside the two routes it chooses between. So the
// question is asked here, at the layer that acts on the answer, and
// `VoiceOverFocusInspector` holds only adapter seams exactly as
// `VoiceOverGestureSender` does.
//
// IMPLEMENTED BY: TCCPermissionBroker -- ONE LEAF, TWO INTERFACES AT TWO LAYERS.
// The class that answers the domain's `PermissionBroker` also answers this, so
// there is one place in the bridge that talks to the permission machinery and no
// second reading of `AXIsProcessTrusted` anywhere. Also by
// FakeAccessibilityTrust (Tests/Fakes).
// USED BY: VoiceOverFocusInspector.
//
// THE ALTERNATIVE, AND WHY IT WAS NOT TAKEN: `focusInfo(accessibilityGranted:)`
// on the domain port, with the GetFocusInfo controller reading the broker's
// `status` and passing the answer down -- which is the shape 13.7 and 13.8 both
// arrived at for `ReaderLiveness` and `PermissionBroker`. It adds no interface,
// and it puts a macOS permission fact into a port signature that lane 1's
// identical port does not have, teaches the domain that focus has two routes,
// and moves a decision out of the adapter that spec 0046 says holds "all the
// decisions". Recorded as an amendment in spec 0046's 13.9 section.
//
// IT ASKS NOBODY ANYTHING. This is `AXIsProcessTrusted` with no options: no
// dialog, no consent prompt, no entry added to any list. Every call to
// `PermissionBroker.request` in this repository is in a command handler that is
// about to post a system event -- a `typeText`, or a keystroke `pressGesture` --
// and nothing here may join them. A route CHOICE that could raise a consent
// dialog is the whole thing this seam exists to prevent: focus does not move the
// machine, so it must not be able to cost the person a decision.

public protocol AccessibilityTrust: AnyObject {
	/// Whether this process is trusted to use the accessibility API.
	///
	/// Not `throws` and not optional: the system answers a Bool, so "not yet
	/// asked" and "asked and refused" are one observable here -- the same reason
	/// `PermissionState` has two cases and not three.
	func isTrusted() -> Bool
}
