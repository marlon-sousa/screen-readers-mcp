// ROLE: entity, the derivation from an endpoint's bare name to the socket path this bridge
// listens on, and that path's length limit.
// Mirrors the server's local_socket.go: both must compute the same path, and a drift fails only
// as "connection refused".

public struct LocalSocketDirs: Equatable, Sendable {
	/// `$XDG_RUNTIME_DIR`, or empty when unset; macOS does not set it, so the home directory usually
	/// answers.
	public let runtimeDir: String

	/// The user's home directory, or empty when it cannot be determined.
	public let home: String

	public init(runtimeDir: String, home: String) {
		self.runtimeDir = runtimeDir
		self.home = home
	}
}

public struct LocalSocketPathError: Error, Equatable, CustomStringConvertible {
	public let description: String

	public init(_ description: String) {
		self.description = description
	}
}

public enum LocalSocketPath {
	/// Unix socket path bytes the kernel reads, minus the NUL: 104 on Darwin and 108 on Linux, so the
	/// smaller wins. The kernel's own error for a longer path is a bare `invalid argument`.
	public static let maxBytes = 103

	/// Named for the product, not a reader: several bridges may listen on one machine.
	static let directoryName = "screenreader-mcp"

	static let suffix = ".sock"

	/// Anything with a separator is a path the user meant literally, as the server decides.
	public static func isBareName(_ address: String) -> Bool {
		!address.isEmpty && !address.contains("/") && !address.contains("\\")
	}

	/// `$XDG_RUNTIME_DIR/screenreader-mcp`, else `~/.screenreader-mcp`; the listener must create it with
	/// mode 0700.
	/// Not `$TMPDIR`: on macOS it is a generated per-user path 49 bytes long.
	public static func directory(in dirs: LocalSocketDirs) throws -> String {
		if !dirs.runtimeDir.isEmpty {
			return join(dirs.runtimeDir, directoryName)
		}
		if !dirs.home.isEmpty {
			return join(dirs.home, "." + directoryName)
		}
		throw LocalSocketPathError(
			"local endpoint: neither XDG_RUNTIME_DIR nor a home directory is known, so there is nowhere to listen"
		)
	}

	/// A bare name is derived; an address that is already a path is used verbatim.
	public static func path(for address: String, in dirs: LocalSocketDirs) throws -> String {
		var path = address
		if isBareName(address) {
			path = join(try directory(in: dirs), address + suffix)
		}
		// UTF-8 bytes, not characters: the kernel counts bytes.
		let byteCount = path.utf8.count
		if byteCount > maxBytes {
			throw LocalSocketPathError(
				"local endpoint '\(address)': its socket path \(path) is \(byteCount) bytes, "
					+ "over the \(maxBytes) a unix socket allows"
			)
		}
		return path
	}

	/// The endpoint name a socket file stands for, or nil when it is not one of ours.
	public static func name(ofFile fileName: String) -> String? {
		guard fileName.hasSuffix(suffix) else { return nil }
		let name = String(fileName.dropLast(suffix.count))
		return name.isEmpty ? nil : name
	}

	static func join(_ head: String, _ tail: String) -> String {
		head.hasSuffix("/") ? head + tail : head + "/" + tail
	}
}
