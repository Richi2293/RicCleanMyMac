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

struct DeletionResult {
    let successCount: Int
    let failedCount: Int
    let freedSize: Int64

    var totalCount: Int { successCount + failedCount }
    var isFullSuccess: Bool { failedCount == 0 && successCount > 0 }
    var isFullFailure: Bool { successCount == 0 && failedCount > 0 }
}
