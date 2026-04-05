import Foundation

final class FileNode: Identifiable {
    let id = UUID()
    let name: String
    let path: String
    var size: Int64
    let isDirectory: Bool
    var accessDenied: Bool
    var children: [FileNode]?
    weak var parent: FileNode?

    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }

    var icon: String {
        if isDirectory {
            return accessDenied ? "folder.badge.questionmark" : "folder.fill"
        }
        return fileIcon(for: name)
    }

    init(name: String, path: String, size: Int64, isDirectory: Bool, accessDenied: Bool = false) {
        self.name = name
        self.path = path
        self.size = size
        self.isDirectory = isDirectory
        self.accessDenied = accessDenied
    }

    var relativeSize: Double {
        guard let parent, parent.size > 0 else { return 1.0 }
        return Double(size) / Double(parent.size)
    }

    func removeChild(_ child: FileNode) {
        guard let index = children?.firstIndex(where: { $0.id == child.id }) else { return }
        children?.remove(at: index)
        recalculateSizeToRoot()
    }

    private func recalculateSizeToRoot() {
        if let children {
            size = children.reduce(Int64(0)) { $0 + $1.size }
        }
        parent?.recalculateSizeToRoot()
    }

    func findNodes(withIDs ids: Set<UUID>) -> [FileNode] {
        var result: [FileNode] = []
        if ids.contains(id) { result.append(self) }
        if let children {
            for child in children {
                result.append(contentsOf: child.findNodes(withIDs: ids))
            }
        }
        return result
    }

    private func fileIcon(for name: String) -> String {
        let ext = (name as NSString).pathExtension.lowercased()
        switch ext {
        case "mp4", "mov", "avi", "mkv":
            return "film"
        case "mp3", "wav", "aac", "flac":
            return "music.note"
        case "jpg", "jpeg", "png", "gif", "heic", "webp":
            return "photo"
        case "pdf":
            return "doc.richtext"
        case "zip", "tar", "gz", "rar", "7z", "dmg":
            return "doc.zipper"
        case "app":
            return "app.gift"
        default:
            return "doc.fill"
        }
    }
}

extension FileNode: Hashable {
    static func == (lhs: FileNode, rhs: FileNode) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

// MARK: - Codable

extension FileNode: Codable {
    enum CodingKeys: String, CodingKey {
        case name, path, size, isDirectory, accessDenied, children
    }

    convenience init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            name: try container.decode(String.self, forKey: .name),
            path: try container.decode(String.self, forKey: .path),
            size: try container.decode(Int64.self, forKey: .size),
            isDirectory: try container.decode(Bool.self, forKey: .isDirectory),
            accessDenied: try container.decode(Bool.self, forKey: .accessDenied)
        )
        self.children = try container.decodeIfPresent([FileNode].self, forKey: .children)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encode(path, forKey: .path)
        try container.encode(size, forKey: .size)
        try container.encode(isDirectory, forKey: .isDirectory)
        try container.encode(accessDenied, forKey: .accessDenied)
        try container.encodeIfPresent(children, forKey: .children)
    }

    /// Rebuild weak parent references after decoding from cache
    func rebuildParentReferences() {
        guard let children else { return }
        for child in children {
            child.parent = self
            child.rebuildParentReferences()
        }
    }
}
