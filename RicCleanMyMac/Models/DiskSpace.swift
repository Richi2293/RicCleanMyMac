import Foundation

/// Model representing disk space information
struct DiskSpace {
    let total: Int64
    /// Raw available space (what's actually free right now)
    let available: Int64
    /// Available space including purgeable (what macOS reports to the user)
    let availableForImportantUsage: Int64

    var used: Int64 { total - available }
    var purgeable: Int64 { availableForImportantUsage - available }

    var formattedTotal: String {
        ByteCountFormatter.string(fromByteCount: total, countStyle: .file)
    }

    var formattedUsed: String {
        ByteCountFormatter.string(fromByteCount: used, countStyle: .file)
    }

    var formattedAvailable: String {
        ByteCountFormatter.string(fromByteCount: available, countStyle: .file)
    }

    var formattedAvailableForImportantUsage: String {
        ByteCountFormatter.string(fromByteCount: availableForImportantUsage, countStyle: .file)
    }

    var formattedPurgeable: String {
        ByteCountFormatter.string(fromByteCount: purgeable, countStyle: .file)
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
