import Foundation
import Testing
@testable import RicCleanMyMac

@Suite("ScanCacheSerializer")
struct ScanCacheSerializerTests {
    private func result(root: FileNode) -> DirectoryScanResult {
        DirectoryScanResult(root: root, totalFiles: 1, totalDirectories: 1, scanDuration: 0, scanDate: Date())
    }

    /// A chain of `depth` folders with one file at the bottom.
    private func nestedResult(depth: Int) -> DirectoryScanResult {
        var node = FileNode.file(name: "leaf", size: 1)
        for level in 0..<depth {
            node = FileNode.directory(name: "level\(level)", children: [node])
        }
        return result(root: node)
    }

    @Test("A written tree reads back with names, sizes and statuses")
    func roundTrip() throws {
        let tree = FileNode.directory(name: "/Users/test", children: [
            FileNode.file(name: "a.txt", size: 42),
            FileNode.directory(name: "Library", children: [], status: .readOnly),
            FileNode.skippedDirectory(name: "Other", reason: "Other user"),
            FileNode.inaccessibleDirectory(name: "locked")
        ])

        let data = try ScanCacheSerializer.write(result(root: tree))
        let root = try ScanCacheSerializer.read(from: data).root

        #expect(root.name == "/Users/test")
        #expect(root.size == 42)
        #expect(root.descendant(at: "a.txt")?.size == 42)
        #expect(root.descendant(at: "Library")?.status == .readOnly)
        #expect(root.descendant(at: "Other")?.status == .skipped(reason: "Other user"))
        #expect(root.descendant(at: "locked")?.status == .inaccessible)
        #expect(root.containsProtectedItems)
    }

    @Test("A normally nested tree is read")
    func normalDepthIsRead() throws {
        let data = try ScanCacheSerializer.write(nestedResult(depth: 200))

        #expect(throws: Never.self) { try ScanCacheSerializer.read(from: data) }
    }

    @Test("A tree deeper than the limit is rejected")
    func tooDeepIsRejected() throws {
        let data = try ScanCacheSerializer.write(nestedResult(depth: 1100))

        let error = #expect(throws: ScanCacheError.self) { try ScanCacheSerializer.read(from: data) }
        guard case .tooDeep = error else {
            Issue.record("Expected tooDeep, got \(String(describing: error))")
            return
        }
    }

    @Test("Data that is not a cache is rejected")
    func garbageIsRejected() {
        #expect(throws: ScanCacheError.self) { try ScanCacheSerializer.read(from: Data("not a cache".utf8)) }
    }
}
