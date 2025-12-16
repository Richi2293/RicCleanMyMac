import Foundation

/// Model representing an item that can be cleaned up
struct CleanupItem: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let path: String
    let size: Int64
    let type: CleanupType
    
    /// Formatted size string (e.g., "1.5 GB")
    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }
}

/// Type of cleanup item
enum CleanupType: String, CaseIterable {
    case cache
    case logs
    case temp
    case downloads
    case trash
    
    /// SF Symbol icon name for this cleanup type
    var icon: String {
        switch self {
        case .cache:
            return "folder.fill"
        case .logs:
            return "doc.text.fill"
        case .temp:
            return "trash.fill"
        case .downloads:
            return "arrow.down.circle.fill"
        case .trash:
            return "trash.fill"
        }
    }
    
    /// Human-readable name for this cleanup type
    var displayName: String {
        switch self {
        case .cache:
            return "Cache"
        case .logs:
            return "Log Files"
        case .temp:
            return "Temporary Files"
        case .downloads:
            return "Downloads"
        case .trash:
            return "Trash"
        }
    }
}

