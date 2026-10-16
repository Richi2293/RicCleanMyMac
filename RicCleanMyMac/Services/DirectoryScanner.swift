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

    /// `true` while a deletion runs. Only one deletion runs at a time.
    @Published private(set) var isDeleting = false

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

    /// Where scan caches are saved. `nil` when Application Support cannot be
    /// resolved: scans then work without a cache.
    private let cacheDirectory: URL?

    private var scanTask: Task<Void, Never>?
    private var loadTask: Task<Void, Never>?
    private var diskSpaceTask: Task<Void, Never>?
    private var diskSpaceRefreshPending = false

    /// Identifies the scan whose progress the UI shows. Progress callbacks
    /// from an older scan that is still winding down are ignored.
    private var activeScanID: UUID?

    /// `true` after the user cancelled a scan or a scan failed, so the view
    /// does not start a new one by itself when it reappears.
    private(set) var skipsAutoStart = false

    /// The most recent background work on a tree (cache save, smart
    /// categories). It reads the tree off the main thread, so every in-place
    /// mutation of the tree must wait for it first. Each task waits for the
    /// previous one.
    private var backgroundTask: Task<Void, Never>?

    /// Cache files a queued background task will write. A root counts as
    /// cached as soon as its save is queued, so reopening it loads the cache
    /// (after the save) instead of starting a full scan.
    private var pendingCacheSaves: [URL: Int] = [:]

    /// - Parameter cacheDirectory: Where to save scan caches. Defaults to the
    ///   app's folder in Application Support; tests pass a temporary folder.
    init(cacheDirectory: URL? = DirectoryScanner.defaultCacheDirectory) {
        self.cacheDirectory = cacheDirectory
    }

    nonisolated static var defaultCacheDirectory: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("RicCleanMyMac")
    }

    /// Returns the cache URL for a given scan root. The filename embeds a
    /// short hash of the root so different roots never collide.
    private func cacheURL(forRootPath rootPath: String) -> URL? {
        let digest = Self.shortHash(of: Self.resolvedPath(rootPath))
        return cacheDirectory?.appendingPathComponent("scan-cache-\(digest).bin.lzfse")
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
        guard forceRefresh || diskSpace == nil else { return }
        guard diskSpaceTask == nil else {
            // A read is running and may predate the change: read again after it.
            if forceRefresh { diskSpaceRefreshPending = true }
            return
        }
        diskSpaceTask = Task {
            if let space = await DiskAnalyzer().getDiskSpace() {
                diskSpace = space
            }
            diskSpaceTask = nil
            if diskSpaceRefreshPending {
                diskSpaceRefreshPending = false
                loadDiskSpace(forceRefresh: true)
            }
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
        isScanning = false
        scheduleBackgroundWork(on: result, savingTo: currentRootPath.flatMap(cacheURL(forRootPath:)))
    }

    private struct BackgroundWorkOutcome: Sendable {
        let categories: [SmartCategory]
        let saveError: String?
    }

    /// Computes the smart categories of `result` and, with a `cacheURL`, saves
    /// it, after any background work still running. Both walk the whole tree,
    /// so they run off the main thread; categories come first so they show
    /// sooner. Categories are applied only if `result` is still on screen.
    private func scheduleBackgroundWork(on result: DirectoryScanResult, savingTo cacheURL: URL?) {
        let previous = backgroundTask
        if let cacheURL { pendingCacheSaves[cacheURL, default: 0] += 1 }
        backgroundTask = Task { [weak self] in
            await previous?.value
            let outcome = await Task.detached(priority: .utility) { () -> BackgroundWorkOutcome in
                let categories = result.root.extractSmartCategories()
                var saveError: String?
                if let cacheURL {
                    do {
                        try Self.saveToDisk(result, cacheURL: cacheURL)
                    } catch {
                        logger.error("Failed to save scan cache: \(error.localizedDescription, privacy: .public)")
                        saveError = error.localizedDescription
                    }
                }
                return BackgroundWorkOutcome(categories: categories, saveError: saveError)
            }.value
            guard let self else { return }
            if let cacheURL {
                self.pendingCacheSaves[cacheURL, default: 1] -= 1
                if self.pendingCacheSaves[cacheURL] == 0 { self.pendingCacheSaves[cacheURL] = nil }
            }
            if self.scanResult?.root === result.root {
                self.smartCategories = outcome.categories
            }
            if let saveError = outcome.saveError {
                self.lastError = .cacheSaveFailed(saveError)
            }
        }
    }

    /// Waits until no background work reads a tree, including work that was
    /// scheduled while waiting.
    func waitForBackgroundWork() async {
        while let task = backgroundTask {
            await task.value
            if backgroundTask == task { return }
        }
    }

    /// Whether a cached scan exists on disk for the given root path.
    func hasCachedResult(forRootPath rootPath: String) -> Bool {
        guard let cacheURL = cacheURL(forRootPath: rootPath) else { return false }
        return pendingCacheSaves[cacheURL] != nil || fileManager.fileExists(atPath: cacheURL.path)
    }

    /// Load the cached scan result for the given root path asynchronously
    /// (off the main thread).
    func loadCachedResult(forRootPath requestedPath: String) {
        let rootPath = Self.resolvedPath(requestedPath)
        prepareForNewRoot(rootPath)
        isLoadingCache = true

        let cacheURL = self.cacheURL(forRootPath: rootPath)
        loadTask = Task { [weak self] in
            // A save of this root may still be queued (for example right after
            // a deletion): read the file only once it is written.
            await self?.waitForBackgroundWork()
            guard !Task.isCancelled else { return }
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
                self.scheduleBackgroundWork(on: result, savingTo: nil)
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
        if ScanPolicy.isKeptFolder(
            URL(fileURLWithPath: node.path),
            homeDirectory: FileManager.default.homeDirectoryForCurrentUser
        ) {
            return "This folder must stay in place. Delete its contents instead."
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

    /// Deletes `node`. Returns `nil` without doing anything when another
    /// deletion is running.
    func deleteSingleItem(_ node: FileNode) async -> DeletionResult? {
        await deleteNodes([node])
    }

    /// Deletes the selected items. Returns `nil` without doing anything when
    /// another deletion is running or nothing is selected.
    func deleteSelectedItems() async -> DeletionResult? {
        let nodes = selectedNodes
        guard !nodes.isEmpty else { return nil }
        return await deleteNodes(nodes)
    }

    private struct DeletionJob: Sendable {
        let index: Int
        let path: String
        let parentPath: String
        let size: Int64
        let isDirectory: Bool
    }

    private enum DeletionOutcome: Sendable {
        /// Deleted from disk: remove the node.
        case deleted(index: Int, freed: Int64)
        /// No longer on disk: remove the node, and tell the user.
        case gone(index: Int, failure: DeletionFailure)
        /// A permanent deletion failed halfway: what is left replaces the node.
        case partiallyDeleted(index: Int, remaining: FileNode, failure: DeletionFailure)
        case failed(DeletionFailure)
    }

    private func deleteNodes(_ nodes: [FileNode]) async -> DeletionResult? {
        guard !isDeleting, let result = scanResult, let rootPath = currentRootPath else { return nil }
        isDeleting = true
        defer { isDeleting = false }

        // Captured now: if the user switches root meanwhile, the tree and the
        // cache of this root are still the ones to update.
        let cacheURL = cacheURL(forRootPath: rootPath)
        let scanRootPath = result.root.path

        var jobs: [DeletionJob] = []
        var failures: [DeletionFailure] = []
        for (index, node) in nodes.enumerated() {
            if let reason = deletionBlocker(for: node) {
                // Paths use the default (private) log privacy: they are user data.
                logger.warning("Skipped non-deletable path: \(node.path) reason=\(reason, privacy: .public)")
                failures.append(DeletionFailure(path: node.path, reason: reason))
                continue
            }
            jobs.append(DeletionJob(
                index: index,
                path: node.path,
                parentPath: node.parent?.path ?? "",
                size: node.size,
                isDirectory: node.isDirectory
            ))
        }

        let deleteMode = self.deleteMode
        let outcomes = await Task.detached(priority: .userInitiated) {
            jobs.map { Self.performDeletion($0, mode: deleteMode, scanRootPath: scanRootPath) }
        }.value

        await waitForBackgroundWork()

        var successCount = 0
        var freedSize: Int64 = 0
        var removedByParent: [ObjectIdentifier: (parent: FileNode, ids: Set<ObjectIdentifier>)] = [:]
        var detachedNodes: [(old: FileNode, replacement: FileNode?)] = []

        func scheduleRemoval(of node: FileNode) {
            guard let parent = node.parent else { return }
            removedByParent[parent.id, default: (parent, [])].ids.insert(node.id)
            detachedNodes.append((node, nil))
        }

        for outcome in outcomes {
            switch outcome {
            case .deleted(let index, let freed):
                scheduleRemoval(of: nodes[index])
                successCount += 1
                freedSize += freed
            case .gone(let index, let failure):
                scheduleRemoval(of: nodes[index])
                failures.append(failure)
            case .partiallyDeleted(let index, let remaining, let failure):
                let node = nodes[index]
                node.parent?.replaceChild(node, with: remaining)
                detachedNodes.append((node, remaining))
                failures.append(failure)
            case .failed(let failure):
                failures.append(failure)
            }
        }
        for (parent, ids) in removedByParent.values {
            parent.removeChildren(withIDs: ids)
        }
        for failure in failures {
            logger.error("Failed to delete \(failure.path): \(failure.reason)")
        }

        if !detachedNodes.isEmpty {
            if scanResult?.root === result.root {
                selectedItems.subtract(detachedNodes.map(\.old.id))
                // The folder on screen may have been deleted or replaced.
                if let current = currentNode,
                   let hit = detachedNodes.first(where: { current.isWithin($0.old) }) {
                    currentNode = hit.replacement ?? hit.old.parent ?? result.root
                }
                treeRevision += 1
            }
            scheduleBackgroundWork(on: result, savingTo: cacheURL)
            loadDiskSpace(forceRefresh: true)
        }

        if !failures.isEmpty {
            lastError = .deletionFailed(failures: failures)
        }
        return DeletionResult(successCount: successCount, freedSize: freedSize, failures: failures)
    }

    /// How much an item may have grown since the scan before deletion is
    /// refused: 10% of the size shown, at least 10 MB.
    nonisolated private static func allowedGrowth(over size: Int64) -> Int64 {
        max(size / 10, 10 * 1024 * 1024)
    }

    /// Checks that the item on disk is still the one the user confirmed,
    /// then deletes it. Runs off the main thread.
    nonisolated private static func performDeletion(
        _ job: DeletionJob,
        mode: DeleteMode,
        scanRootPath: String
    ) -> DeletionOutcome {
        let fm = FileManager.default
        func failure(_ reason: String) -> DeletionFailure {
            DeletionFailure(path: job.path, reason: reason)
        }

        // `attributesOfItem` does not follow symlinks, so a broken link is
        // still found and the link itself is what gets checked.
        guard let attributes = try? fm.attributesOfItem(atPath: job.path) else {
            return .gone(index: job.index, failure: failure("Item no longer exists"))
        }
        let type = attributes[.type] as? FileAttributeType
        if job.isDirectory != (type == .typeDirectory) {
            return .failed(failure("Item changed since the scan. Re-scan before deleting it."))
        }
        // A folder on the path that became a symlink would redirect the deletion.
        if resolvedRealPath(job.parentPath).lowercased() != job.parentPath.lowercased() {
            return .failed(failure("A folder on this path changed since the scan. Re-scan before deleting it."))
        }

        let url = URL(fileURLWithPath: job.path)
        let currentSize: Int64
        if job.isDirectory {
            let fresh = TreeBuilder(scanRoot: URL(fileURLWithPath: scanRootPath), ignoresHardLinkedFiles: true)
                .buildTree(startingAt: url, name: url.lastPathComponent)
            guard fresh.isDeletableByPolicy else {
                return .failed(failure("Folder now contains protected items"))
            }
            currentSize = fresh.size
        } else {
            let values = try? url.resourceValues(
                forKeys: [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .fileSizeKey, .linkCountKey]
            )
            if let linkCount = values?.linkCount, linkCount > 1 {
                // The scan counts a hard-linked file at one path only, so the
                // size shown may be 0: like folders, ignore it when measuring.
                currentSize = 0
            } else {
                currentSize = Int64(values?.totalFileAllocatedSize ?? values?.fileAllocatedSize ?? values?.fileSize ?? 0)
            }
        }
        if currentSize > job.size + allowedGrowth(over: job.size) {
            return .failed(failure("Item grew since the scan. Re-scan before deleting it."))
        }

        do {
            switch mode {
            case .trash:
                try fm.trashItem(at: url, resultingItemURL: nil)
            case .permanent:
                try fm.removeItem(at: url)
            }
            return .deleted(index: job.index, freed: job.size)
        } catch {
            let reason = failure(error.localizedDescription)
            // Moving to the Trash is all or nothing; a permanent deletion of a
            // folder can stop halfway and leave part of it behind.
            guard mode == .permanent, job.isDirectory else { return .failed(reason) }
            guard (try? fm.attributesOfItem(atPath: job.path)) != nil else {
                return .deleted(index: job.index, freed: job.size)
            }
            let remaining = TreeBuilder(scanRoot: URL(fileURLWithPath: scanRootPath))
                .buildTree(startingAt: url, name: url.lastPathComponent)
            return .partiallyDeleted(index: job.index, remaining: remaining, failure: reason)
        }
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
