# VoiceOver capture spike

The instrument for [spec 0041](../../specs/0041-can-voiceover-say-what-it-said.md).
**It is throwaway.** It adds no production class, follows none of the repo's
ports-and-adapters rules, and is deleted once the direction RFC is written
against its Findings.

It is versioned anyway, for the reason the 2026-08-22 fixture incident
established: a measurement nobody else can re-run is weaker than it looks. Every
number in that spec's Findings section came from something in this directory.

## What is here

| Path | What it is |
|---|---|
| `VoiceOver.sdef` | VoiceOver's AppleScript dictionary, dumped with `sdef /System/Library/CoreServices/VoiceOver.app` on macOS 15.0. The reference this repo otherwise does not have. |
| `provider/build.sh` | Builds a speech synthesis provider — a container app plus an `.appex` — with `swiftc` and `codesign`, no Xcode project. |
| `provider/Sources/Voice/` | The audio unit and its factory: the thing macOS hands every utterance to, as SSML, before any audio exists. |
| `provider/Sources/Stub/` | The extension executable. A stub, because the unit lives in a framework. |
| `provider/Sources/Probe/` | A client that lists voices, speaks through ours, and enumerates speech audio components — so "the extension never ran" and "VoiceOver ignored it" stay separable. |

`provider/build/` is generated and git-ignored.

## Running it

```sh
cd provider
./build.sh --sandbox                 # the configuration that works
./build/probe list                   # is our voice published?
```

Registration is two steps, and the first alone is not enough:

```sh
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$PWD/build/VoiceOverCaptureSpike.app"
pluginkit -a "$PWD/build/VoiceOverCaptureSpike.app/Contents/PlugIns/CaptureVoice.appex"
```

The system then re-reads voices on its own schedule — roughly every 30 seconds —
so the voice appears a little after the command returns, not immediately.

## The flags exist to reproduce failures

Two build flags produce configurations that are **known not to work**. They are
kept because a negative result that cannot be re-run is not a result:

- `--network` adds `com.apple.security.network.client`, and macOS then refuses to
  publish the voice, logging `Skipping network entitled extension`.
- `--in-process` adds `AudioComponentBundle`, and the voice stops working
  entirely.

Build with neither for the working configuration.

## Watching what the extension sees

Two routes, both live, because the sandbox makes one of them the question:

```sh
log stream --predicate 'subsystem == "voiceover-capture-spike"' --style compact
tail -f ~/Library/Containers/org.screen-readers-mcp.spike.capture.voice/Data/voiceover-capture-spike.jsonl
```

When diagnosing why a voice does not appear, the useful log is not ours:

```sh
log show --last 5m --predicate 'category == "AXTTSCommon"' --style compact
log show --last 5m --predicate 'process == "pkd"' --style compact
```

Both silent rejections found so far were visible only there.

## Removing it

```sh
pluginkit -r "$PWD/build/VoiceOverCaptureSpike.app/Contents/PlugIns/CaptureVoice.appex"
rm -rf build
```

If VoiceOver has been pointed at this voice, **change the voice back in
VoiceOver Utility first** — there is no known scripted way to restore it (spec
0041, C3), and removing a voice that is in use is how a machine ends up silent.
