import Foundation

struct DirectoryScanResult {
    let root: FileNode
    let totalFiles: Int
    let totalDirectories: Int
    let scanDuration: TimeInterval
    let scanDate: Date

    /// Derived from `root.size` to avoid divergence after mutations (e.g. deletion).
    var totalSize: Int64 { root.size }

    init(
        root: FileNode,
        totalFiles: Int,
        totalDirectories: Int,
        scanDuration: TimeInterval,
        scanDate: Date
    ) {
        precondition(totalFiles >= 0, "totalFiles must be non-negative")
        precondition(totalDirectories >= 0, "totalDirectories must be non-negative")
        precondition(scanDuration >= 0, "scanDuration must be non-negative")
        self.root = root
        self.totalFiles = totalFiles
        self.totalDirectories = totalDirectories
        self.scanDuration = scanDuration
        self.scanDate = scanDate
    }

    var formattedScanDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: scanDate)
    }

    var formattedDuration: String {
        let minutes = Int(scanDuration) / 60
        let seconds = Int(scanDuration) % 60
        if minutes > 0 {
            return "\(minutes)m \(seconds)s"
        }
        return "\(seconds)s"
    }
}
