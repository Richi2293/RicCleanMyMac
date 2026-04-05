import Foundation
import os

private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "RicCleanMyMac", category: "FileManager")

extension FileManager {
    /// Calculate the total size of a directory recursively
    /// - Parameter url: The directory URL to calculate size for
    /// - Returns: Total size in bytes, or nil if calculation fails
    func directorySize(at url: URL) -> Int64? {
        guard fileExists(atPath: url.path) else {
            return nil
        }

        guard let enumerator = enumerator(
            at: url,
            includingPropertiesForKeys: [.fileSizeKey, .isDirectoryKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            logger.warning("Failed to create enumerator for \(url.path, privacy: .public)")
            return nil
        }

        var totalSize: Int64 = 0

        for case let fileURL as URL in enumerator {
            if let isDirectory = try? fileURL.resourceValues(forKeys: [.isDirectoryKey]).isDirectory,
               isDirectory == true {
                continue
            }

            if let resourceValues = try? fileURL.resourceValues(forKeys: [.fileSizeKey]),
               let fileSize = resourceValues.fileSize {
                totalSize += Int64(fileSize)
            }
        }

        return totalSize > 0 ? totalSize : nil
    }

    /// Safely remove an item at the specified path
    /// - Parameter path: The path to remove
    /// - Throws: The underlying file system error if removal fails
    func safeRemoveItem(atPath path: String) throws {
        guard fileExists(atPath: path) else {
            logger.info("Item does not exist, skipping: \(path, privacy: .public)")
            return
        }

        do {
            try removeItem(atPath: path)
            logger.info("Removed: \(path, privacy: .public)")
        } catch {
            logger.error("Failed to remove \(path, privacy: .public): \(error.localizedDescription, privacy: .public)")
            throw error
        }
    }

    /// Validate that a path is within allowed safe directories
    /// - Parameters:
    ///   - path: The path to validate
    ///   - allowedDirectories: List of allowed directory paths
    /// - Returns: True if path is within allowed directories, false otherwise
    func isPathSafe(_ path: String, within allowedDirectories: [String]) -> Bool {
        let normalizedPath = URL(fileURLWithPath: path).standardized.path

        for allowedDir in allowedDirectories {
            let normalizedAllowed = URL(fileURLWithPath: allowedDir).standardized.path
            if normalizedPath == normalizedAllowed || normalizedPath.hasPrefix(normalizedAllowed + "/") {
                return true
            }
        }

        return false
    }
}
