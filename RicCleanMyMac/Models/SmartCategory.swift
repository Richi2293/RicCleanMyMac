import Foundation

nonisolated struct SmartCategory: Identifiable {
    let id: String
    let name: String
    let icon: String
    let totalSize: Int64
    let nodeIDs: [ObjectIdentifier]

    @MainActor var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: totalSize, countStyle: .file)
    }
}
