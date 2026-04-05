import Foundation

struct DirectoryScanResult: Codable {
    let root: FileNode
    let totalSize: Int64
    let totalFiles: Int
    let totalDirectories: Int
    let scanDuration: TimeInterval
    let scanDate: Date

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
