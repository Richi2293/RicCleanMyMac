import Foundation

/// Model representing disk space information
struct DiskSpace {
    let total: Int64
    let used: Int64
    let available: Int64
    
    /// Formatted total disk space
    var formattedTotal: String {
        ByteCountFormatter.string(fromByteCount: total, countStyle: .file)
    }
    
    /// Formatted used disk space
    var formattedUsed: String {
        ByteCountFormatter.string(fromByteCount: used, countStyle: .file)
    }
    
    /// Formatted available disk space
    var formattedAvailable: String {
        ByteCountFormatter.string(fromByteCount: available, countStyle: .file)
    }
    
    /// Percentage of disk used (0.0 to 1.0)
    var usedPercentage: Double {
        guard total > 0 else { return 0.0 }
        return Double(used) / Double(total)
    }
    
    /// Percentage of disk available (0.0 to 1.0)
    var availablePercentage: Double {
        guard total > 0 else { return 0.0 }
        return Double(available) / Double(total)
    }
}

