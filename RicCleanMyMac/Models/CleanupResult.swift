import Foundation

/// Result of a cleanup operation
struct CleanupResult {
    let successCount: Int
    let failedCount: Int
    let freedSize: Int64

    var totalCount: Int { successCount + failedCount }
    var isFullSuccess: Bool { failedCount == 0 && successCount > 0 }
    var isPartialSuccess: Bool { successCount > 0 && failedCount > 0 }
    var isFullFailure: Bool { successCount == 0 }
}
