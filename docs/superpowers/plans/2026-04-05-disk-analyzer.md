# Disk Analyzer Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a Disk Analyzer feature that lets users visually explore which folders/files consume the most space, navigate the filesystem via breadcrumb drill-down, view a sunburst chart, and delete files/folders (trash or permanent).

**Architecture:** Full recursive scan builds an in-memory FileNode tree. A `DirectoryScanner` ObservableObject service owns scanning, navigation state, and deletion. The UI is a split view: navigable list (left) + sunburst chart (right), synced through the shared `currentNode`. Follows the existing MVVM-like pattern with `@EnvironmentObject` injection.

**Tech Stack:** Swift 5.7+, SwiftUI, Foundation (FileManager), Combine, macOS 12.0+

---

## File Structure

### New files

| File | Responsibility |
|------|----------------|
| `Models/FileNode.swift` | Tree node class (reference type with weak parent) |
| `Models/ScanProgress.swift` | Progress reporting struct + DeleteMode enum + DeletionResult struct |
| `Models/DirectoryScanResult.swift` | Wrapper for completed scan output |
| `Services/DirectoryScanner.swift` | ObservableObject: scanning, navigation state, deletion |
| `Views/DiskAnalyzerView.swift` | Container: toolbar + breadcrumb + HSplitView(list, sunburst) + bottom bar |
| `Views/BreadcrumbBar.swift` | Clickable path segments |
| `Views/FileListView.swift` | Navigable list with checkboxes, size bars, context menus |
| `Views/SunburstChartView.swift` | Sunburst chart with arc geometry + interactivity |
| `Views/DiskAnalyzerConfirmationSheet.swift` | Delete confirmation dialog for disk analyzer items |

### Modified files

| File | Change |
|------|--------|
| `Views/MainView.swift` | Add `.diskAnalyzer` case to `NavigationSection`, wire `DiskAnalyzerView` |

---

### Task 1: Data Models

**Files:**
- Create: `RicCleanMyMac/Models/FileNode.swift`
- Create: `RicCleanMyMac/Models/ScanProgress.swift`
- Create: `RicCleanMyMac/Models/DirectoryScanResult.swift`

- [ ] **Step 1: Create FileNode.swift**

```swift
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
        ByteCountFormatter.string(fromByteCount: size)
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

    /// Percentage of this node's size relative to parent's total size (0.0 to 1.0)
    var relativeSize: Double {
        guard let parent, parent.size > 0 else { return 1.0 }
        return Double(size) / Double(parent.size)
    }

    /// Remove a child node and recalculate sizes up to root
    func removeChild(_ child: FileNode) {
        guard let index = children?.firstIndex(where: { $0.id == child.id }) else { return }
        children?.remove(at: index)
        recalculateSizeToRoot()
    }

    /// Recalculate this node's size from its children and propagate up
    private func recalculateSizeToRoot() {
        if let children {
            size = children.reduce(Int64(0)) { $0 + $1.size }
        }
        parent?.recalculateSizeToRoot()
    }

    /// All descendant nodes (flattened) matching a set of IDs
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
```

- [ ] **Step 2: Create ScanProgress.swift**

```swift
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
```

- [ ] **Step 3: Create DirectoryScanResult.swift**

```swift
import Foundation

struct DirectoryScanResult {
    let root: FileNode
    let totalSize: Int64
    let totalFiles: Int
    let totalDirectories: Int
    let scanDuration: TimeInterval
}
```

- [ ] **Step 4: Build verification**

Run: `xcodebuild -project RicCleanMyMac.xcodeproj -scheme RicCleanMyMac build 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 5: Commit**

```bash
git add RicCleanMyMac/Models/FileNode.swift RicCleanMyMac/Models/ScanProgress.swift RicCleanMyMac/Models/DirectoryScanResult.swift
git commit -m "feat(disk-analyzer): add FileNode tree model and supporting types"
```

---

### Task 2: DirectoryScanner Service — Scanning

**Files:**
- Create: `RicCleanMyMac/Services/DirectoryScanner.swift`

- [ ] **Step 1: Create DirectoryScanner.swift with scanning logic**

```swift
import Foundation
import Combine
import os

private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "RicCleanMyMac", category: "DirectoryScanner")

final class DirectoryScanner: ObservableObject {
    @Published var isScanning = false
    @Published var progress = ScanProgress(filesScanned: 0, currentPath: "")
    @Published var scanResult: DirectoryScanResult?
    @Published var currentNode: FileNode?
    @Published var selectedItems: Set<UUID> = []
    @Published var deleteMode: DeleteMode = .trash

    private let fileManager = FileManager.default
    private var scanTask: Task<Void, Never>?

    /// Protected system paths that cannot be deleted
    private let protectedPrefixes: [String] = [
        "/System", "/usr", "/bin", "/sbin", "/private", "/Library"
    ]

    // MARK: - Scanning

    func scan(rootPath: String) {
        scanTask?.cancel()
        isScanning = true
        scanResult = nil
        currentNode = nil
        selectedItems.removeAll()
        progress = ScanProgress(filesScanned: 0, currentPath: "")

        let startTime = Date()

        scanTask = Task { [weak self] in
            guard let self else { return }

            let result = await self.performScan(rootPath: rootPath, startTime: startTime)

            guard !Task.isCancelled else { return }

            await MainActor.run { [weak self] in
                self?.scanResult = result
                self?.currentNode = result?.root
                self?.isScanning = false
            }
        }
    }

    func cancel() {
        scanTask?.cancel()
        scanTask = nil
        Task { @MainActor [weak self] in
            self?.isScanning = false
        }
    }

    private func performScan(rootPath: String, startTime: Date) async -> DirectoryScanResult? {
        return await Task.detached(priority: .userInitiated) { [weak self] () -> DirectoryScanResult? in
            guard let self else { return nil }
            var filesCount = 0
            var directoriesCount = 0
            var scannedCount = 0

            func buildTree(at url: URL, parent: FileNode?) -> FileNode {
                let node = FileNode(
                    name: url.lastPathComponent,
                    path: url.path,
                    size: 0,
                    isDirectory: true
                )
                node.parent = parent
                directoriesCount += 1

                guard let contents = try? self.fileManager.contentsOfDirectory(
                    at: url,
                    includingPropertiesForKeys: [.fileSizeKey, .isDirectoryKey],
                    options: []
                ) else {
                    node.accessDenied = true
                    return node
                }

                var children: [FileNode] = []
                var totalSize: Int64 = 0

                for itemURL in contents {
                    if Task.isCancelled { break }

                    let values = try? itemURL.resourceValues(forKeys: [.fileSizeKey, .isDirectoryKey])
                    let isDir = values?.isDirectory ?? false

                    if isDir {
                        let childNode = buildTree(at: itemURL, parent: node)
                        totalSize += childNode.size
                        children.append(childNode)
                    } else {
                        let fileSize = Int64(values?.fileSize ?? 0)
                        let childNode = FileNode(
                            name: itemURL.lastPathComponent,
                            path: itemURL.path,
                            size: fileSize,
                            isDirectory: false
                        )
                        childNode.parent = node
                        totalSize += fileSize
                        filesCount += 1
                        children.append(childNode)
                    }

                    scannedCount += 1
                    if scannedCount % 1000 == 0 {
                        let count = scannedCount
                        let currentPath = url.lastPathComponent
                        DispatchQueue.main.async { [weak self] in
                            self?.progress = ScanProgress(filesScanned: count, currentPath: currentPath)
                        }
                    }
                }

                node.children = children.sorted { $0.size > $1.size }
                node.size = totalSize
                return node
            }

            let rootURL = URL(fileURLWithPath: rootPath)
            let root = buildTree(at: rootURL, parent: nil)

            guard !Task.isCancelled else { return nil }

            return DirectoryScanResult(
                root: root,
                totalSize: root.size,
                totalFiles: filesCount,
                totalDirectories: directoriesCount,
                scanDuration: Date().timeIntervalSince(startTime)
            )
        }.value
    }

    // MARK: - Navigation

    var breadcrumbPath: [FileNode] {
        guard let current = currentNode else { return [] }
        var path: [FileNode] = [current]
        var node = current
        while let parent = node.parent {
            path.insert(parent, at: 0)
            node = parent
        }
        return path
    }

    func navigateTo(_ node: FileNode) {
        guard node.isDirectory else { return }
        selectedItems.removeAll()
        currentNode = node
    }

    func navigateToParent() {
        guard let parent = currentNode?.parent else { return }
        selectedItems.removeAll()
        currentNode = parent
    }

    // MARK: - Deletion

    func isNodeDeletable(_ node: FileNode) -> Bool {
        if node.accessDenied { return false }
        if node.id == scanResult?.root.id { return false }
        return !isPathProtected(node.path)
    }

    func deleteSingleItem(_ node: FileNode) async -> DeletionResult {
        await deleteNodes([node])
    }

    func deleteSelectedItems() async -> DeletionResult {
        guard let current = currentNode else {
            return DeletionResult(successCount: 0, failedCount: 0, freedSize: 0)
        }
        let nodes = current.findNodes(withIDs: selectedItems)
        let result = await deleteNodes(nodes)
        await MainActor.run { [weak self] in
            self?.selectedItems.removeAll()
        }
        return result
    }

    private func deleteNodes(_ nodes: [FileNode]) async -> DeletionResult {
        var successCount = 0
        var failedCount = 0
        var freedSize: Int64 = 0

        for node in nodes {
            guard isNodeDeletable(node) else {
                logger.warning("Skipped non-deletable path: \(node.path, privacy: .public)")
                failedCount += 1
                continue
            }

            do {
                if deleteMode == .trash {
                    try fileManager.trashItem(at: URL(fileURLWithPath: node.path), resultingItemURL: nil)
                } else {
                    try fileManager.removeItem(atPath: node.path)
                }
                freedSize += node.size
                successCount += 1

                // Remove from tree and recalculate sizes
                await MainActor.run { [weak self] in
                    node.parent?.removeChild(node)
                    self?.objectWillChange.send()
                }
            } catch {
                logger.error("Failed to delete \(node.name, privacy: .public): \(error.localizedDescription, privacy: .public)")
                failedCount += 1
            }
        }

        return DeletionResult(successCount: successCount, failedCount: failedCount, freedSize: freedSize)
    }

    private func isPathProtected(_ path: String) -> Bool {
        let normalized = URL(fileURLWithPath: path).standardized.path
        for prefix in protectedPrefixes {
            if normalized == prefix || normalized.hasPrefix(prefix + "/") {
                return true
            }
        }
        return false
    }
}
```

- [ ] **Step 2: Build verification**

Run: `xcodebuild -project RicCleanMyMac.xcodeproj -scheme RicCleanMyMac build 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Commit**

```bash
git add RicCleanMyMac/Services/DirectoryScanner.swift
git commit -m "feat(disk-analyzer): add DirectoryScanner service with scan, navigation, deletion"
```

---

### Task 3: BreadcrumbBar View

**Files:**
- Create: `RicCleanMyMac/Views/BreadcrumbBar.swift`

- [ ] **Step 1: Create BreadcrumbBar.swift**

```swift
import SwiftUI

struct BreadcrumbBar: View {
    let path: [FileNode]
    let onNavigate: (FileNode) -> Void

    /// Maximum segments to show before collapsing middle ones
    private let maxVisibleSegments = 5

    var body: some View {
        HStack(spacing: 2) {
            if path.count <= maxVisibleSegments {
                fullBreadcrumb
            } else {
                collapsedBreadcrumb
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color(NSColor.controlBackgroundColor))
    }

    @ViewBuilder
    private var fullBreadcrumb: some View {
        ForEach(Array(path.enumerated()), id: \.element.id) { index, node in
            if index > 0 {
                chevronSeparator
            }
            breadcrumbSegment(node: node, isLast: index == path.count - 1)
        }
    }

    @ViewBuilder
    private var collapsedBreadcrumb: some View {
        // First segment (root)
        breadcrumbSegment(node: path[0], isLast: false)
        chevronSeparator

        // Collapsed middle
        Menu {
            ForEach(Array(path[1..<(path.count - 2)].enumerated()), id: \.element.id) { _, node in
                Button(node.name) { onNavigate(node) }
            }
        } label: {
            Text("...")
                .font(.subheadline)
                .foregroundColor(.accentColor)
                .padding(.horizontal, 4)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()

        chevronSeparator

        // Second to last
        breadcrumbSegment(node: path[path.count - 2], isLast: false)
        chevronSeparator

        // Last (current)
        breadcrumbSegment(node: path[path.count - 1], isLast: true)
    }

    private func breadcrumbSegment(node: FileNode, isLast: Bool) -> some View {
        Group {
            if isLast {
                Text(displayName(for: node))
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
            } else {
                Button(action: { onNavigate(node) }) {
                    Text(displayName(for: node))
                        .font(.subheadline)
                        .foregroundColor(.accentColor)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var chevronSeparator: some View {
        Image(systemName: "chevron.right")
            .font(.caption2)
            .foregroundColor(.secondary)
            .padding(.horizontal, 2)
    }

    private func displayName(for node: FileNode) -> String {
        if node.path == NSHomeDirectory() {
            return "~"
        }
        if node.path == "/" {
            return "/"
        }
        return node.name
    }
}
```

- [ ] **Step 2: Build verification**

Run: `xcodebuild -project RicCleanMyMac.xcodeproj -scheme RicCleanMyMac build 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Commit**

```bash
git add RicCleanMyMac/Views/BreadcrumbBar.swift
git commit -m "feat(disk-analyzer): add BreadcrumbBar navigation component"
```

---

### Task 4: FileListView

**Files:**
- Create: `RicCleanMyMac/Views/FileListView.swift`

- [ ] **Step 1: Create FileListView.swift**

```swift
import SwiftUI

struct FileListView: View {
    let children: [FileNode]
    @Binding var selectedItems: Set<UUID>
    let isDeletable: (FileNode) -> Bool
    let onNavigate: (FileNode) -> Void
    let onDelete: (FileNode) -> Void

    var body: some View {
        List {
            ForEach(children) { node in
                FileListRow(
                    node: node,
                    isSelected: selectedItems.contains(node.id),
                    isDeletable: isDeletable(node),
                    onToggleSelection: { toggleSelection(node) },
                    onNavigate: { onNavigate(node) }
                )
                .contextMenu {
                    if isDeletable(node) {
                        Button(role: .destructive) {
                            onDelete(node)
                        } label: {
                            Label("Delete \"\(node.name)\"", systemImage: "trash")
                        }
                    }

                    if node.isDirectory {
                        Button {
                            onNavigate(node)
                        } label: {
                            Label("Open", systemImage: "folder")
                        }
                    }

                    Divider()

                    Button {
                        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: node.path)
                    } label: {
                        Label("Show in Finder", systemImage: "magnifyingglass")
                    }
                }
            }
        }
        .listStyle(.plain)
    }

    private func toggleSelection(_ node: FileNode) {
        if selectedItems.contains(node.id) {
            selectedItems.remove(node.id)
        } else {
            selectedItems.insert(node.id)
        }
    }
}

// MARK: - Row

struct FileListRow: View {
    let node: FileNode
    let isSelected: Bool
    let isDeletable: Bool
    let onToggleSelection: () -> Void
    let onNavigate: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            // Checkbox
            if isDeletable {
                Button(action: onToggleSelection) {
                    Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                        .foregroundColor(isSelected ? .accentColor : .secondary)
                }
                .buttonStyle(.plain)
            } else {
                Image(systemName: "lock.fill")
                    .foregroundColor(.secondary.opacity(0.5))
                    .frame(width: 16)
            }

            // Icon
            Image(systemName: node.icon)
                .foregroundColor(node.isDirectory ? .accentColor : .secondary)
                .frame(width: 20)

            // Name + path
            VStack(alignment: .leading, spacing: 2) {
                Text(node.name)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(1)

                if node.isDirectory, let childCount = node.children?.count {
                    Text("\(childCount) item(s)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            // Size bar
            sizeBar
                .frame(width: 60)

            // Size label
            Text(node.formattedSize)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(.secondary)
                .frame(width: 70, alignment: .trailing)

            // Chevron for directories
            if node.isDirectory {
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            if node.isDirectory {
                onNavigate()
            }
        }
        .onTapGesture(count: 1) {
            if isDeletable {
                onToggleSelection()
            }
        }
    }

    private var sizeBar: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.secondary.opacity(0.15))
                    .frame(height: 6)

                RoundedRectangle(cornerRadius: 2)
                    .fill(barColor)
                    .frame(width: geo.size.width * CGFloat(node.relativeSize), height: 6)
            }
        }
        .frame(height: 6)
    }

    private var barColor: Color {
        switch node.relativeSize {
        case 0.5...: return .red.opacity(0.7)
        case 0.25...: return .orange.opacity(0.7)
        default: return .accentColor.opacity(0.7)
        }
    }
}
```

- [ ] **Step 2: Build verification**

Run: `xcodebuild -project RicCleanMyMac.xcodeproj -scheme RicCleanMyMac build 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Commit**

```bash
git add RicCleanMyMac/Views/FileListView.swift
git commit -m "feat(disk-analyzer): add FileListView with checkboxes, size bars, context menus"
```

---

### Task 5: SunburstChartView

**Files:**
- Create: `RicCleanMyMac/Views/SunburstChartView.swift`

- [ ] **Step 1: Create SunburstChartView.swift**

```swift
import SwiftUI

// MARK: - Data

struct SunburstSegment: Identifiable {
    let id = UUID()
    let node: FileNode
    let depth: Int
    let startAngle: Angle
    let endAngle: Angle
    let color: Color
}

// MARK: - Layout

enum SunburstLayout {
    static func buildSegments(from root: FileNode, maxDepth: Int = 3) -> [SunburstSegment] {
        guard let children = root.children, root.size > 0 else { return [] }

        var segments: [SunburstSegment] = []
        let palette = generatePalette(count: min(children.count, 12))

        func traverse(node: FileNode, depth: Int, startAngle: Angle, sweep: Angle, color: Color) {
            guard depth <= maxDepth,
                  let children = node.children,
                  node.size > 0 else { return }

            let minSweep = Angle.degrees(360 * 0.01)
            var currentAngle = startAngle
            var otherSize: Int64 = 0

            for (index, child) in children.enumerated() {
                let ratio = Double(child.size) / Double(node.size)
                let childSweep = Angle.degrees(sweep.degrees * ratio)

                if childSweep < minSweep {
                    otherSize += child.size
                    continue
                }

                let childColor: Color
                if depth == 1 {
                    childColor = palette[index % palette.count]
                } else {
                    childColor = color.opacity(1.0 - Double(depth - 1) * 0.25)
                }

                segments.append(SunburstSegment(
                    node: child,
                    depth: depth,
                    startAngle: currentAngle,
                    endAngle: currentAngle + childSweep,
                    color: childColor
                ))

                if child.isDirectory {
                    traverse(
                        node: child,
                        depth: depth + 1,
                        startAngle: currentAngle,
                        sweep: childSweep,
                        color: childColor
                    )
                }

                currentAngle = currentAngle + childSweep
            }

            if otherSize > 0 {
                let otherSweep = Angle.degrees(sweep.degrees * Double(otherSize) / Double(node.size))
                if otherSweep >= minSweep {
                    segments.append(SunburstSegment(
                        node: FileNode(name: "Other", path: "", size: otherSize, isDirectory: false),
                        depth: depth,
                        startAngle: currentAngle,
                        endAngle: currentAngle + otherSweep,
                        color: Color.gray.opacity(0.3)
                    ))
                }
            }
        }

        traverse(node: root, depth: 1, startAngle: .degrees(0), sweep: .degrees(360), color: .accentColor)
        return segments
    }

    private static func generatePalette(count: Int) -> [Color] {
        (0..<count).map { index in
            Color(hue: Double(index) / Double(max(count, 1)), saturation: 0.55, brightness: 0.80)
        }
    }
}

// MARK: - Shape

struct AnnularSector: Shape {
    let innerRadius: CGFloat
    let outerRadius: CGFloat
    let startAngle: Angle
    let endAngle: Angle

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        var path = Path()
        // Offset by -90 degrees so 0 starts at top
        let start = startAngle - .degrees(90)
        let end = endAngle - .degrees(90)
        path.addArc(center: center, radius: outerRadius, startAngle: start, endAngle: end, clockwise: false)
        path.addArc(center: center, radius: innerRadius, startAngle: end, endAngle: start, clockwise: true)
        path.closeSubpath()
        return path
    }
}

// MARK: - View

struct SunburstChartView: View {
    let rootNode: FileNode
    let onNavigate: (FileNode) -> Void

    @State private var hoveredSegment: UUID?

    private let ringWidth: CGFloat = 36
    private let centerRadius: CGFloat = 50

    var body: some View {
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height)
            let segments = SunburstLayout.buildSegments(from: rootNode)

            ZStack {
                // Center label
                VStack(spacing: 2) {
                    Text(rootNode.name)
                        .font(.caption)
                        .fontWeight(.semibold)
                        .lineLimit(1)
                    Text(rootNode.formattedSize)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .frame(width: centerRadius * 1.6)

                // Segments
                ForEach(segments) { segment in
                    let innerR = centerRadius + CGFloat(segment.depth - 1) * ringWidth
                    let outerR = innerR + ringWidth

                    AnnularSector(
                        innerRadius: innerR,
                        outerRadius: outerR,
                        startAngle: segment.startAngle,
                        endAngle: segment.endAngle
                    )
                    .fill(hoveredSegment == segment.id ? segment.color.opacity(0.9) : segment.color)
                    .overlay(
                        AnnularSector(
                            innerRadius: innerR,
                            outerRadius: outerR,
                            startAngle: segment.startAngle,
                            endAngle: segment.endAngle
                        )
                        .stroke(Color(NSColor.windowBackgroundColor), lineWidth: 1)
                    )
                    .onHover { isHovered in
                        hoveredSegment = isHovered ? segment.id : nil
                    }
                    .onTapGesture {
                        if segment.node.isDirectory && !segment.node.path.isEmpty {
                            onNavigate(segment.node)
                        }
                    }
                    .help(tooltipText(for: segment))
                }
            }
            .frame(width: size, height: size)
            .position(x: geo.size.width / 2, y: geo.size.height / 2)
        }
        .padding()
    }

    private func tooltipText(for segment: SunburstSegment) -> String {
        let percentage = String(format: "%.1f%%", segment.node.relativeSize * 100)
        return "\(segment.node.name) — \(segment.node.formattedSize) (\(percentage))"
    }
}
```

- [ ] **Step 2: Build verification**

Run: `xcodebuild -project RicCleanMyMac.xcodeproj -scheme RicCleanMyMac build 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Commit**

```bash
git add RicCleanMyMac/Views/SunburstChartView.swift
git commit -m "feat(disk-analyzer): add SunburstChartView with arc geometry and interactivity"
```

---

### Task 6: DiskAnalyzerConfirmationSheet

**Files:**
- Create: `RicCleanMyMac/Views/DiskAnalyzerConfirmationSheet.swift`

- [ ] **Step 1: Create DiskAnalyzerConfirmationSheet.swift**

```swift
import SwiftUI

struct DiskAnalyzerConfirmationSheet: View {
    let nodes: [FileNode]
    let totalSize: Int64
    let deleteMode: DeleteMode
    let onConfirm: () -> Void
    let onCancel: () -> Void

    private let largeItemThreshold: Int64 = 500_000_000 // 500 MB

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            itemList
            Divider()
            footer
        }
        .frame(minWidth: 480, minHeight: 360)
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: deleteMode == .permanent ? "xmark.bin.fill" : "trash.circle.fill")
                .font(.largeTitle)
                .foregroundColor(.red)

            VStack(alignment: .leading, spacing: 4) {
                Text("Confirm Deletion")
                    .font(.headline)

                Text("\(deleteMode == .trash ? "Move" : "Permanently delete") \(nodes.count) item(s) (\(ByteCountFormatter.string(fromByteCount: totalSize)))")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                if deleteMode == .permanent {
                    Text("This action cannot be undone.")
                        .font(.caption)
                        .foregroundColor(.red)
                        .fontWeight(.medium)
                } else {
                    Text("Items will be moved to the Trash.")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
            }
        }
        .padding()
    }

    private var itemList: some View {
        List(nodes) { node in
            HStack(spacing: 10) {
                Image(systemName: node.icon)
                    .foregroundColor(node.isDirectory ? .accentColor : .secondary)
                    .frame(width: 20)

                VStack(alignment: .leading, spacing: 2) {
                    Text(node.name)
                        .font(.subheadline)
                    Text(node.path)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                HStack(spacing: 4) {
                    if node.size >= largeItemThreshold {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                    Text(node.formattedSize)
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(node.size >= largeItemThreshold ? .orange : .secondary)
                }
            }
        }
        .listStyle(.plain)
    }

    private var footer: some View {
        HStack {
            Spacer()
            Button("Cancel", action: onCancel)
                .keyboardShortcut(.escape)

            Button(role: .destructive, action: onConfirm) {
                Text(deleteMode == .trash
                     ? "Move to Trash (\(nodes.count))"
                     : "Delete Permanently (\(nodes.count))")
            }
            .keyboardShortcut(.return)
            .buttonStyle(.borderedProminent)
            .tint(.red)
        }
        .padding()
    }
}
```

- [ ] **Step 2: Build verification**

Run: `xcodebuild -project RicCleanMyMac.xcodeproj -scheme RicCleanMyMac build 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Commit**

```bash
git add RicCleanMyMac/Views/DiskAnalyzerConfirmationSheet.swift
git commit -m "feat(disk-analyzer): add deletion confirmation sheet with trash/permanent modes"
```

---

### Task 7: DiskAnalyzerView Container

**Files:**
- Create: `RicCleanMyMac/Views/DiskAnalyzerView.swift`

- [ ] **Step 1: Create DiskAnalyzerView.swift**

```swift
import SwiftUI

struct DiskAnalyzerView: View {
    @EnvironmentObject var scanner: DirectoryScanner

    @State private var showConfirmation = false
    @State private var showSingleDeleteConfirmation = false
    @State private var nodeToDelete: FileNode?
    @State private var deletionResult: DeletionResult?
    @State private var isDeleting = false

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()

            if scanner.isScanning {
                scanningView
            } else if let currentNode = scanner.currentNode {
                BreadcrumbBar(path: scanner.breadcrumbPath) { node in
                    scanner.navigateTo(node)
                }
                Divider()

                contentView(for: currentNode)

                if !scanner.selectedItems.isEmpty {
                    Divider()
                    bottomBar
                }
            } else {
                emptyState
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .sheet(isPresented: $showConfirmation) {
            bulkDeleteSheet
        }
        .sheet(isPresented: $showSingleDeleteConfirmation) {
            singleDeleteSheet
        }
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: 12) {
            Button {
                let panel = NSOpenPanel()
                panel.canChooseDirectories = true
                panel.canChooseFiles = false
                panel.allowsMultipleSelection = false
                panel.message = "Choose a folder to analyze"
                if panel.runModal() == .OK, let url = panel.url {
                    scanner.scan(rootPath: url.path)
                }
            } label: {
                Label("Choose Folder...", systemImage: "folder.badge.plus")
            }

            if scanner.scanResult != nil {
                Button {
                    if let rootPath = scanner.scanResult?.root.path {
                        scanner.scan(rootPath: rootPath)
                    }
                } label: {
                    Label("Re-scan", systemImage: "arrow.clockwise")
                }
            }

            Spacer()

            if scanner.scanResult != nil {
                scanSummary
            }

            Spacer()

            Picker("Delete mode", selection: $scanner.deleteMode) {
                ForEach(DeleteMode.allCases, id: \.self) { mode in
                    Label(mode.rawValue, systemImage: mode.icon).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 200)

            if let result = deletionResult {
                deletionBanner(result)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var scanSummary: some View {
        Group {
            if let result = scanner.scanResult {
                HStack(spacing: 8) {
                    Text("\(result.totalFiles) files, \(result.totalDirectories) folders")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("Scanned in \(String(format: "%.1fs", result.scanDuration))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    // MARK: - Content

    private func contentView(for node: FileNode) -> some View {
        HSplitView {
            FileListView(
                children: node.children ?? [],
                selectedItems: $scanner.selectedItems,
                isDeletable: { scanner.isNodeDeletable($0) },
                onNavigate: { scanner.navigateTo($0) },
                onDelete: { nodeToDelete = $0; showSingleDeleteConfirmation = true }
            )
            .frame(minWidth: 400)

            SunburstChartView(rootNode: node) { childNode in
                scanner.navigateTo(childNode)
            }
            .frame(minWidth: 250)
        }
    }

    // MARK: - Scanning state

    private var scanningView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.2)
            Text("Scanning filesystem...")
                .font(.headline)
            if scanner.progress.filesScanned > 0 {
                Text("\(scanner.progress.filesScanned) items scanned")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Text(scanner.progress.currentPath)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            Button("Cancel") {
                scanner.cancel()
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 20) {
            Image(systemName: "internaldrive")
                .font(.system(size: 60))
                .foregroundColor(.secondary)
            Text("Disk Analyzer")
                .font(.title2)
                .fontWeight(.semibold)
            Text("Choose a folder to analyze its space usage.")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Bottom bar

    private var bottomBar: some View {
        HStack(spacing: 8) {
            let selectedCount = scanner.selectedItems.count
            let selectedSize = selectedNodes.reduce(Int64(0)) { $0 + $1.size }

            Text("\(selectedCount) item(s) selected — \(ByteCountFormatter.string(fromByteCount: selectedSize))")
                .font(.subheadline)
                .foregroundColor(.secondary)

            Spacer()

            Button("Deselect All") {
                scanner.selectedItems.removeAll()
            }

            Button(action: { showConfirmation = true }) {
                HStack {
                    if isDeleting {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle())
                            .scaleEffect(0.8)
                    } else {
                        Image(systemName: "trash.fill")
                    }
                    Text(isDeleting ? "Deleting..." : "Delete Selected")
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
            }
            .disabled(isDeleting)
            .buttonStyle(.borderedProminent)
            .tint(scanner.deleteMode == .permanent ? .red : .accentColor)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(NSColor.windowBackgroundColor))
    }

    // MARK: - Helpers

    private var selectedNodes: [FileNode] {
        scanner.currentNode?.findNodes(withIDs: scanner.selectedItems) ?? []
    }

    @ViewBuilder
    private var bulkDeleteSheet: some View {
        DiskAnalyzerConfirmationSheet(
            nodes: selectedNodes,
            totalSize: selectedNodes.reduce(Int64(0)) { $0 + $1.size },
            deleteMode: scanner.deleteMode,
            onConfirm: {
                showConfirmation = false
                Task { await performBulkDelete() }
            },
            onCancel: { showConfirmation = false }
        )
    }

    @ViewBuilder
    private var singleDeleteSheet: some View {
        if let node = nodeToDelete {
            DiskAnalyzerConfirmationSheet(
                nodes: [node],
                totalSize: node.size,
                deleteMode: scanner.deleteMode,
                onConfirm: {
                    showSingleDeleteConfirmation = false
                    Task { await performSingleDelete(node) }
                },
                onCancel: { showSingleDeleteConfirmation = false; nodeToDelete = nil }
            )
        }
    }

    private func deletionBanner(_ result: DeletionResult) -> some View {
        HStack(spacing: 4) {
            Image(systemName: result.isFullSuccess ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundColor(result.isFullSuccess ? .green : .orange)
            Text("Freed \(ByteCountFormatter.string(fromByteCount: result.freedSize))")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    private func performBulkDelete() async {
        isDeleting = true
        let result = await scanner.deleteSelectedItems()
        await MainActor.run {
            isDeleting = false
            deletionResult = result
        }
    }

    private func performSingleDelete(_ node: FileNode) async {
        isDeleting = true
        let result = await scanner.deleteSingleItem(node)
        await MainActor.run {
            isDeleting = false
            nodeToDelete = nil
            deletionResult = result
        }
    }
}
```

- [ ] **Step 2: Build verification**

Run: `xcodebuild -project RicCleanMyMac.xcodeproj -scheme RicCleanMyMac build 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Commit**

```bash
git add RicCleanMyMac/Views/DiskAnalyzerView.swift
git commit -m "feat(disk-analyzer): add DiskAnalyzerView container with toolbar, split view, bottom bar"
```

---

### Task 8: MainView Integration

**Files:**
- Modify: `RicCleanMyMac/Views/MainView.swift`

- [ ] **Step 1: Add diskAnalyzer to NavigationSection and wire it up**

In `MainView.swift`, make these changes:

1. Add the new enum case in `NavigationSection`:

```swift
enum NavigationSection: String, CaseIterable {
    case dashboard = "Dashboard"
    case diskAnalyzer = "Disk Analyzer"
    case cleanup = "Cleanup"

    var icon: String {
        switch self {
        case .dashboard: return "chart.bar.fill"
        case .diskAnalyzer: return "internaldrive"
        case .cleanup: return "trash.fill"
        }
    }
}
```

2. Add a `@StateObject` for `DirectoryScanner`:

```swift
@StateObject private var directoryScanner = DirectoryScanner()
```

3. Add the new case in the detail switch:

```swift
switch selectedSection {
case .cleanup:
    CleanupView()
case .diskAnalyzer:
    DiskAnalyzerView()
case .dashboard, .none:
    DashboardView()
}
```

4. Add `.environmentObject(directoryScanner)` alongside the existing `.environmentObject(cleanupService)`.

The full updated `MainView.swift`:

```swift
import SwiftUI

struct MainView: View {
    @StateObject private var cleanupService = CleanupService()
    @StateObject private var directoryScanner = DirectoryScanner()
    @State private var selectedSection: NavigationSection? = .dashboard

    enum NavigationSection: String, CaseIterable {
        case dashboard = "Dashboard"
        case diskAnalyzer = "Disk Analyzer"
        case cleanup = "Cleanup"

        var icon: String {
            switch self {
            case .dashboard: return "chart.bar.fill"
            case .diskAnalyzer: return "internaldrive"
            case .cleanup: return "trash.fill"
            }
        }
    }

    var body: some View {
        NavigationSplitView {
            List(NavigationSection.allCases, id: \.self, selection: $selectedSection) { section in
                Label(section.rawValue, systemImage: section.icon)
                    .tag(section)
            }
            .listStyle(SidebarListStyle())
            .navigationSplitViewColumnWidth(min: 180, ideal: 200)
        } detail: {
            Group {
                switch selectedSection {
                case .cleanup:
                    CleanupView()
                case .diskAnalyzer:
                    DiskAnalyzerView()
                case .dashboard, .none:
                    DashboardView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .environmentObject(cleanupService)
        .environmentObject(directoryScanner)
    }
}
```

- [ ] **Step 2: Build verification**

Run: `xcodebuild -project RicCleanMyMac.xcodeproj -scheme RicCleanMyMac build 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Commit**

```bash
git add RicCleanMyMac/Views/MainView.swift
git commit -m "feat(disk-analyzer): integrate Disk Analyzer into sidebar navigation"
```

---

### Task 9: Manual Verification and Polish

- [ ] **Step 1: Run the app and verify the full flow**

Run: `xcodebuild -project RicCleanMyMac.xcodeproj -scheme RicCleanMyMac build 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`

Then open and manually test:
1. Click "Disk Analyzer" in sidebar — should show empty state
2. Click "Choose Folder..." — should open NSOpenPanel
3. Select a test directory (e.g., `~/Downloads`) — should show scanning progress
4. After scan: breadcrumb shows root, list shows children sorted by size, sunburst renders
5. Double-click a directory in list — drill-down works, breadcrumb updates, sunburst updates
6. Click breadcrumb segment — navigates back to that level
7. Click a sunburst arc — navigates to that directory (synced with list)
8. Checkboxes — select items, bottom bar appears with count/size
9. Right-click — context menu shows "Delete" and "Show in Finder"
10. Toggle Trash/Permanent — confirm button color changes
11. Delete flow — confirmation sheet shows, deletion works, tree updates

- [ ] **Step 2: Fix any build errors or UI issues found during verification**

Address any compilation errors, layout issues, or broken interactions discovered during testing.

- [ ] **Step 3: Final commit**

```bash
git add -A
git commit -m "fix(disk-analyzer): address issues found during manual verification"
```

Note: only create this commit if there are actual changes to commit.
