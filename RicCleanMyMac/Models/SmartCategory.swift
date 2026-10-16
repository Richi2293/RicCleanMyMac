import Foundation

nonisolated struct SmartCategory: Identifiable {
    let id: String
    let name: String
    let icon: String
    /// The matching nodes, largest first.
    let nodes: [FileNode]
    let totalSize: Int64

    init(id: String, name: String, icon: String, nodes: [FileNode]) {
        self.id = id
        self.name = name
        self.icon = icon
        self.nodes = nodes.sorted { $0.size > $1.size }
        self.totalSize = nodes.reduce(Int64(0)) { $0 + $1.size }
    }

    @MainActor var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: totalSize, countStyle: .file)
    }
}
