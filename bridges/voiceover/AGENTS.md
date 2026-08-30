# bridges/voiceover/ — the macOS VoiceOver bridge

The manual for this package. The repo-wide manual is the root
[`AGENTS.md`](../../AGENTS.md) — the four-role vocabulary (port / controller /
entity / adapter), the hard invariants, the workflow and the task list all live
there and are not repeated here. This file is what is specific to the Swift half:
how the repo's rules render in Swift, what the module graph enforces, and the
macOS traps that have already cost time.

`bridges/voiceover/` is one Swift `.app` ([spec
0043](../../specs/0043-the-voiceover-bridge-is-one-swift-bundle.md), Decided).
Its class-by-class layout is [spec
0046](../../specs/0046-the-voiceover-bridge-class-by-class.md); the board entries
are lane 3 in [`ROADMAP.md`](../../ROADMAP.md). What each directory holds, how to
build it, and how to register and remove the capture voice are in
[`README.md`](README.md) beside this file — that is the document for *using* this
bridge, and this is the document for *changing* it.

## It is one bundle and FIVE elements, not one program

Spec 0046 part 3 names them, and the decomposition is wrong if it pretends
otherwise: the speech provider (its own `.appex` process, **and** dlopened into
every client that speaks, VoiceOver included), provider registration, the bridge
session (a background thread of the app), the input path (posting system events,
needing an Accessibility grant), and the control UI (AppKit's main thread).

Two consequences bind every change here:

- **`CaptureVoice` depends on nothing of ours, and that is a hard rule.** Every
  byte it carries runs inside the user's screen reader — the same argument that
  makes the shared wire module stdlib-only, reached from the other direction. It
  never imports the domain, the wire binding, or anything that would grow a
  dependency later. Its tests keep their own `Fakes/` for the same reason.
- **The session runs on a background thread; AppKit owns the main one.** Every UI
  update the session causes marshals to the main thread, and no call the UI makes
  may block it. This is the macOS rendering of the NVDA main-thread rule, and it
  is the same class of bug.

## The module graph is the architecture test

`Package.swift`'s dependency edges are load-bearing, not descriptive: a domain
file that imports `VoiceOverBridgeAdapters` **does not compile**. Lane 1 enforces
the same rule by convention and review; Swift enforces it at build time and costs
nothing for the privilege, so `swift test` (which builds every target) is also
the architecture check.

**`Package.swift` is not the build.** SwiftPM cannot emit `.app` or `.appex`
bundles, so `build.sh` assembles them from swiftc output. A change to what ships
is a change to `build.sh`; a change to what compiles and is tested is a change to
the manifest. Both, usually.

## Swift renderings of the repo's rules

- **One class per file, and no re-export facades.** The file half holds. The
  import half cannot: Swift imports modules, not files, so "every import names its
  file" is not a property Swift offers. The compensating rule is that **no file
  may exist whose purpose is a `typealias` re-export** — and for the wire binding
  that rule is enforced, by `scripts/drift.py --swift`.
- **Fakes conform to their port**, one file per fake, mirroring the port's file.
  A fake that forgets a method fails to **compile**, where Python's ABC fails at
  construction: strictly stronger, same guarantee.
- **A port that can fail says `throws`; the session guards exactly those.** Lane 1
  wraps every teardown step in a blanket guard because a Python port that raises
  looks like one that does not. Here the claim is checkable, so it is made in the
  type: `SessionSignals`' cues throw (a cue reaches an audio device that may be
  gone, and a courtesy is never worth a session), while `Transcript` and
  `MessageChannel.close` promise that they swallow their own IO failures. A
  `try/catch` around one of those would be catching nothing — if you add one, one
  of the two is wrong.
- **Ports are protocols, and binding is chosen per call site.** Separating a
  component costs nothing at run time; only *binding* can. The one place that
  constrains is the capture voice's render block, which must not allocate, must
  not block on a lock, and must not bind through an existential — it captures a
  concrete `final` `AudioRing` for exactly that reason. Everywhere else a port is
  free to be a protocol.

## The capability set grows ONE ENTRY AT A TIME

`hello` announces what this build actually implements, and nothing else.
`Registry.capabilities` is empty at 13.4 and each later entry adds its own
alongside the handlers that serve it. Announcing a capability before the entry
that implements it produces the one failure the capability gate exists to
prevent: a tool the agent can see, call, and get nothing from.

The same rule is why **`VoiceOverAdapterFactory` refuses a silent session until
13.6**. `silent` is not a preference, it is a promise about a human's ears — the
reader keeps talking, the human hears nothing, the agent reads what was said —
and a bridge that cannot keep any part of it must refuse rather than establish a
session that means something else. When you make the promise keepable, delete the
refusal and its named test in the same commit.

## The endpoint, and why the derivation is duplicated on purpose

The bridge **listens**; the server dials
([`specs/wire/v1/protocol.md`](../../specs/wire/v1/protocol.md) §1). The default
is the local endpoint, addressed by the bare name `voiceoverMcpBridge`, which
resolves here to a Unix domain socket under `$XDG_RUNTIME_DIR` or `~`.

`Entities/LocalSocketPath.swift` deliberately mirrors the server's
`server/domain/entities/local_socket.go`. **Both halves must derive the same path
from the same published rule or they never meet**, and the failure mode is a
refused connection on a machine where the bridge is plainly running. So the rule
lives in the published contract, both sides compute it in tested domain code, and
neither reads the environment to do it — the caller passes the values in.
`LocalSocketListener` holds §1's three listener obligations (directory mode
`0700`, unlink before binding, unlink on exit) because their **order** is the
contract.

## Two executables exist that the bundle does not ship

`CaptureProbe` answers *"is the capture voice published?"* without a human
squinting at a settings pane, and `BridgeListener` starts the bridge listening
from a terminal. Neither is copied by `build.sh`. They are in the repo for one
reason: **anything a check depends on is versioned, in the same PR as the
check** — the 2026-08-22 rule — and both answer a question no unit test can.
Keep them thin. Every decision `BridgeListener` makes is a flag read into a
`BridgeConfig`; the graph is `Wiring`'s, and logic that starts accumulating there
belongs in `Wiring` or in the dialog.

## Tests

The root manual's rules apply unchanged: `Tests/` mirrors `Sources/` file for
file, one test module per source module, and a source file with no test file is a
deliberate statement (ports, and leaves that make no decisions). The lane's own
shapes:

- **swift-testing** (`import Testing`), decided for the lane at 13.4.
- **`Tests/Fakes/` is a shared target** — the domain's tests, the adapters' tests
  and the integration scenarios all need the same doubles, and three copies of a
  stateful fake is three chances for one to drift into agreeing with the code
  instead of with the port. `Support/` inside it is scaffolding that stands in for
  no port, which is lane 1's `tests/support/` in the one form Swift allows.
- **`Tests/Integration/`** holds headless scenarios that drive the real stack,
  including over **real** sockets dialled by a client built from the raw socket
  API — a round trip proven with our own code on both ends would not prove the
  endpoint is dialable. They bind in a home directory they invent under `/tmp`, so
  they never touch the endpoint a developer's own bridge listens on. Live-VoiceOver
  scenarios are **not** here: they live behind the bridge's `live` tier and never
  run in CI.
- **No test compares reader strings.** VoiceOver renders under the tester's own
  locale — the maintainer's machine speaks Portuguese — so structure is compared
  and text never is. That is
  [`scripts/live_pages/README.md`](../../scripts/live_pages/README.md)'s rule in
  its macOS instance.

## Gotchas learned the hard way

- **macOS filesystems are case-insensitive by default, so two source files whose
  names differ only in case are ONE file to the build.** `Ports/TcpBinder.swift`
  beside `TCPBinder.swift` compiled, and one object file silently overwrote the
  other; the failure arrived as *"undefined protocol descriptor"* at link time,
  naming nothing that would lead you back. Measured on 2026-08-30. A type may
  differ from another only in case; a **file** may not.
- **Searching outside the repo needs `-a`.** macOS's interesting files are binary
  plists, and both `grep` and ripgrep report *absence* rather than saying they
  declined to look. Ripgrep's version is worse because it looks safe: `rg -l` on a
  **named** binary file matches, while `rg -l` **walking a directory** does not.
  The root manual carries the measurement; it cost an evening here.
- **When a value must exist but cannot be found, compare states instead of
  searching for strings** — checksum the candidate tree with the value set to A,
  to B, and back to A. See
  [`docs/how-we-found-the-voice-store.md`](../../docs/how-we-found-the-voice-store.md).
- **The bundle identity is frozen**, and `README.md` says why: the voice
  identifier VoiceOver stores is derived from the extension's bundle id, so
  renaming costs every user a trip to VoiceOver Utility to re-select a voice that
  silently vanished. 13.11 owns identifiers and is where that is paid once.
- **Three findings are built into `build.sh`, each of which failed silently when
  it was wrong**: a speech provider must be sandboxed, must **not** hold
  `com.apple.security.network.client` (which is why the bridge reads a file rather
  than a socket from the extension), and must not declare `AudioComponentBundle`.
  [Spec 0041](../../specs/0041-can-voiceover-say-what-it-said.md) A1 has the
  measurements.
- **VoiceOver crashes on the maintainer's machine as routine weather**, so lane
  3's live checklists measure the crash census from two independent sources and
  every check is independently re-runnable from a cold start. Spec 0046 part 1(c).
