// Mirrors Sources/VoiceOverBridgeDomain/Entities/LocalSocketPath.swift.
//
// THESE ARE CONTRACT ASSERTIONS, NOT UNIT ASSERTIONS. Every expectation below is
// the rule published in specs/wire/v1/protocol.md §1 and implemented a second
// time in the server's local_socket.go: the two halves must derive the same path
// from the same name or they never meet, and the failure mode is a refused
// connection on a machine where the bridge is plainly running. So the values are
// spelled out literally rather than computed -- a test that derived them the way
// the code does would agree with any drift.

import Testing

@testable import VoiceOverBridgeDomain

@Suite("LocalSocketPath")
struct LocalSocketPathTests {
	@Test("XDG_RUNTIME_DIR wins, and the directory is the product's name")
	func runtimeDirectoryWins() throws {
		let dirs = LocalSocketDirs(runtimeDir: "/run/user/501", home: "/Users/someone")
		#expect(try LocalSocketPath.directory(in: dirs) == "/run/user/501/screenreader-mcp")
	}

	@Test("with no runtime directory it is a dot-directory in the home directory")
	func homeIsTheFallback() throws {
		let dirs = LocalSocketDirs(runtimeDir: "", home: "/Users/someone")
		#expect(try LocalSocketPath.directory(in: dirs) == "/Users/someone/.screenreader-mcp")
	}

	@Test("with neither, it says so rather than guessing a directory")
	func nowhereToListen() {
		let dirs = LocalSocketDirs(runtimeDir: "", home: "")
		#expect(throws: LocalSocketPathError.self) {
			try LocalSocketPath.directory(in: dirs)
		}
	}

	@Test("a bare name becomes <dir>/<name>.sock -- the path the server dials")
	func bareNameIsDerived() throws {
		let dirs = LocalSocketDirs(runtimeDir: "", home: "/Users/someone")
		let path = try LocalSocketPath.path(for: "voiceoverMcpBridge", in: dirs)
		#expect(path == "/Users/someone/.screenreader-mcp/voiceoverMcpBridge.sock")
	}

	@Test("an address that is already a path is used verbatim -- the deliberate override")
	func aPathIsHonoured() throws {
		let dirs = LocalSocketDirs(runtimeDir: "/run/user/501", home: "/Users/someone")
		let path = try LocalSocketPath.path(for: "/tmp/mine.sock", in: dirs)
		#expect(path == "/tmp/mine.sock")
	}

	@Test("a path is recognised by its separator, and an empty address is not a name")
	func bareNameRecognition() {
		#expect(LocalSocketPath.isBareName("voiceoverMcpBridge"))
		#expect(!LocalSocketPath.isBareName("/tmp/mine.sock"))
		#expect(!LocalSocketPath.isBareName("dir\\mine"))
		#expect(!LocalSocketPath.isBareName(""))
	}

	@Test("a path over 103 bytes is refused where it can still be explained")
	func theLimitIsChecked() {
		let dirs = LocalSocketDirs(runtimeDir: "", home: "/Users/" + String(repeating: "x", count: 90))
		#expect(throws: LocalSocketPathError.self) {
			try LocalSocketPath.path(for: "voiceoverMcpBridge", in: dirs)
		}
	}

	@Test("the limit counts BYTES, not characters")
	func theLimitCountsBytes() throws {
		// Each of these costs two bytes in UTF-8, so a name that fits as characters
		// does not fit as a path. The kernel counts bytes and answers `invalid
		// argument`, naming neither the limit nor the path.
		let home = "/Users/" + String(repeating: "é", count: 45)
		let dirs = LocalSocketDirs(runtimeDir: "", home: home)
		#expect(home.count < LocalSocketPath.maxBytes)
		#expect(throws: LocalSocketPathError.self) {
			try LocalSocketPath.path(for: "bridge", in: dirs)
		}
	}

	@Test("a socket file names the endpoint it stands for, and nothing else does")
	func theInverse() {
		#expect(LocalSocketPath.name(ofFile: "voiceoverMcpBridge.sock") == "voiceoverMcpBridge")
		#expect(LocalSocketPath.name(ofFile: "notes.txt") == nil)
		#expect(LocalSocketPath.name(ofFile: ".sock") == nil)
	}

	@Test("the failure names the address the user wrote, not the derived path alone")
	func theFailureIsDiagnosable() {
		let dirs = LocalSocketDirs(runtimeDir: "", home: "/Users/" + String(repeating: "x", count: 90))
		do {
			_ = try LocalSocketPath.path(for: "voiceoverMcpBridge", in: dirs)
			Issue.record("expected the length check to refuse this path")
		} catch let error as LocalSocketPathError {
			#expect(error.description.contains("voiceoverMcpBridge"))
			#expect(error.description.contains("103"))
		} catch {
			Issue.record("unexpected error: \(error)")
		}
	}
}
