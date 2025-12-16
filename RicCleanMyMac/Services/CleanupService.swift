import Foundation
import Combine

/// Main service for orchestrating cleanup operations
class CleanupService: ObservableObject {
    @Published var cleanupItems: [CleanupItem] = []
    @Published var isScanning = false
    @Published var totalSize: Int64 = 0
    @Published var diskSpace: DiskSpace?
    
    private let fileScanner = FileScanner()
    private let diskAnalyzer = DiskAnalyzer()
    private let fileManager = FileManager.default
    
    // Whitelist of safe directories that can be cleaned
    private let allowedDirectories: [String] = {
        var directories: [String] = []
        
        // User cache directory
        if let cacheURL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first {
            directories.append(cacheURL.path)
        }
        
        // User logs directory
        if let libraryURL = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first {
            let logsURL = libraryURL.appendingPathComponent("Logs")
            directories.append(logsURL.path)
        }
        
        // Temporary directory
        directories.append(FileManager.default.temporaryDirectory.path)
        
        return directories
    }()
    
    init() {
        Task {
            await updateDiskSpace()
        }
    }
    
    /// Scan for cleanup items (read-only operation)
    func scan() async {
        await MainActor.run {
            isScanning = true
            cleanupItems.removeAll()
            totalSize = 0
        }
        
        let items = await fileScanner.scanForCleanupItems()
        
        let total = items.reduce(Int64(0)) { $0 + $1.size }
        
        await MainActor.run {
            cleanupItems = items
            totalSize = total
            isScanning = false
        }
        
        await updateDiskSpace()
    }
    
    /// Clean up selected items (only after user confirmation)
    /// - Parameter items: Array of CleanupItem to clean up
    /// - Returns: Number of items successfully cleaned, or nil if validation failed
    func cleanup(items: [CleanupItem]) async -> Int? {
        // Validate all paths before proceeding
        for item in items {
            guard fileManager.isPathSafe(item.path, within: allowedDirectories) else {
                print("Error: Path \(item.path) is not in allowed directories")
                return nil
            }
        }
        
        var successCount = 0
        
        for item in items {
            if fileManager.safeRemoveItem(atPath: item.path) {
                successCount += 1
            }
        }
        
        // Rescan after cleanup
        await scan()
        
        return successCount
    }
    
    /// Update disk space information
    private func updateDiskSpace() async {
        let space = await diskAnalyzer.getDiskSpace()
        await MainActor.run {
            diskSpace = space
        }
    }
}

