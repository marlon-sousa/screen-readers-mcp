// ROLE: entity -- the derivation from an endpoint's bare NAME to the socket path
// this bridge listens on, and the length limit that path must respect.
//
// Pure: it touches no environment and no filesystem. The caller reads the two
// directories and passes them in as values, which is why this compiles and is
// tested with no socket anywhere near it.
//
// IT IS THE DELIBERATE MIRROR OF THE SERVER'S local_socket.go, and the mirroring
// is the point: the server dials what this bridge binds, so both halves must
// compute the same path or never meet. That is why the rule is published in
// specs/wire/v1 §1 rather than agreed between two implementations, why both
// sides compute it in tested domain code, and why neither reads the environment
// to do it. A drift here does not fail loudly -- it fails as "connection
// refused" on a machine where the bridge is plainly running.
//
// WHY THIS IS DOMAIN AND THE WINDOWS SPELLING IS NOT: the `\\.\pipe\` prefix is
// a constant and decides nothing. This is a derivation -- an environment
// variable with a fallback, a directory, a suffix, an override case and a limit
// -- and it is the RENDEZVOUS. Contract is what an entity is for.

/// The directories the derivation needs, read by the caller.
///
/// A DTO in the file of the rule that owns it. The listener leaf fills it from
/// the process environment and the home directory, and nothing in here knows
/// those exist.
public struct LocalSocketDirs: Equatable, Sendable {
	/// `$XDG_RUNTIME_DIR`, or empty when unset. macOS sets it for nobody, so in
	/// practice the home directory answers here -- but the variable is honoured
	/// because the server honours it, and a user who sets it means it.
	public let runtimeDir: String

	/// The user's home directory, or empty when it cannot be determined.
	public let home: String

	public init(runtimeDir: String, home: String) {
		self.runtimeDir = runtimeDir
		self.home = home
	}
}

/// Why a name could not be turned into a path a socket can be bound to.
public struct LocalSocketPathError: Error, Equatable, CustomStringConvertible {
	public let description: String

	public init(_ description: String) {
		self.description = description
	}
}

public enum LocalSocketPath {
	/// How many bytes of a Unix socket path the kernel will look at, minus the
	/// terminating NUL.
	///
	/// 104 on darwin and 108 on Linux, so the smaller wins and a path this bridge
	/// accepts is dialable on every POSIX host the contract targets. It is
	/// checked at all because the kernel's own answer to a longer path is
	/// `invalid argument`, which names neither the limit, nor the path, nor the
	/// fix.
	public static let maxBytes = 103

	/// The directory a POSIX bridge's sockets live in. Its name is the PRODUCT's,
	/// not a reader's: several bridges may listen on one machine.
	static let directoryName = "screenreader-mcp"

	/// What makes a socket file recognisable in a directory that is not otherwise
	/// ours to interpret, and what a listing trims back off so both platforms
	/// answer in bare names.
	static let suffix = ".sock"

	/// Whether `address` is a bare name rather than a path written out.
	///
	/// The same test the server makes, spelled the same way: anything with a
	/// separator in it is a path the user meant literally.
	public static func isBareName(_ address: String) -> Bool {
		!address.isEmpty && !address.contains("/") && !address.contains("\\")
	}

	/// Where this user's sockets live.
	///
	/// `$XDG_RUNTIME_DIR/screenreader-mcp` when that is set, else
	/// `~/.screenreader-mcp`. The directory is mode 0700, and that is where the
	/// "only this user" property comes from -- but creating it that way is the
	/// LISTENER's obligation (protocol.md §1), not this rule's.
	///
	/// `$TMPDIR` was rejected by spec 0044: on macOS it is a generated per-user
	/// path 49 bytes long, which spends half the budget above before the first
	/// meaningful character.
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

	/// Where the endpoint addressed `address` listens.
	///
	/// A bare NAME is derived; an address that is already a path is used
	/// verbatim, which is the override spec 0044 keeps -- what would fork the
	/// shipped defaults per host is a path in the DEFAULTS, not a path being
	/// expressible at all.
	public static func path(for address: String, in dirs: LocalSocketDirs) throws -> String {
		var path = address
		if isBareName(address) {
			path = join(try directory(in: dirs), address + suffix)
		}
		// Measured in UTF-8 bytes, not characters: the kernel counts bytes, and a
		// name with an accent in it costs more than it looks.
		let byteCount = path.utf8.count
		if byteCount > maxBytes {
			throw LocalSocketPathError(
				"local endpoint '\(address)': its socket path \(path) is \(byteCount) bytes, "
					+ "over the \(maxBytes) a unix socket allows"
			)
		}
		return path
	}

	/// The endpoint name a socket file stands for, and whether it is one of ours
	/// at all. The inverse of the derivation, and what lets both platforms answer
	/// a listing in the same vocabulary.
	public static func name(ofFile fileName: String) -> String? {
		guard fileName.hasSuffix(suffix) else { return nil }
		let name = String(fileName.dropLast(suffix.count))
		return name.isEmpty ? nil : name
	}

	/// Joining, spelled out rather than taken from Foundation's URL machinery:
	/// this is a POSIX path and the one edge case is a trailing separator.
	static func join(_ head: String, _ tail: String) -> String {
		head.hasSuffix("/") ? head + tail : head + "/" + tail
	}
}
