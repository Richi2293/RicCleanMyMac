import Foundation

/// The scanner's verdict on a node, capturing both policy decisions
/// (`.readOnly`, `.skipped`) and runtime failures (`.inaccessible`).
///
/// Distinct from `ScanPolicy.Classification`: that type drives the
/// traversal decision in `buildTree`; this type records the outcome on
/// the persisted node. They deliberately carry parallel-looking cases
/// so that mapping from one to the other at scan time is mechanical.
nonisolated enum NodeStatus: Equatable {
    /// Traversed normally. Deletable from the UI.
    case normal

    /// Traversed and measured, but protected by `ScanPolicy`. Not deletable.
    case readOnly

    /// Not traversed at all: placeholder node with `size == 0`.
    case skipped(reason: String)

    /// The directory existed but could not be read (permissions, I/O error).
    /// Treated as non-deletable.
    case inaccessible
}

///
/// Threading: a tree is built off the main thread (scan or cache read), then
/// handed to `DirectoryScanner` on the main thread, which is the only place
/// that mutates it. Background work may read a tree only while no mutation
/// can run; `DirectoryScanner` enforces this by waiting for cache saves
/// before deleting. Hence `@unchecked Sendable`.
nonisolated final class FileNode: Identifiable, @unchecked Sendable {
    var id: ObjectIdentifier { ObjectIdentifier(self) }
    let name: String
    let isDirectory: Bool
    private(set) var size: Int64
    private(set) var status: NodeStatus
    private(set) var children: [FileNode]?
    private(set) weak var parent: FileNode?

    /// `true` when at least one descendant is not `.normal` (read-only, skipped
    /// or inaccessible). Deleting such a folder would also delete, or try to
    /// delete, content the scan policy protects, so the UI must refuse it.
    private(set) var containsProtectedItems = false

    @MainActor var formattedSize: String {
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
    ///
    /// Files inside a `.readOnly` directory inherit `.readOnly`: the scan policy
    /// classifies directories only, and a file is as protected as its folder.
    /// Applying the rule here covers both fresh scans and older caches.
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
            if status == .readOnly, !child.isDirectory, child.status == .normal {
                child.status = .readOnly
            }
        }
        node.containsProtectedItems = Self.anyProtected(in: children)
        return node
    }

    private static func anyProtected(in children: [FileNode]) -> Bool {
        children.contains { $0.status != .normal || $0.containsProtectedItems }
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
        guard let parent else { return 1.0 }
        guard parent.size > 0 else { return 0 }
        return Double(size) / Double(parent.size)
    }

    func removeChild(_ child: FileNode) {
        removeChildren(withIDs: [child.id])
    }

    /// Removes several children at once, recalculating sizes up the chain a
    /// single time. Removing them one by one costs children x removals.
    func removeChildren(withIDs ids: Set<ObjectIdentifier>) {
        guard let current = children, !ids.isEmpty else { return }
        let remaining = current.filter { !ids.contains($0.id) }
        guard remaining.count != current.count else { return }
        children = remaining
        recalculateSizeToRoot()
    }

    /// Puts `replacement` in place of `child`, for a folder measured again
    /// after a deletion failed halfway. Children stay sorted by size.
    func replaceChild(_ child: FileNode, with replacement: FileNode) {
        guard var current = children,
              let index = current.firstIndex(where: { $0 === child }) else { return }
        current[index] = replacement
        current.sort { $0.size > $1.size }
        children = current
        replacement.parent = self
        recalculateSizeToRoot()
    }

    /// `true` when `self` is `node` or lies somewhere inside it.
    func isWithin(_ node: FileNode) -> Bool {
        var current: FileNode? = self
        while let candidate = current {
            if candidate === node { return true }
            current = candidate.parent
        }
        return false
    }

    private func recalculateSizeToRoot() {
        if let children {
            size = children.reduce(Int64(0)) { $0 + $1.size }
            containsProtectedItems = Self.anyProtected(in: children)
        }
        parent?.recalculateSizeToRoot()
    }

    /// `true` when the scan policy allows deleting this node: it is `.normal`
    /// and holds no protected content. `DirectoryScanner` adds its own
    /// checks (scan root, home folder) on top.
    var isDeletableByPolicy: Bool {
        status == .normal && !containsProtectedItems
    }

    // MARK: - Smart categories

    /// Groups well-known expendable folders and large files found under this
    /// node. Only nodes the policy lets the user delete are counted, so the
    /// totals show space that can really be freed.
    func extractSmartCategories(
        homeDirectory: String = FileManager.default.homeDirectoryForCurrentUser.path
    ) -> [SmartCategory] {
        var cacheNodes: [FileNode] = []
        var logNodes: [FileNode] = []
        var tempNodes: [FileNode] = []
        var downloadsNodes: [FileNode] = []
        var largeFileNodes: [FileNode] = []

        let largeFileThreshold: Int64 = 1_073_741_824 // 1 GB
        let downloadsPath = URL(fileURLWithPath: homeDirectory)
            .appendingPathComponent("Downloads").standardizedFileURL.path.lowercased()

        func walk(_ node: FileNode) {
            if node.isDirectory {
                if node.isDeletableByPolicy {
                    let lower = node.name.lowercased()
                    // A matching folder counts as a whole: its subtree is not visited.
                    if lower == "caches" || lower == ".cache" {
                        cacheNodes.append(node)
                        return
                    }
                    if lower == "logs" {
                        logNodes.append(node)
                        return
                    }
                    if lower == "tmp" || lower == "temporary items" {
                        tempNodes.append(node)
                        return
                    }
                    if lower == "downloads", node.path.lowercased() == downloadsPath {
                        downloadsNodes.append(node)
                        return
                    }
                }
                for child in node.children ?? [] {
                    walk(child)
                }
            } else if node.isDeletableByPolicy {
                if (node.name as NSString).pathExtension.lowercased() == "log" {
                    logNodes.append(node)
                }
                if node.size >= largeFileThreshold {
                    largeFileNodes.append(node)
                }
            }
        }

        for child in children ?? [] {
            walk(child)
        }

        let candidates = [
            SmartCategory(id: "cache", name: "Cache", icon: "archivebox", nodes: cacheNodes),
            SmartCategory(id: "log", name: "Log", icon: "doc.text", nodes: logNodes),
            SmartCategory(id: "temp", name: "Temp", icon: "clock.arrow.circlepath", nodes: tempNodes),
            SmartCategory(id: "downloads", name: "Downloads", icon: "arrow.down.circle", nodes: downloadsNodes),
            SmartCategory(id: "largeFiles", name: "Large files", icon: "doc.badge.ellipsis", nodes: largeFileNodes)
        ]
        return candidates
            .filter { $0.totalSize > 0 }
            .sorted { $0.totalSize > $1.totalSize }
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

nonisolated extension FileNode: Hashable {
    static func == (lhs: FileNode, rhs: FileNode) -> Bool {
        lhs === rhs
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(ObjectIdentifier(self))
    }
}
