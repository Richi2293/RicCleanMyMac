import Foundation

/// The scanner's verdict on a node, capturing both policy decisions
/// (`.readOnly`, `.skipped`) and runtime failures (`.inaccessible`).
///
/// Distinct from `ScanPolicy.Classification`: that type drives the
/// traversal decision in `buildTree`; this type records the outcome on
/// the persisted node. They deliberately carry parallel-looking cases
/// so that mapping from one to the other at scan time is mechanical.
enum NodeStatus: Equatable {
    /// Traversed normally. Deletable from the UI.
    case normal

    /// Traversed and measured, but protected by `ScanPolicy`. Not deletable.
    case readOnly

    /// Not traversed at all — placeholder node with `size == 0`.
    case skipped(reason: String)

    /// The directory existed but could not be read (permissions, I/O error).
    /// Treated as non-deletable.
    case inaccessible
}

final class FileNode: Identifiable {
    var id: ObjectIdentifier { ObjectIdentifier(self) }
    let name: String
    let isDirectory: Bool
    private(set) var size: Int64
    private(set) var status: NodeStatus
    private(set) var children: [FileNode]?
    private(set) weak var parent: FileNode?

    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }

    var icon: String {
        if isDirectory {
            switch status {
            case .inaccessible: return "folder.badge.questionmark"
            case .skipped: return "folder.badge.minus"
            case .readOnly: return "folder.badge.gearshape"
            case .normal: return "folder.fill"
            }
        }
        return fileIcon(for: name)
    }

    /// Reconstructs the absolute path by walking up the parent chain iteratively.
    /// The root node's name is the absolute path (e.g. "/" or "/Users/foo"); descendants
    /// contribute their lastPathComponent. Synthetic nodes with no parent (e.g. the
    /// "Other" aggregate in the sunburst chart) return their raw name.
    var path: String {
        var names: [String] = []
        var current: FileNode? = self
        while let node = current {
            names.append(node.name)
            current = node.parent
        }
        names.reverse()
        guard let first = names.first else { return "" }
        if names.count == 1 { return first }
        let rest = names.dropFirst().joined(separator: "/")
        return first.hasSuffix("/") ? first + rest : first + "/" + rest
    }

    private init(name: String, size: Int64, isDirectory: Bool, status: NodeStatus) {
        self.name = name
        self.size = size
        self.isDirectory = isDirectory
        self.status = status
    }

    // MARK: - Factories

    /// Creates a leaf file node with no children and no parent.
    /// The caller attaches it to a parent via `FileNode.directory(..., children:)`.
    static func file(name: String, size: Int64, status: NodeStatus = .normal) -> FileNode {
        FileNode(name: name, size: size, isDirectory: false, status: status)
    }

    /// Creates a directory node and wires parent links on its children in one step.
    /// Pass `size` explicitly when the value is authoritative (e.g. reading from cache);
    /// otherwise it is computed as the sum of children's sizes.
    static func directory(
        name: String,
        children: [FileNode],
        size: Int64? = nil,
        status: NodeStatus = .normal
    ) -> FileNode {
        let totalSize = size ?? children.reduce(Int64(0)) { $0 + $1.size }
        let node = FileNode(name: name, size: totalSize, isDirectory: true, status: status)
        node.children = children
        for child in children {
            child.parent = node
        }
        return node
    }

    /// Creates a directory node that could not be read (permission denied, I/O error).
    static func inaccessibleDirectory(name: String) -> FileNode {
        FileNode(name: name, size: 0, isDirectory: true, status: .inaccessible)
    }

    /// Convenience for creating a placeholder node for a directory the scanner
    /// chose not to traverse because `ScanPolicy` returned `.skipped`.
    static func skippedDirectory(name: String, reason: String) -> FileNode {
        FileNode(name: name, size: 0, isDirectory: true, status: .skipped(reason: reason))
    }

    // MARK: - Mutations

    var relativeSize: Double {
        guard let parent, parent.size > 0 else { return 1.0 }
        return Double(size) / Double(parent.size)
    }

    func removeChild(_ child: FileNode) {
        guard var current = children,
              let index = current.firstIndex(where: { $0 === child }) else { return }
        current.remove(at: index)
        children = current
        recalculateSizeToRoot()
    }

    private func recalculateSizeToRoot() {
        if let children {
            size = children.reduce(Int64(0)) { $0 + $1.size }
        }
        parent?.recalculateSizeToRoot()
    }

    func findNodes(withIDs ids: Set<ObjectIdentifier>) -> [FileNode] {
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
        lhs === rhs
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(ObjectIdentifier(self))
    }
}
