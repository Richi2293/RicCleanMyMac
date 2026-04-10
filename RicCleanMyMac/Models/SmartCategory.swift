import Foundation

struct SmartCategory: Identifiable {
    let id: String
    let name: String
    let icon: String
    let totalSize: Int64
    let nodeIDs: [ObjectIdentifier]

    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: totalSize, countStyle: .file)
    }
}
