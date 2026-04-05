import Foundation
import Combine

/// Result of a cleanup operation
struct CleanupResult {
    let successCount: Int
    let freedSize: Int64
}

/// Main service for orchestrating cleanup operations
class CleanupService: ObservableObject {
    @Published var cleanupItems: [CleanupItem] = []
    @Published var isScanning = false
    @Published var scanProgressLabel: String = ""
    @Published var totalSize: Int64 = 0
    @Published var diskSpace: DiskSpace?
    @Published var spaceUsageItems: [SpaceUsageItem] = []
    @Published var isScanningSpaceUsage = false

    private let fileScanner = FileScanner()
    private let diskAnalyzer = DiskAnalyzer()
    private let fileManager = FileManager.default

    // Whitelist of safe directories that can be cleaned
    private let allowedDirectories: [String] = {
        var directories: [String] = []

        if let cacheURL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first {
            directories.append(cacheURL.path)
        }

        if let libraryURL = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first {
            let logsURL = libraryURL.appendingPathComponent("Logs")
            directories.append(logsURL.path)
        }

        directories.append(FileManager.default.temporaryDirectory.path)

        let homeURL = URL(fileURLWithPath: NSHomeDirectory())
        directories.append(homeURL.appendingPathComponent("Downloads").path)
        directories.append(homeURL.appendingPathComponent(".Trash").path)

        return directories
    }()

    init() {
        Task {
            await updateDiskSpace()
            await scanSpaceUsage()
        }
    }

    /// Scan for cleanup items (read-only operation)
    func scan() async {
        await MainActor.run {
            isScanning = true
            cleanupItems.removeAll()
            totalSize = 0
            scanProgressLabel = ""
        }

        let items = await fileScanner.scanForCleanupItems { [weak self] label in
            Task { @MainActor [weak self] in
                self?.scanProgressLabel = label
            }
        }

        let total = items.reduce(Int64(0)) { $0 + $1.size }

        await MainActor.run {
            cleanupItems = items
            totalSize = total
            isScanning = false
            scanProgressLabel = ""
        }

        await updateDiskSpace()
    }

    /// Clean up selected items (only after user confirmation)
    /// - Parameter items: Array of CleanupItem to clean up
    /// - Returns: CleanupResult with success count and freed size, or nil if validation failed
    func cleanup(items: [CleanupItem]) async -> CleanupResult? {
        for item in items {
            guard fileManager.isPathSafe(item.path, within: allowedDirectories) else {
                print("Error: Path \(item.path) is not in allowed directories")
                return nil
            }
        }

        var successCount = 0
        var freedSize: Int64 = 0

        for item in items {
            if fileManager.safeRemoveItem(atPath: item.path) {
                successCount += 1
                freedSize += item.size
            }
        }

        await scan()

        return CleanupResult(successCount: successCount, freedSize: freedSize)
    }

    /// Update disk space information
    private func updateDiskSpace() async {
        let space = await diskAnalyzer.getDiskSpace()
        await MainActor.run {
            diskSpace = space
        }
    }

    /// Scan user directories for space usage
    func scanSpaceUsage() async {
        await MainActor.run {
            isScanningSpaceUsage = true
        }

        let items = await diskAnalyzer.scanUserDirectories()

        await MainActor.run {
            spaceUsageItems = items
            isScanningSpaceUsage = false
        }
    }
}
