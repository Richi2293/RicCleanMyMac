import Foundation
import os

private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "RicCleanMyMac", category: "DiskAnalyzer")

/// Service for analyzing disk space information
class DiskAnalyzer {
    private let fileManager = FileManager.default

    /// Get current disk space information
    /// - Returns: DiskSpace model with total and available space, or nil on failure
    func getDiskSpace() async -> DiskSpace? {
        return await Task.detached(priority: .userInitiated) {
            guard let homeURL = self.fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
                logger.error("Failed to resolve user document directory")
                return nil
            }

            let volumeURL = homeURL.deletingLastPathComponent()

            let resourceValues: URLResourceValues
            do {
                resourceValues = try volumeURL.resourceValues(forKeys: [
                    .volumeTotalCapacityKey,
                    .volumeAvailableCapacityKey
                ])
            } catch {
                logger.error("Failed to read volume resources: \(error.localizedDescription, privacy: .public)")
                return nil
            }

            guard let totalCapacity = resourceValues.volumeTotalCapacity,
                  let availableCapacity = resourceValues.volumeAvailableCapacity else {
                logger.error("Volume capacity values are nil")
                return nil
            }

            return DiskSpace(
                total: Int64(totalCapacity),
                available: Int64(availableCapacity)
            )
        }.value
    }

    /// Scan main user directories to find space usage
    /// - Returns: Array of SpaceUsageItem sorted by size (largest first)
    func scanUserDirectories() async -> [SpaceUsageItem] {
        return await Task.detached(priority: .userInitiated) {
            var items: [SpaceUsageItem] = []
            let homeURL = URL(fileURLWithPath: NSHomeDirectory())

            let directoriesToScan: [(String, URL?)] = [
                ("Documents", self.fileManager.urls(for: .documentDirectory, in: .userDomainMask).first),
                ("Downloads", homeURL.appendingPathComponent("Downloads")),
                ("Desktop", homeURL.appendingPathComponent("Desktop")),
                ("Library", self.fileManager.urls(for: .libraryDirectory, in: .userDomainMask).first),
                ("Movies", homeURL.appendingPathComponent("Movies")),
                ("Music", homeURL.appendingPathComponent("Music")),
                ("Pictures", homeURL.appendingPathComponent("Pictures")),
                ("Applications", URL(fileURLWithPath: "/Applications"))
            ]

            for (name, urlOptional) in directoriesToScan {
                guard let url = urlOptional else {
                    logger.debug("URL is nil for directory: \(name, privacy: .public)")
                    continue
                }

                guard self.fileManager.fileExists(atPath: url.path) else {
                    logger.debug("Directory does not exist: \(url.path, privacy: .public)")
                    continue
                }

                if let size = self.fileManager.directorySize(at: url), size > 0 {
                    items.append(SpaceUsageItem(
                        name: name,
                        path: url.path,
                        size: size
                    ))
                }
            }

            return items.sorted { $0.size > $1.size }
        }.value
    }
}
