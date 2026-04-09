import Foundation
import Combine
import os

private let logger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "RicCleanMyMac",
    category: "DirectoryScanner"
)

@MainActor
final class DirectoryScanner: ObservableObject {
    @Published var isScanning = false
    @Published var isLoadingCache = false
    @Published var progress = ScanProgress(filesScanned: 0, currentPath: "")
    @Published var scanResult: DirectoryScanResult?
    @Published var currentNode: FileNode?
    @Published var selectedItems: Set<ObjectIdentifier> = []
    @Published var deleteMode: DeleteMode = .trash
    @Published var lastError: ScanError?

    private let fileManager = FileManager.default
    private var scanTask: Task<Void, Never>?
    private var loadTask: Task<Void, Never>?

    private var cacheURL: URL? {
        fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("RicCleanMyMac")
            .appendingPathComponent("scan-cache.bin.lzfse")
    }

    // MARK: - Scanning

    func scan(rootPath: String) {
        scanTask?.cancel()
        loadTask?.cancel()
        loadTask = nil

        isScanning = true
        isLoadingCache = false
        scanResult = nil
        currentNode = nil
        selectedItems.removeAll()
        progress = ScanProgress(filesScanned: 0, currentPath: "")

        let startTime = Date()

        scanTask = Task { [weak self] in
            let progressHandler: @Sendable (ScanProgress) -> Void = { [weak self] progress in
                Task { @MainActor [weak self] in
                    self?.progress = progress
                }
            }

            let outcome = await Self.performScan(
                rootPath: rootPath,
                startTime: startTime,
                progressHandler: progressHandler
            )

            guard let self, !Task.isCancelled else { return }

            switch outcome {
            case .success(let result):
                await self.handleScanSuccess(result)
            case .failed(let reason):
                self.isScanning = false
                self.lastError = .scanFailed(reason)
            case .cancelled:
                self.isScanning = false
            }
        }
    }

    private func handleScanSuccess(_ result: DirectoryScanResult) async {
        scanResult = result
        currentNode = result.root
        isScanning = false

        // Save happens on a detached task so the main thread is not blocked by
        // serialization and LZFSE compression (both are CPU-bound on large trees).
        let cacheURL = self.cacheURL
        Task.detached(priority: .utility) { [weak self] in
            guard let cacheURL else { return }
            do {
                try Self.saveToDisk(result, cacheURL: cacheURL)
            } catch {
                logger.error("Failed to save scan cache: \(error.localizedDescription, privacy: .public)")
                await MainActor.run { [weak self] in
                    self?.lastError = .cacheSaveFailed(error.localizedDescription)
                }
            }
        }
    }

    /// Whether a cached scan exists on disk.
    var hasCachedResult: Bool {
        guard let cacheURL else { return false }
        return fileManager.fileExists(atPath: cacheURL.path)
    }

    /// Load cached scan result asynchronously (off the main thread).
    func loadCachedResult() {
        guard scanResult == nil, !isLoadingCache, !isScanning else { return }
        isLoadingCache = true

        let cacheURL = self.cacheURL
        loadTask = Task { [weak self] in
            let outcome: CacheLoadOutcome = await Task.detached(priority: .userInitiated) {
                guard let cacheURL else { return .notFound }
                return Self.loadFromDisk(cacheURL: cacheURL)
            }.value

            guard let self, !Task.isCancelled else { return }

            self.isLoadingCache = false
            self.loadTask = nil

            switch outcome {
            case .success(let result):
                self.scanResult = result
                self.currentNode = result.root
            case .notFound:
                // No cache yet — UI handles this by offering a fresh scan.
                break
            case .failed(let reason):
                self.lastError = .cacheLoadFailed(reason)
            }
        }
    }

    func cancel() {
        scanTask?.cancel()
        scanTask = nil
        loadTask?.cancel()
        loadTask = nil
        isScanning = false
        isLoadingCache = false
    }

    // MARK: - Scan worker

    /// Outcome of a scan run. Distinct from `nil` so the caller can distinguish
    /// cancellation from a real failure and report accordingly.
    private enum ScanOutcome {
        case success(DirectoryScanResult)
        case cancelled
        case failed(String)
    }

    nonisolated private static func performScan(
        rootPath: String,
        startTime: Date,
        progressHandler: @Sendable @escaping (ScanProgress) -> Void
    ) async -> ScanOutcome {
        return await Task.detached(priority: .userInitiated) { () -> ScanOutcome in
            let fileManager = FileManager.default
            var filesCount = 0
            var directoriesCount = 0
            var scannedCount = 0
            var lastProgressUpdate: CFAbsoluteTime = 0

            // Throttle main-actor progress dispatches to ~10 Hz. Any higher and
            // the main actor drowns in hops during deep recursion.
            let progressInterval: CFAbsoluteTime = 0.1

            let bootVolumeName: String? = try? URL(fileURLWithPath: "/")
                .resourceValues(forKeys: [.volumeNameKey])
                .volumeName
            let homeDirectory = FileManager.default.homeDirectoryForCurrentUser

            func buildTree(at url: URL) -> FileNode {
                directoriesCount += 1
                let name = url.lastPathComponent

                let contents: [URL]
                do {
                    contents = try fileManager.contentsOfDirectory(
                        at: url,
                        includingPropertiesForKeys: [.fileSizeKey, .isDirectoryKey],
                        options: []
                    )
                } catch {
                    logger.debug("contentsOfDirectory failed at \(url.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
                    return FileNode.inaccessibleDirectory(name: name)
                }

                var children: [FileNode] = []
                children.reserveCapacity(contents.count)
                var totalSize: Int64 = 0

                for itemURL in contents {
                    if Task.isCancelled { break }

                    let values: URLResourceValues?
                    do {
                        values = try itemURL.resourceValues(forKeys: [.fileSizeKey, .isDirectoryKey])
                    } catch {
                        logger.debug("resourceValues failed at \(itemURL.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
                        values = nil
                    }
                    let isDir = values?.isDirectory ?? false

                    if isDir {
                        let classification = ScanPolicy.classify(
                            itemURL,
                            homeDirectory: homeDirectory,
                            bootVolumeName: bootVolumeName
                        )
                        let childNode: FileNode
                        switch classification {
                        case .scanned:
                            childNode = buildTree(at: itemURL)
                        case .readOnly:
                            // Traverse and measure as usual, then re-wrap the result with
                            // `.readOnly` status so the UI and deletion gate know. If the
                            // inner traversal failed (e.g. permissions), preserve the
                            // inaccessible node as-is instead of re-wrapping — that keeps
                            // `children == nil` consistent with how `inaccessibleDirectory`
                            // builds such nodes, and avoids the fragile assumption that
                            // `buildTree` only returns `.normal` or `.inaccessible`.
                            let scanned = buildTree(at: itemURL)
                            if scanned.status == .inaccessible {
                                childNode = scanned
                            } else {
                                childNode = FileNode.directory(
                                    name: scanned.name,
                                    children: scanned.children ?? [],
                                    size: scanned.size,
                                    status: .readOnly
                                )
                            }
                        case .skipped(let reason):
                            // Do not traverse. Emit a placeholder with size 0 so
                            // the user still sees that the path exists but does
                            // not pay the cost of reading its contents.
                            childNode = FileNode.skippedDirectory(
                                name: itemURL.lastPathComponent,
                                reason: reason
                            )
                            directoriesCount += 1
                        }
                        totalSize += childNode.size
                        children.append(childNode)
                    } else {
                        let fileSize = Int64(values?.fileSize ?? 0)
                        children.append(FileNode.file(name: itemURL.lastPathComponent, size: fileSize))
                        totalSize += fileSize
                        filesCount += 1
                    }

                    scannedCount += 1
                    let now = CFAbsoluteTimeGetCurrent()
                    if now - lastProgressUpdate >= progressInterval {
                        lastProgressUpdate = now
                        progressHandler(ScanProgress(filesScanned: scannedCount, currentPath: url.lastPathComponent))
                    }
                }

                children.sort { $0.size > $1.size }
                return FileNode.directory(name: name, children: children, size: totalSize, status: .normal)
            }

            // Validate the root up front so we can distinguish "root unreadable"
            // from "root readable but some descendants were skipped".
            let rootURL = URL(fileURLWithPath: rootPath)
            var isDir: ObjCBool = false
            guard fileManager.fileExists(atPath: rootURL.path, isDirectory: &isDir), isDir.boolValue else {
                return .failed("Root path does not exist or is not a directory: \(rootPath)")
            }

            let root = buildTree(at: rootURL)

            if Task.isCancelled { return .cancelled }

            let result = DirectoryScanResult(
                root: root,
                totalFiles: filesCount,
                totalDirectories: directoriesCount,
                scanDuration: Date().timeIntervalSince(startTime),
                scanDate: Date()
            )
            return .success(result)
        }.value
    }

    // MARK: - Navigation

    var breadcrumbPath: [FileNode] {
        guard let current = currentNode else { return [] }
        var path: [FileNode] = [current]
        var node = current
        while let parent = node.parent {
            path.insert(parent, at: 0)
            node = parent
        }
        return path
    }

    func navigateTo(_ node: FileNode) {
        guard node.isDirectory else { return }
        selectedItems.removeAll()
        currentNode = node
    }

    func navigateToParent() {
        guard let parent = currentNode?.parent else { return }
        selectedItems.removeAll()
        currentNode = parent
    }

    // MARK: - Deletion

    func isNodeDeletable(_ node: FileNode) -> Bool {
        if node === scanResult?.root { return false }
        switch node.status {
        case .normal: return true
        case .readOnly, .skipped, .inaccessible: return false
        }
    }

    func deleteSingleItem(_ node: FileNode) async -> DeletionResult {
        await deleteNodes([node])
    }

    func deleteSelectedItems() async -> DeletionResult {
        guard let current = currentNode else {
            return DeletionResult(successCount: 0, freedSize: 0, failures: [])
        }
        let nodes = current.findNodes(withIDs: selectedItems)
        let result = await deleteNodes(nodes)
        selectedItems.removeAll()
        return result
    }

    private func deleteNodes(_ nodes: [FileNode]) async -> DeletionResult {
        struct DeletionJob: Sendable {
            let index: Int
            let path: String
            let size: Int64
        }
        enum Outcome: Sendable {
            case success(index: Int, freed: Int64)
            case failure(DeletionFailure)
        }

        var jobs: [DeletionJob] = []
        var failures: [DeletionFailure] = []

        for (index, node) in nodes.enumerated() {
            guard isNodeDeletable(node) else {
                let reason: String
                if node === scanResult?.root {
                    reason = "Path is the scan root"
                } else {
                    switch node.status {
                    case .readOnly: reason = "Path is read-only"
                    case .skipped: reason = "Path is skipped by scan policy"
                    case .inaccessible: reason = "Path could not be read during the scan"
                    case .normal:
                        // A .normal node that is not the root and is not deletable
                        // is a contract violation of isNodeDeletable.
                        reason = "Path is not deletable"
                    }
                }
                logger.warning("Skipped non-deletable path: \(node.path, privacy: .public)")
                failures.append(DeletionFailure(path: node.path, reason: reason))
                continue
            }
            jobs.append(DeletionJob(index: index, path: node.path, size: node.size))
        }

        let deleteMode = self.deleteMode
        let outcomes: [Outcome] = await Task.detached(priority: .userInitiated) {
            let fm = FileManager.default
            var results: [Outcome] = []
            results.reserveCapacity(jobs.count)
            for job in jobs {
                guard fm.fileExists(atPath: job.path) else {
                    results.append(.failure(DeletionFailure(
                        path: job.path,
                        reason: "Item no longer exists"
                    )))
                    continue
                }
                do {
                    switch deleteMode {
                    case .trash:
                        try fm.trashItem(at: URL(fileURLWithPath: job.path), resultingItemURL: nil)
                    case .permanent:
                        try fm.removeItem(atPath: job.path)
                    }
                    results.append(.success(index: job.index, freed: job.size))
                } catch {
                    results.append(.failure(DeletionFailure(
                        path: job.path,
                        reason: error.localizedDescription
                    )))
                }
            }
            return results
        }.value

        var successCount = 0
        var freedSize: Int64 = 0
        for outcome in outcomes {
            switch outcome {
            case .success(let index, let freed):
                let node = nodes[index]
                node.parent?.removeChild(node)
                successCount += 1
                freedSize += freed
            case .failure(let failure):
                logger.error("Failed to delete \(failure.path, privacy: .public): \(failure.reason, privacy: .public)")
                failures.append(failure)
            }
        }
        if successCount > 0 {
            objectWillChange.send()
        }

        let result = DeletionResult(
            successCount: successCount,
            freedSize: freedSize,
            failures: failures
        )
        if !failures.isEmpty {
            lastError = .deletionFailed(failures: failures)
        }
        return result
    }

    // MARK: - Persistence

    /// Outcome of a cache load attempt, distinguishing "no cache" from "cache corrupted".
    private enum CacheLoadOutcome {
        case success(DirectoryScanResult)
        case notFound
        case failed(String)
    }

    nonisolated private static func saveToDisk(_ result: DirectoryScanResult, cacheURL: URL) throws {
        let fileManager = FileManager.default
        let directory = cacheURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

        let data = try ScanCacheSerializer.write(result)
        let compressed = try (data as NSData).compressed(using: .lzfse) as Data
        try compressed.write(to: cacheURL, options: .atomic)

        logger.info("Saved scan cache (\(compressed.count) bytes compressed, \(data.count) bytes raw)")
    }

    nonisolated private static func loadFromDisk(cacheURL: URL) -> CacheLoadOutcome {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: cacheURL.path) else { return .notFound }

        do {
            let t0 = CFAbsoluteTimeGetCurrent()
            let compressed = try Data(contentsOf: cacheURL)
            let t1 = CFAbsoluteTimeGetCurrent()

            let data = try (compressed as NSData).decompressed(using: .lzfse) as Data
            let t2 = CFAbsoluteTimeGetCurrent()

            let result = try ScanCacheSerializer.read(from: data)
            let t3 = CFAbsoluteTimeGetCurrent()

            logger.info("""
                Cache load timing — \
                read: \(String(format: "%.2f", t1 - t0))s, \
                decompress: \(String(format: "%.2f", t2 - t1))s, \
                decode: \(String(format: "%.2f", t3 - t2))s, \
                compressed: \(compressed.count) bytes, \
                decompressed: \(data.count) bytes, \
                files: \(result.totalFiles), \
                folders: \(result.totalDirectories)
                """)
            return .success(result)
        } catch {
            logger.error("Failed to load scan cache: \(error.localizedDescription, privacy: .public)")
            do {
                try fileManager.removeItem(at: cacheURL)
            } catch {
                logger.error("Failed to remove corrupt scan cache: \(error.localizedDescription, privacy: .public)")
            }
            return .failed(error.localizedDescription)
        }
    }
}
