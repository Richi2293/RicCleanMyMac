import Foundation
@testable import RicCleanMyMac

extension FileNode {
    /// The descendant at `relativePath` (names separated by "/"), or `nil`.
    func descendant(at relativePath: String) -> FileNode? {
        var current: FileNode? = self
        for name in relativePath.split(separator: "/") {
            current = current?.children?.first { $0.name == String(name) }
        }
        return current
    }
}

struct TimeoutError: Error {}

/// Polls `condition` until it is true, for work that reports its end through
/// published state (a scan, a cache load). Throws after `timeout` seconds.
@MainActor
func waitUntil(timeout: TimeInterval = 10, _ condition: () -> Bool) async throws {
    let deadline = Date().addingTimeInterval(timeout)
    while !condition() {
        guard Date() < deadline else { throw TimeoutError() }
        try await Task.sleep(nanoseconds: 20_000_000)
    }
}
