import Foundation

struct DirectoryScanResult {
    let root: FileNode
    let totalSize: Int64
    let totalFiles: Int
    let totalDirectories: Int
    let scanDuration: TimeInterval
}
