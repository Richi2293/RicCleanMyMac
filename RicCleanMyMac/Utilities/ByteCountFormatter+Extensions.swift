import Foundation

extension ByteCountFormatter {
    /// Convenience method to format byte count as file size string
    /// - Parameter byteCount: The number of bytes to format
    /// - Returns: Formatted string (e.g., "1.5 GB")
    static func string(fromByteCount byteCount: Int64, countStyle: CountStyle = .file) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = countStyle
        formatter.allowedUnits = [.useKB, .useMB, .useGB, .useTB]
        return formatter.string(fromByteCount: byteCount)
    }
}

