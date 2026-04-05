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
}
