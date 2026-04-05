import Foundation
import Combine
import os

private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "RicCleanMyMac", category: "DirectoryScanner")

final class DirectoryScanner: ObservableObject {
    @Published var isScanning = false
    @Published var progress = ScanProgress(filesScanned: 0, currentPath: "")
    @Published var scanResult: DirectoryScanResult?
    @Published var currentNode: FileNode?
    @Published var selectedItems: Set<UUID> = []
    @Published var deleteMode: DeleteMode = .trash

    private let fileManager = FileManager.default
    private var scanTask: Task<Void, Never>?

    private var cacheURL: URL? {
        fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("RicCleanMyMac")
            .appendingPathComponent("scan-cache.bplist.lzfse")
    }

    /// Protected system paths that cannot be deleted
    private let protectedPrefixes: [String] = [
        "/System", "/usr", "/bin", "/sbin", "/private", "/Library"
    ]

    // MARK: - Scanning

    func scan(rootPath: String) {
        scanTask?.cancel()
        isScanning = true
        scanResult = nil
        currentNode = nil
        selectedItems.removeAll()
        progress = ScanProgress(filesScanned: 0, currentPath: "")

        let startTime = Date()

        scanTask = Task { [weak self] in
            guard let self else { return }

            let result = await self.performScan(rootPath: rootPath, startTime: startTime)

            guard !Task.isCancelled else { return }

            if let result {
                self.saveToDisk(result)
            }

            await MainActor.run { [weak self] in
                self?.scanResult = result
                self?.currentNode = result?.root
                self?.isScanning = false
            }
        }
    }

    @Published var isLoadingCache = false

    /// Whether a cached scan exists on disk
    var hasCachedResult: Bool {
        guard let cacheURL else { return false }
        return fileManager.fileExists(atPath: cacheURL.path)
    }

    /// Load cached scan result asynchronously (off main thread)
    func loadCachedResult() {
        guard scanResult == nil, !isLoadingCache else { return }
        isLoadingCache = true

        Task { [weak self] in
            let result = await Task.detached(priority: .userInitiated) { [weak self] () -> DirectoryScanResult? in
                guard let self else { return nil }
                guard let loaded = self.loadFromDisk() else { return nil }
                loaded.root.rebuildParentReferences()
                return loaded
            }.value

            await MainActor.run { [weak self] in
                if let result {
                    self?.scanResult = result
                    self?.currentNode = result.root
                }
                self?.isLoadingCache = false
            }
        }
    }

    func cancel() {
        scanTask?.cancel()
        scanTask = nil
        Task { @MainActor [weak self] in
            self?.isScanning = false
        }
    }

    private func performScan(rootPath: String, startTime: Date) async -> DirectoryScanResult? {
        return await Task.detached(priority: .userInitiated) { [weak self] () -> DirectoryScanResult? in
            guard let self else { return nil }
            var filesCount = 0
            var directoriesCount = 0
            var scannedCount = 0

            func buildTree(at url: URL, parent: FileNode?) -> FileNode {
                let node = FileNode(
                    name: url.lastPathComponent,
                    size: 0,
                    isDirectory: true
                )
                node.parent = parent
                directoriesCount += 1

                guard let contents = try? self.fileManager.contentsOfDirectory(
                    at: url,
                    includingPropertiesForKeys: [.fileSizeKey, .isDirectoryKey],
                    options: []
                ) else {
                    node.accessDenied = true
                    return node
                }

                var children: [FileNode] = []
                var totalSize: Int64 = 0

                for itemURL in contents {
                    if Task.isCancelled { break }

                    let values = try? itemURL.resourceValues(forKeys: [.fileSizeKey, .isDirectoryKey])
                    let isDir = values?.isDirectory ?? false

                    if isDir {
                        let childNode = buildTree(at: itemURL, parent: node)
                        totalSize += childNode.size
                        children.append(childNode)
                    } else {
                        let fileSize = Int64(values?.fileSize ?? 0)
                        let childNode = FileNode(
                            name: itemURL.lastPathComponent,
                            size: fileSize,
                            isDirectory: false
                        )
                        childNode.parent = node
                        totalSize += fileSize
                        filesCount += 1
                        children.append(childNode)
                    }

                    scannedCount += 1
                    if scannedCount % 1000 == 0 {
                        let count = scannedCount
                        let currentPath = url.lastPathComponent
                        Task { @MainActor [weak self] in
                            self?.progress = ScanProgress(filesScanned: count, currentPath: currentPath)
                        }
                    }
                }

                node.children = children.sorted { $0.size > $1.size }
                node.size = totalSize
                return node
            }

            let rootURL = URL(fileURLWithPath: rootPath)
            let root = buildTree(at: rootURL, parent: nil)

            guard !Task.isCancelled else { return nil }

            return DirectoryScanResult(
                root: root,
                totalSize: root.size,
                totalFiles: filesCount,
                totalDirectories: directoriesCount,
                scanDuration: Date().timeIntervalSince(startTime),
                scanDate: Date()
            )
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
        if node.accessDenied { return false }
        if node.id == scanResult?.root.id { return false }
        return !isPathProtected(node.path)
    }

    func deleteSingleItem(_ node: FileNode) async -> DeletionResult {
        await deleteNodes([node])
    }

    func deleteSelectedItems() async -> DeletionResult {
        guard let current = currentNode else {
            return DeletionResult(successCount: 0, failedCount: 0, freedSize: 0)
        }
        let nodes = current.findNodes(withIDs: selectedItems)
        let result = await deleteNodes(nodes)
        await MainActor.run { [weak self] in
            self?.selectedItems.removeAll()
        }
        return result
    }

    private func deleteNodes(_ nodes: [FileNode]) async -> DeletionResult {
        var successCount = 0
        var failedCount = 0
        var freedSize: Int64 = 0

        for node in nodes {
            guard isNodeDeletable(node) else {
                logger.warning("Skipped non-deletable path: \(node.path, privacy: .public)")
                failedCount += 1
                continue
            }

            guard fileManager.fileExists(atPath: node.path) else {
                logger.info("Item no longer exists, skipping: \(node.path, privacy: .public)")
                failedCount += 1
                continue
            }

            do {
                if deleteMode == .trash {
                    try fileManager.trashItem(at: URL(fileURLWithPath: node.path), resultingItemURL: nil)
                } else {
                    try fileManager.removeItem(atPath: node.path)
                }
                freedSize += node.size
                successCount += 1

                await MainActor.run { [weak self] in
                    node.parent?.removeChild(node)
                    self?.objectWillChange.send()
                }
            } catch {
                logger.error("Failed to delete \(node.name, privacy: .public): \(error.localizedDescription, privacy: .public)")
                failedCount += 1
            }
        }

        return DeletionResult(successCount: successCount, failedCount: failedCount, freedSize: freedSize)
    }

    private func isPathProtected(_ path: String) -> Bool {
        let normalized = URL(fileURLWithPath: path).standardized.path
        for prefix in protectedPrefixes {
            if normalized == prefix || normalized.hasPrefix(prefix + "/") {
                return true
            }
        }
        return false
    }

    // MARK: - Persistence

    private func saveToDisk(_ result: DirectoryScanResult) {
        guard let cacheURL else { return }

        do {
            let directory = cacheURL.deletingLastPathComponent()
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

            let encoder = PropertyListEncoder()
            encoder.outputFormat = .binary
            let data = try encoder.encode(result)
            let compressed = try (data as NSData).compressed(using: .lzfse) as Data
            try compressed.write(to: cacheURL, options: .atomic)

            logger.info("Saved scan cache (\(compressed.count) bytes compressed)")
        } catch {
            logger.error("Failed to save scan cache: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func loadFromDisk() -> DirectoryScanResult? {
        guard let cacheURL, fileManager.fileExists(atPath: cacheURL.path) else { return nil }

        do {
            let compressed = try Data(contentsOf: cacheURL)
            let data = try (compressed as NSData).decompressed(using: .lzfse) as Data
            let result = try PropertyListDecoder().decode(DirectoryScanResult.self, from: data)

            logger.info("Loaded scan cache from \(result.formattedScanDate)")
            return result
        } catch {
            logger.error("Failed to load scan cache: \(error.localizedDescription, privacy: .public)")
            try? fileManager.removeItem(at: cacheURL)
            return nil
        }
    }
}
