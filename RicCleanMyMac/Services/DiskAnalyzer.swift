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
}

