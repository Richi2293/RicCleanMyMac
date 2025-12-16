import Foundation

/// Model representing a path and its disk space usage
struct SpaceUsageItem: Identifiable {
    let id = UUID()
    let name: String
    let path: String
    let size: Int64
    
    /// Formatted size string
    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }
    
    /// Display name (last component of path or custom name)
    var displayName: String {
        name.isEmpty ? (URL(fileURLWithPath: path).lastPathComponent) : name
    }
}

