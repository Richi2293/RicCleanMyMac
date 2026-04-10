import Foundation

struct ScanProgress {
    let filesScanned: Int
    let currentPath: String
}

enum DeleteMode: String, CaseIterable {
    case trash = "Trash"
    case permanent = "Permanent"

    var icon: String {
        switch self {
        case .trash: return "trash"
        case .permanent: return "xmark.bin"
        }
    }
}

struct DeletionFailure: Identifiable {
    let id = UUID()
    let path: String
    let reason: String
}

struct DeletionResult {
    let successCount: Int
    let freedSize: Int64
    let failures: [DeletionFailure]

    var failedCount: Int { failures.count }
    var totalCount: Int { successCount + failedCount }
    var isFullSuccess: Bool { failedCount == 0 && successCount > 0 }
    var isFullFailure: Bool { successCount == 0 && failedCount > 0 }
}

/// User-facing errors surfaced by `DirectoryScanner`.
enum ScanError: Identifiable {
    case scanFailed(String)
    case cacheLoadFailed(String)
    case cacheSaveFailed(String)
    case deletionFailed(failures: [DeletionFailure])

    var id: String {
        switch self {
        case .scanFailed: return "scanFailed"
        case .cacheLoadFailed: return "cacheLoadFailed"
        case .cacheSaveFailed: return "cacheSaveFailed"
        case .deletionFailed: return "deletionFailed"
        }
    }

    var title: String {
        switch self {
        case .scanFailed: return "Scan Failed"
        case .cacheLoadFailed: return "Could Not Load Previous Scan"
        case .cacheSaveFailed: return "Could Not Save Scan Cache"
        case .deletionFailed: return "Some Items Could Not Be Deleted"
        }
    }

    var message: String {
        switch self {
        case .scanFailed(let reason):
            return reason
        case .cacheLoadFailed(let reason):
            return "The cached scan was corrupted or unreadable and has been discarded. \(reason)"
        case .cacheSaveFailed(let reason):
            return "The scan results could not be cached to disk, so re-opening the analyzer will trigger a full re-scan. \(reason)"
        case .deletionFailed(let failures):
            let preview = failures.prefix(5).map { "• \($0.path) — \($0.reason)" }.joined(separator: "\n")
            let suffix = failures.count > 5 ? "\n…and \(failures.count - 5) more." : ""
            return preview + suffix
        }
    }
}
