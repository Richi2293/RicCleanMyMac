import Foundation
import os

nonisolated private let logger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "RicCleanMyMac",
    category: "TreeBuilder"
)

/// The canonical path of `path`: symlinks resolved, `/private` kept.
/// `URL.resolvingSymlinksInPath()` strips `/private` (it turns `/private/var`
/// into `/var`), which would stop paths from matching `ScanPolicy` rules.
/// Falls back to the standardized path when the item does not exist.
nonisolated func resolvedRealPath(_ path: String) -> String {
    guard let resolved = realpath(path, nil) else {
        return URL(fileURLWithPath: path).standardizedFileURL.path
    }
    defer { free(resolved) }
    return String(cString: resolved)
}

/// Builds a `FileNode` tree from the filesystem, applying `ScanPolicy` to
/// every folder, the starting one included.
///
/// One instance per traversal, used from a single task: it keeps counters
/// and the set of hard links already met. Traversal stops early when the
/// calling task is cancelled.
nonisolated final class TreeBuilder {
    /// Allocated size is what a file really takes on disk: it is ~0 for
    /// iCloud files that are not downloaded and smaller for sparse files.
    /// APFS clones still count in full, macOS does not expose shared blocks.
    private static let resourceKeys: [URLResourceKey] = [
        .isDirectoryKey,
        .totalFileAllocatedSizeKey,
        .fileAllocatedSizeKey,
        .fileSizeKey,
        .linkCountKey
    ]
    private static let resourceKeySet = Set(resourceKeys)

    /// Throttle progress callbacks to ~10 Hz. Any higher and the main actor
    /// drowns in hops during deep recursion.
    private static let progressInterval: CFAbsoluteTime = 0.1

    private(set) var filesCount = 0
    private(set) var directoriesCount = 0

    private let scanRoot: URL
    private let homeDirectory: URL
    private let bootVolumeName: String?
    private let ignoresHardLinkedFiles: Bool
    private let progressHandler: (@Sendable (ScanProgress) -> Void)?
    private let fileManager = FileManager.default

    private var scannedCount = 0
    private var lastProgressUpdate: CFAbsoluteTime = 0
    private var seenHardLinks = Set<NSObject>()

    /// - Parameters:
    ///   - scanRoot: The root of the whole scan, used by `ScanPolicy` rules
    ///     that depend on it (a root on an external volume).
    ///   - ignoresHardLinkedFiles: Count files with more than one hard link
    ///     as 0 bytes. Used when re-measuring a subtree before deletion: the
    ///     first link may have been counted outside the subtree in the scan.
    ///   - progressHandler: Called at most ~10 times per second.
    init(
        scanRoot: URL,
        ignoresHardLinkedFiles: Bool = false,
        progressHandler: (@Sendable (ScanProgress) -> Void)? = nil
    ) {
        self.scanRoot = scanRoot
        self.homeDirectory = FileManager.default.homeDirectoryForCurrentUser
        self.bootVolumeName = try? URL(fileURLWithPath: "/")
            .resourceValues(forKeys: [.volumeNameKey])
            .volumeName
        self.ignoresHardLinkedFiles = ignoresHardLinkedFiles
        self.progressHandler = progressHandler
    }

    /// Builds the tree of the folder at `url`. The folder itself is
    /// classified like any other: a protected folder is still traversed, so
    /// the user sees its weight, but as `.readOnly`.
    func buildTree(startingAt url: URL, name: String) -> FileNode {
        let status: NodeStatus
        switch classify(url) {
        case .scanned: status = .normal
        case .readOnly, .skipped: status = .readOnly
        }
        return buildTree(at: url, name: name, status: status)
    }

    private func classify(_ url: URL) -> ScanPolicy.Classification {
        ScanPolicy.classify(
            url,
            homeDirectory: homeDirectory,
            bootVolumeName: bootVolumeName,
            scanRoot: scanRoot
        )
    }

    private func buildTree(at url: URL, name: String, status: NodeStatus) -> FileNode {
        directoriesCount += 1

        let contents: [URL]
        do {
            contents = try fileManager.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: Self.resourceKeys,
                options: []
            )
        } catch {
            logger.debug("contentsOfDirectory failed at \(url.path): \(error.localizedDescription)")
            return FileNode.inaccessibleDirectory(name: name)
        }

        var children: [FileNode] = []
        children.reserveCapacity(contents.count)
        var totalSize: Int64 = 0

        for itemURL in contents {
            if Task.isCancelled { break }

            let values: URLResourceValues?
            do {
                values = try itemURL.resourceValues(forKeys: Self.resourceKeySet)
            } catch {
                logger.debug("resourceValues failed at \(itemURL.path): \(error.localizedDescription)")
                values = nil
            }

            // Symlinks report `isDirectory == false`, so they are never followed.
            if values?.isDirectory ?? false {
                let childNode: FileNode
                switch classify(itemURL) {
                case .scanned:
                    childNode = buildTree(at: itemURL, name: itemURL.lastPathComponent, status: .normal)
                case .readOnly:
                    // Traverse and measure as usual, but mark the folder `.readOnly`
                    // so the UI and the deletion gate know. Its files inherit the
                    // status in `FileNode.directory`. An unreadable folder still
                    // comes back as `.inaccessible`.
                    childNode = buildTree(at: itemURL, name: itemURL.lastPathComponent, status: .readOnly)
                case .skipped(let reason):
                    // Do not traverse. Emit a placeholder with size 0 so the user
                    // still sees that the path exists without paying for its contents.
                    childNode = FileNode.skippedDirectory(name: itemURL.lastPathComponent, reason: reason)
                    directoriesCount += 1
                }
                totalSize += childNode.size
                children.append(childNode)
            } else {
                let fileSize = diskSize(of: values, at: itemURL)
                children.append(FileNode.file(name: itemURL.lastPathComponent, size: fileSize))
                totalSize += fileSize
                filesCount += 1
            }

            scannedCount += 1
            reportProgress(currentFolder: url.lastPathComponent)
        }

        children.sort { $0.size > $1.size }
        return FileNode.directory(name: name, children: children, size: totalSize, status: status)
    }

    /// Files with several hard links are counted once, at the first path met
    /// (or never, with `ignoresHardLinkedFiles`).
    private func diskSize(of values: URLResourceValues?, at url: URL) -> Int64 {
        guard let values else { return 0 }
        if let linkCount = values.linkCount, linkCount > 1 {
            if ignoresHardLinkedFiles { return 0 }
            if let identifier = try? url.resourceValues(forKeys: [.fileResourceIdentifierKey])
                .fileResourceIdentifier as? NSObject,
               !seenHardLinks.insert(identifier).inserted {
                return 0
            }
        }
        let size = values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? values.fileSize ?? 0
        return Int64(size)
    }

    private func reportProgress(currentFolder: String) {
        guard let progressHandler else { return }
        let now = CFAbsoluteTimeGetCurrent()
        guard now - lastProgressUpdate >= Self.progressInterval else { return }
        lastProgressUpdate = now
        progressHandler(ScanProgress(filesScanned: scannedCount, currentPath: currentFolder))
    }
}
