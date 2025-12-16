import Foundation

/// Service for analyzing disk space information
class DiskAnalyzer {
    private let fileManager = FileManager.default
    
    /// Get current disk space information
    /// - Returns: DiskSpace model with total, used, and available space
    func getDiskSpace() async -> DiskSpace? {
        return await Task.detached(priority: .userInitiated) {
            guard let homeURL = self.fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
                return nil
            }
            
            let volumeURL = homeURL.deletingLastPathComponent()
            
            guard let resourceValues = try? volumeURL.resourceValues(forKeys: [
                .volumeTotalCapacityKey,
                .volumeAvailableCapacityKey
            ]) else {
                return nil
            }
            
            guard let totalCapacity = resourceValues.volumeTotalCapacity,
                  let availableCapacity = resourceValues.volumeAvailableCapacity else {
                return nil
            }
            
            let total = Int64(totalCapacity)
            let available = Int64(availableCapacity)
            let used = total - available
            
            return DiskSpace(
                total: total,
                used: used,
                available: available
            )
        }.value
    }
    
    /// Scan main user directories to find space usage
    /// - Returns: Array of SpaceUsageItem sorted by size (largest first)
    func scanUserDirectories() async -> [SpaceUsageItem] {
        return await Task.detached(priority: .userInitiated) {
            var items: [SpaceUsageItem] = []
            
            // Get home directory
            let homeURL = URL(fileURLWithPath: NSHomeDirectory())
            
            // Main directories to scan
            let directoriesToScan: [(String, URL?)] = [
                ("Documents", self.fileManager.urls(for: .documentDirectory, in: .userDomainMask).first),
                ("Downloads", homeURL.appendingPathComponent("Downloads")),
                ("Desktop", homeURL.appendingPathComponent("Desktop")),
                ("Library", self.fileManager.urls(for: .libraryDirectory, in: .userDomainMask).first),
                ("Movies", homeURL.appendingPathComponent("Movies")),
                ("Music", homeURL.appendingPathComponent("Music")),
                ("Pictures", homeURL.appendingPathComponent("Pictures")),
                ("Applications", homeURL.appendingPathComponent("Applications"))
            ]
            
            // Scan each directory
            for (name, urlOptional) in directoriesToScan {
                guard let url = urlOptional else {
                    continue
                }
                
                guard self.fileManager.fileExists(atPath: url.path) else {
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
            
            // Sort by size (largest first)
            return items.sorted { $0.size > $1.size }
        }.value
    }
}

