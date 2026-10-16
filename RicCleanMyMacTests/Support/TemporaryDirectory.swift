import Foundation

/// A folder on disk that a test owns, removed with `remove()`.
///
/// Folders to scan are created under `/tmp`: the system temporary folder
/// (`/private/var/folders`) is skipped by `ScanPolicy`, so a scan there would
/// find nothing. Caches and other files that are never scanned can use
/// `inSystemTemporaryFolder`.
struct TemporaryDirectory {
    let url: URL

    /// A new empty folder under `/tmp`, which `ScanPolicy` scans normally.
    static func scannable() throws -> TemporaryDirectory {
        try TemporaryDirectory(parent: URL(fileURLWithPath: "/tmp"))
    }

    /// A new empty folder in the system temporary folder.
    static func inSystemTemporaryFolder() throws -> TemporaryDirectory {
        try TemporaryDirectory(parent: FileManager.default.temporaryDirectory)
    }

    private init(parent: URL) throws {
        url = parent.appendingPathComponent("RicCleanMyMacTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    /// Writes `byteCount` bytes at `relativePath`, creating the folders on the way.
    @discardableResult
    func createFile(_ relativePath: String, byteCount: Int) throws -> URL {
        let fileURL = url.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data(repeating: 1, count: byteCount).write(to: fileURL)
        return fileURL
    }

    /// Creates an empty folder at `relativePath`.
    @discardableResult
    func createFolder(_ relativePath: String) throws -> URL {
        let folderURL = url.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        return folderURL
    }

    /// Deletes the folder and everything in it, restoring permissions first
    /// so folders a test locked can be removed.
    func remove() {
        let fileManager = FileManager.default
        if let enumerator = fileManager.enumerator(atPath: url.path) {
            for case let relativePath as String in enumerator {
                try? fileManager.setAttributes(
                    [.posixPermissions: 0o755],
                    ofItemAtPath: url.appendingPathComponent(relativePath).path
                )
            }
        }
        try? fileManager.removeItem(at: url)
    }
}
