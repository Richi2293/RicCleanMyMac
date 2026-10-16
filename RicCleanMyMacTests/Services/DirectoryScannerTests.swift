import Foundation
import Testing
@testable import RicCleanMyMac

@Suite("DirectoryScanner deletion rules")
struct DirectoryScannerDeletionRulesTests {
    private let home = FileManager.default.homeDirectoryForCurrentUser

    @Test("The home folder and its ancestors cannot be deleted")
    func homeAndAncestorsAreProtected() {
        let documents = FileNode.directory(name: "Documents", children: [FileNode.file(name: "a.txt", size: 5)])
        let homeNode = FileNode.directory(name: home.lastPathComponent, children: [documents])
        let users = FileNode.directory(name: "Users", children: [homeNode])
        let root = FileNode.directory(name: "/", children: [users])
        let scanner = DirectoryScanner(cacheDirectory: nil)

        #expect(!scanner.isNodeDeletable(homeNode))
        #expect(!scanner.isNodeDeletable(users))
        #expect(scanner.isNodeDeletable(documents))
        withExtendedLifetime(root) {}
    }

    @Test("~/Library/Caches stays in place, its contents can be deleted")
    func libraryCachesKeepsTheFolder() {
        let cacheFile = FileNode.file(name: "blob", size: 10)
        let appCache = FileNode.directory(name: "com.example", children: [cacheFile])
        let caches = FileNode.directory(name: "Caches", children: [appCache])
        let library = FileNode.directory(name: "Library", children: [caches], status: .readOnly)
        let homeNode = FileNode.directory(name: home.path, children: [library])
        let scanner = DirectoryScanner(cacheDirectory: nil)

        #expect(!scanner.isNodeDeletable(caches))
        #expect(scanner.isNodeDeletable(appCache))
        #expect(scanner.isNodeDeletable(cacheFile))
        withExtendedLifetime(homeNode) {}
    }
}

/// Scans real folders created for the test. Each test uses its own folders
/// and its own cache folder, so the app's caches are never touched. Tests
/// wait for the scanner's background cache save before returning: otherwise
/// the save could recreate the cache folder after `remove()`.
@Suite("DirectoryScanner on disk", .serialized)
struct DirectoryScannerDiskTests {
    @Test("A scan measures allocated sizes, counts hard links once and marks unreadable folders")
    func scanMeasuresTheTree() async throws {
        let folder = try TemporaryDirectory.scannable()
        let cache = try TemporaryDirectory.inSystemTemporaryFolder()
        defer { folder.remove(); cache.remove() }

        let original = try folder.createFile("links/original", byteCount: 1_000_000)
        try FileManager.default.linkItem(at: original, to: folder.url.appendingPathComponent("links/hardlink"))
        let locked = try folder.createFolder("locked")
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: locked.path)

        let scanner = DirectoryScanner(cacheDirectory: cache.url)
        scanner.scan(rootPath: folder.url.path)
        try await waitUntil { !scanner.isScanning }

        let root = try #require(scanner.scanResult?.root)
        let linkSizes = try #require(root.descendant(at: "links")?.children).map(\.size).sorted()
        #expect(linkSizes.first == 0)
        #expect((linkSizes.last ?? 0) >= 1_000_000)
        #expect(root.descendant(at: "locked")?.status == .inaccessible)
        #expect(root.containsProtectedItems)
        await scanner.waitForBackgroundWork()
    }

    @Test("Deleting a file removes it from disk, from the tree and from the saved cache")
    func deletionUpdatesDiskTreeAndCache() async throws {
        let folder = try TemporaryDirectory.scannable()
        let cache = try TemporaryDirectory.inSystemTemporaryFolder()
        defer { folder.remove(); cache.remove() }

        let doomed = try folder.createFile("a/doomed", byteCount: 8192)
        try folder.createFile("a/kept", byteCount: 4096)

        let scanner = DirectoryScanner(cacheDirectory: cache.url)
        scanner.deleteMode = .permanent
        scanner.scan(rootPath: folder.url.path)
        try await waitUntil { !scanner.isScanning }

        let node = try #require(scanner.scanResult?.root.descendant(at: "a/doomed"))
        let revisionBefore = scanner.treeRevision
        let deletion = await scanner.deleteSingleItem(node)

        #expect(deletion?.successCount == 1)
        #expect(!FileManager.default.fileExists(atPath: doomed.path))
        #expect(scanner.scanResult?.root.descendant(at: "a/doomed") == nil)
        #expect(scanner.treeRevision == revisionBefore + 1)

        // The cache load waits for the save queued by the deletion.
        scanner.loadCachedResult(forRootPath: folder.url.path)
        try await waitUntil { !scanner.isLoadingCache }

        let reloaded = try #require(scanner.scanResult?.root)
        #expect(reloaded.descendant(at: "a/kept") != nil)
        #expect(reloaded.descendant(at: "a/doomed") == nil)
        let cacheFiles = try FileManager.default.contentsOfDirectory(atPath: cache.url.path)
        #expect(cacheFiles.count == 1)
    }

    @Test("Only one deletion runs at a time")
    func secondDeletionIsRefused() async throws {
        let folder = try TemporaryDirectory.scannable()
        let cache = try TemporaryDirectory.inSystemTemporaryFolder()
        defer { folder.remove(); cache.remove() }

        try folder.createFile("first", byteCount: 10)
        try folder.createFile("second", byteCount: 10)

        let scanner = DirectoryScanner(cacheDirectory: cache.url)
        scanner.deleteMode = .permanent
        scanner.scan(rootPath: folder.url.path)
        try await waitUntil { !scanner.isScanning }

        let root = try #require(scanner.scanResult?.root)
        let first = try #require(root.descendant(at: "first"))
        let second = try #require(root.descendant(at: "second"))
        async let firstResult = scanner.deleteSingleItem(first)
        async let secondResult = scanner.deleteSingleItem(second)
        let results = await [firstResult, secondResult]

        #expect(results.filter { $0 == nil }.count == 1)
        #expect(!scanner.isDeleting)
        await scanner.waitForBackgroundWork()
    }
}
