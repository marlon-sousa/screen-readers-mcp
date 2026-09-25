// ROLE: adapter seam for a raw byte pipe, and the signal that its poll window elapsed.
// USED BY: JsonLinesChannel.
// IMPLEMENTED BY: SocketTransport and FakeTransport.

import Foundation

/// Not a failure: it hands control back so the caller can check deadlines or notice it was asked to stop.
public struct PollTimeout: Error {
	public init() {}
}

public protocol Transport: AnyObject {
	/// The next chunk; empty at end of stream, and `PollTimeout` when idle.
	func receive() throws -> Data

	func sendAll(_ data: Data) throws

	func close()
}
