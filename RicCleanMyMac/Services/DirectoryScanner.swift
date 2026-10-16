import Foundation
import Combine
import os
import CommonCrypto

nonisolated private let logger = Logger(
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
    @Published var diskSpace: DiskSpace?
    @Published var smartCategories: [SmartCategory] = []

    /// Bumped every time the current tree is mutated in place (deletion).
    /// Views that cache data derived from a node (the sunburst) observe it,
    /// because the node itself stays the same object.
    @Published private(set) var treeRevision = 0

    /// The root path the scanner is currently working on (either actively
    /// scanning, loading from cache, or showing results for). `nil` when
    /// no scan has started yet this session. Not `@Published` on purpose:
    /// the view owns the "selected root" state (`DiskAnalyzerView.selectedRoot`)
    /// and all mutations flow through `startOrLoad`. Exposing this as a
    /// publisher would create a second source of truth for the same value.
    private(set) var currentRootPath: String?

    private let fileManager = FileManager.default
    private var scanTask: Task<Void, Never>?
    private var loadTask: Task<Void, Never>?
    private var diskSpaceTask: Task<Void, Never>?

    /// Identifies the scan whose progress the UI shows. Progress callbacks
    /// from an older scan that is still winding down are ignored.
    private var activeScanID: UUID?

    /// `true` after the user cancelled a scan or a scan failed, so the view
    /// does not start a new one by itself when it reappears.
    private(set) var skipsAutoStart = false

    /// The most recent cache save. Saves read the whole tree off the main
    /// thread, so every in-place mutation of the tree must wait for it first.
    private var saveTask: Task<Void, Never>?

    /// Returns the cache URL for a given scan root. The filename embeds a
    /// short hash of the root so different roots never collide.
    private func cacheURL(forRootPath rootPath: String) -> URL? {
        let digest = Self.shortHash(of: Self.resolvedPath(rootPath))
        return fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("RicCleanMyMac")
            .appendingPathComponent("scan-cache-\(digest).bin.lzfse")
    }

    /// 16-hex-char prefix of the SHA-256 of the input. Cryptographic strength
    /// is not required: we just need a filename-safe, stable, collision-rare
    /// fingerprint of the root path.
    private static func shortHash(of string: String) -> String {
        let data = Data(string.utf8)
        var hash = [UInt8](repeating: 0, count: 32)
        data.withUnsafeBytes { buffer in
            _ = CC_SHA256(buffer.baseAddress, CC_LONG(buffer.count), &hash)
        }
        return hash.prefix(8).map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Scanning

    /// Tear down any in-flight work and clear session-scoped state so a new
    /// scan or cache load can begin on `rootPath`. Shared between
    /// `scan(rootPath:)` and `loadCachedResult(forRootPath:)` to keep the
    /// two entry points in lockstep, otherwise switching roots after a
    /// successful scan (or during one) could leave stale state behind.
    private func prepareForNewRoot(_ rootPath: String) {
        scanTask?.cancel()
        scanTask = nil
        loadTask?.cancel()
        loadTask = nil
        activeScanID = nil
        skipsAutoStart = false

        currentRootPath = rootPath
        scanResult = nil
        currentNode = nil
        selectedItems.removeAll()
        smartCategories = []
        progress = ScanProgress(filesScanned: 0, currentPath: "")
        isScanning = false
        isLoadingCache = false
    }

    /// Reads the boot volume's capacity. Without `forceRefresh` it runs only
    /// once per session; deletions pass `true` to show the freed space.
    func loadDiskSpace(forceRefresh: Bool = false) {
        guard diskSpaceTask == nil, forceRefresh || diskSpace == nil else { return }
        diskSpaceTask = Task {
            if let space = await DiskAnalyzer().getDiskSpace() {
                diskSpace = space
            }
            diskSpaceTask = nil
        }
    }

    /// The real path of `path`. Scan roots are resolved before use so node
    /// paths match what `ScanPolicy` and the home-folder check expect:
    /// `/Volumes/Macintosh HD` is a symlink to `/`.
    nonisolated private static func resolvedPath(_ path: String) -> String {
        resolvedRealPath(path)
    }

    func scan(rootPath requestedPath: String) {
        let rootPath = Self.resolvedPath(requestedPath)
        prepareForNewRoot(rootPath)
        isScanning = true

        let startTime = Date()
        let scanID = UUID()
        activeScanID = scanID

        scanTask = Task { [weak self] in
            let progressHandler: @Sendable (ScanProgress) -> Void = { [weak self] progress in
                Task { @MainActor [weak self] in
                    guard let self, self.activeScanID == scanID else { return }
                    self.progress = progress
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
                self.handleScanSuccess(result)
            case .failed(let reason):
                self.isScanning = false
                self.skipsAutoStart = true
                self.lastError = .scanFailed(reason)
            case .cancelled:
                self.isScanning = false
            }
        }
    }

    private func handleScanSuccess(_ result: DirectoryScanResult) {
        scanResult = result
        currentNode = result.root
        smartCategories = result.root.extractSmartCategories()
        isScanning = false
        scheduleCacheSave(result)
    }

    /// Saves `result` to the cache of the current root, after any save still
    /// running. The work happens off the main thread because serialization
    /// and LZFSE compression are CPU-bound on large trees.
    private func scheduleCacheSave(_ result: DirectoryScanResult) {
        guard let rootPath = currentRootPath,
              let cacheURL = cacheURL(forRootPath: rootPath) else { return }
        let previousSave = saveTask
        saveTask = Task { [weak self] in
            await previousSave?.value
            do {
                try await Task.detached(priority: .utility) {
                    try Self.saveToDisk(result, cacheURL: cacheURL)
                }.value
            } catch {
                logger.error("Failed to save scan cache: \(error.localizedDescription, privacy: .public)")
                self?.lastError = .cacheSaveFailed(error.localizedDescription)
            }
        }
    }

    /// Whether a cached scan exists on disk for the given root path.
    func hasCachedResult(forRootPath rootPath: String) -> Bool {
        guard let cacheURL = cacheURL(forRootPath: rootPath) else { return false }
        return fileManager.fileExists(atPath: cacheURL.path)
    }

    /// Load the cached scan result for the given root path asynchronously
    /// (off the main thread).
    func loadCachedResult(forRootPath requestedPath: String) {
        let rootPath = Self.resolvedPath(requestedPath)
        prepareForNewRoot(rootPath)
        isLoadingCache = true

        let cacheURL = self.cacheURL(forRootPath: rootPath)
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
                self.smartCategories = result.root.extractSmartCategories()
            case .notFound:
                // No cache yet: the UI handles this by offering a fresh scan.
                break
            case .failed(let reason):
                self.lastError = .cacheLoadFailed(reason)
            }
        }
    }

    /// Stops the running scan or cache load. When a scan is cancelled and the
    /// root has a saved scan (a "Re-scan" cancelled midway), that scan is
    /// shown again instead of an empty view.
    func cancel() {
        let wasScanning = isScanning
        scanTask?.cancel()
        scanTask = nil
        loadTask?.cancel()
        loadTask = nil
        activeScanID = nil
        isScanning = false
        isLoadingCache = false

        if wasScanning, scanResult == nil,
           let rootPath = currentRootPath, hasCachedResult(forRootPath: rootPath) {
            loadCachedResult(forRootPath: rootPath)
        }
        skipsAutoStart = true
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
        let worker = Task.detached(priority: .userInitiated) { () -> ScanOutcome in
            // Validate the root up front so we can distinguish "root unreadable"
            // from "root readable but some descendants were skipped".
            let rootURL = URL(fileURLWithPath: rootPath)
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: rootURL.path, isDirectory: &isDir),
                  isDir.boolValue else {
                return .failed("Root path does not exist or is not a directory: \(rootPath)")
            }

            let builder = TreeBuilder(scanRoot: rootURL, progressHandler: progressHandler)
            let root = builder.buildTree(startingAt: rootURL, name: rootURL.path)

            if Task.isCancelled { return .cancelled }

            return .success(DirectoryScanResult(
                root: root,
                totalFiles: builder.filesCount,
                totalDirectories: builder.directoriesCount,
                scanDuration: Date().timeIntervalSince(startTime),
                scanDate: Date()
            ))
        }
        // A detached task does not inherit cancellation: forward it, so
        // `cancel()` and root switches really stop the traversal.
        return await withTaskCancellationHandler {
            await worker.value
        } onCancel: {
            worker.cancel()
        }
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

    /// The selected children of the current node. Selection never spans
    /// folders, because every navigation clears it, so filtering the direct
    /// children is enough.
    var selectedNodes: [FileNode] {
        guard !selectedItems.isEmpty, let children = currentNode?.children else { return [] }
        return children.filter { selectedItems.contains($0.id) }
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
        deletionBlocker(for: node) == nil
    }

    /// Why `node` must not be deleted, or `nil` when it can be.
    private func deletionBlocker(for node: FileNode) -> String? {
        if node === scanResult?.root { return "Path is the scan root" }
        switch node.status {
        case .normal: break
        case .readOnly: return "Path is read-only"
        case .skipped: return "Path is skipped by scan policy"
        case .inaccessible: return "Path could not be read during the scan"
        }
        if Self.isHomeOrAncestorOfHome(node.path) {
            return "Path is your home folder or contains it"
        }
        if node.containsProtectedItems {
            return "Folder contains protected items"
        }
        return nil
    }

    private static let resolvedHomePath = resolvedPath(
        FileManager.default.homeDirectoryForCurrentUser.path
    ).lowercased()

    /// `path` comes from the tree, whose root path is already resolved.
    private static func isHomeOrAncestorOfHome(_ path: String) -> Bool {
        let home = resolvedHomePath
        let candidate = URL(fileURLWithPath: path).standardizedFileURL.path.lowercased()
        if candidate == home || candidate == "/" { return true }
        return home.hasPrefix(candidate + "/")
    }

    func deleteSingleItem(_ node: FileNode) async -> DeletionResult {
        await deleteNodes([node])
    }

    func deleteSelectedItems() async -> DeletionResult {
        let nodes = selectedNodes
        guard !nodes.isEmpty else {
            return DeletionResult(successCount: 0, freedSize: 0, failures: [])
        }
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
            if let reason = deletionBlocker(for: node) {
                // Paths use the default (private) log privacy: they are user data.
                logger.warning("Skipped non-deletable path: \(node.path) reason=\(reason, privacy: .public)")
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

        // A cache save may still be reading the tree in the background:
        // wait for it before removing nodes.
        await saveTask?.value

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
                logger.error("Failed to delete \(failure.path): \(failure.reason)")
                failures.append(failure)
            }
        }
        if successCount > 0 {
            treeRevision += 1
            if let scanResult {
                smartCategories = scanResult.root.extractSmartCategories()
                scheduleCacheSave(scanResult)
            }
            loadDiskSpace(forceRefresh: true)
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

            logger.debug("""
                Cache load timing: \
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
