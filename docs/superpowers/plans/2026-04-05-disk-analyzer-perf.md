# Disk Analyzer Performance Optimization — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Speed up cached scan loading and reduce memory usage through four targeted optimizations.

**Architecture:** No structural changes. Replace JSON with binary plist for serialization, remove redundant stored path strings from FileNode (compute on-demand from parent chain), add time-based progress throttle, and cache sunburst chart segments.

**Tech Stack:** Swift, SwiftUI, PropertyListEncoder/Decoder, LZFSE compression.

**Spec:** `docs/superpowers/specs/2026-04-05-disk-analyzer-perf-design.md`

---

### Task 1: Binary plist serialization

**Files:**
- Modify: `RicCleanMyMac/Services/DirectoryScanner.swift:18-22` (cacheURL)
- Modify: `RicCleanMyMac/Services/DirectoryScanner.swift:284-299` (saveToDisk)
- Modify: `RicCleanMyMac/Services/DirectoryScanner.swift:301-316` (loadFromDisk)

- [ ] **Step 1: Update cache file name**

In `DirectoryScanner.swift`, change the `cacheURL` computed property to use the new file extension. This auto-invalidates any existing JSON cache.

```swift
private var cacheURL: URL? {
    fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
        .appendingPathComponent("RicCleanMyMac")
        .appendingPathComponent("scan-cache.bplist.lzfse")
}
```

- [ ] **Step 2: Switch saveToDisk to binary plist**

Replace the `JSONEncoder` call in `saveToDisk(_:)` with `PropertyListEncoder` in binary format:

```swift
private func saveToDisk(_ result: DirectoryScanResult) {
    guard let cacheURL else { return }

    do {
        let directory = cacheURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        let data = try encoder.encode(result)
        let compressed = try (data as NSData).compressed(using: .lzfse) as Data
        try compressed.write(to: cacheURL, options: .atomic)

        logger.info("Saved scan cache (\(compressed.count) bytes compressed)")
    } catch {
        logger.error("Failed to save scan cache: \(error.localizedDescription, privacy: .public)")
    }
}
```

- [ ] **Step 3: Switch loadFromDisk to plist decoder**

Replace `JSONDecoder` with `PropertyListDecoder` in `loadFromDisk()`:

```swift
private func loadFromDisk() -> DirectoryScanResult? {
    guard let cacheURL, fileManager.fileExists(atPath: cacheURL.path) else { return nil }

    do {
        let compressed = try Data(contentsOf: cacheURL)
        let data = try (compressed as NSData).decompressed(using: .lzfse) as Data
        let result = try PropertyListDecoder().decode(DirectoryScanResult.self, from: data)

        logger.info("Loaded scan cache from \(result.formattedScanDate)")
        return result
    } catch {
        logger.error("Failed to load scan cache: \(error.localizedDescription, privacy: .public)")
        try? fileManager.removeItem(at: cacheURL)
        return nil
    }
}
```

- [ ] **Step 4: Build and verify**

Run: `xcodebuild build -project RicCleanMyMac.xcodeproj -scheme RicCleanMyMac -destination 'platform=macOS' -quiet`

Expected: Build succeeds with no errors.

- [ ] **Step 5: Commit**

```bash
git add RicCleanMyMac/Services/DirectoryScanner.swift
git commit -m "perf(disk-analyzer): switch from JSON to binary plist for cache serialization"
```

---

### Task 2: Remove stored path from FileNode

**Files:**
- Modify: `RicCleanMyMac/Models/FileNode.swift:3-30` (stored properties and init)
- Modify: `RicCleanMyMac/Models/FileNode.swift:94-119` (Codable conformance)
- Modify: `RicCleanMyMac/Services/DirectoryScanner.swift:106-113` (buildTree directory node creation)
- Modify: `RicCleanMyMac/Services/DirectoryScanner.swift:140-145` (buildTree file node creation)
- Modify: `RicCleanMyMac/Views/SunburstChartView.swift:82-88` ("Other" node creation)
- Modify: `RicCleanMyMac/Views/SunburstChartView.swift:175` (navigation tap check)

- [ ] **Step 1: Change path from stored to computed in FileNode**

In `FileNode.swift`, remove `let path: String` from stored properties, remove `path:` from `init`, and add a computed property:

Replace the class declaration and init (lines 3-30):

```swift
final class FileNode: Identifiable {
    let id = UUID()
    let name: String
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

    /// Reconstructs the absolute path by walking up the parent chain.
    /// Root node's name must be the absolute root path (e.g. "/").
    var path: String {
        guard let parent else { return name }
        if parent.path.hasSuffix("/") {
            return parent.path + name
        }
        return parent.path + "/" + name
    }

    init(name: String, size: Int64, isDirectory: Bool, accessDenied: Bool = false) {
        self.name = name
        self.size = size
        self.isDirectory = isDirectory
        self.accessDenied = accessDenied
    }
```

- [ ] **Step 2: Update Codable to exclude path**

Replace the Codable extension (lines 94-119):

```swift
extension FileNode: Codable {
    enum CodingKeys: String, CodingKey {
        case name, size, isDirectory, accessDenied, children
    }

    convenience init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            name: try container.decode(String.self, forKey: .name),
            size: try container.decode(Int64.self, forKey: .size),
            isDirectory: try container.decode(Bool.self, forKey: .isDirectory),
            accessDenied: try container.decode(Bool.self, forKey: .accessDenied)
        )
        self.children = try container.decodeIfPresent([FileNode].self, forKey: .children)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encode(size, forKey: .size)
        try container.encode(isDirectory, forKey: .isDirectory)
        try container.encode(accessDenied, forKey: .accessDenied)
        try container.encodeIfPresent(children, forKey: .children)
    }
```

- [ ] **Step 3: Update DirectoryScanner.buildTree — directory node**

In `DirectoryScanner.swift`, the `buildTree` function (line 107) creates directory nodes. Remove the `path:` argument:

Change:
```swift
let node = FileNode(
    name: url.lastPathComponent,
    path: url.path,
    size: 0,
    isDirectory: true
)
```

To:
```swift
let node = FileNode(
    name: url.lastPathComponent,
    size: 0,
    isDirectory: true
)
```

- [ ] **Step 4: Update DirectoryScanner.buildTree — file node**

In the same function (line 140), remove `path:` from file node creation:

Change:
```swift
let childNode = FileNode(
    name: itemURL.lastPathComponent,
    path: itemURL.path,
    size: fileSize,
    isDirectory: false
)
```

To:
```swift
let childNode = FileNode(
    name: itemURL.lastPathComponent,
    size: fileSize,
    isDirectory: false
)
```

- [ ] **Step 5: Update SunburstChartView "Other" node**

In `SunburstChartView.swift` (line 82), the synthetic "Other" node no longer needs `path:`:

Change:
```swift
segments.append(SunburstSegment(
    node: FileNode(name: "Other", path: "", size: otherSize, isDirectory: false),
    depth: depth,
    startAngle: currentAngle,
    endAngle: currentAngle + otherSweep,
    color: Color.gray.opacity(0.3)
))
```

To:
```swift
segments.append(SunburstSegment(
    node: FileNode(name: "Other", size: otherSize, isDirectory: false),
    depth: depth,
    startAngle: currentAngle,
    endAngle: currentAngle + otherSweep,
    color: Color.gray.opacity(0.3)
))
```

- [ ] **Step 6: Simplify SunburstChartView navigation check**

In `SunburstChartView.swift` (line 175), the `!segment.node.path.isEmpty` check was guarding against the "Other" node with empty path. Since "Other" has `isDirectory: false`, the `isDirectory` check already prevents navigation. Simplify:

Change:
```swift
.onTapGesture {
    if segment.node.isDirectory && !segment.node.path.isEmpty {
        onNavigate(segment.node)
    }
}
```

To:
```swift
.onTapGesture {
    if segment.node.isDirectory {
        onNavigate(segment.node)
    }
}
```

- [ ] **Step 7: Build and verify**

Run: `xcodebuild build -project RicCleanMyMac.xcodeproj -scheme RicCleanMyMac -destination 'platform=macOS' -quiet`

Expected: Build succeeds with no errors.

- [ ] **Step 8: Commit**

```bash
git add RicCleanMyMac/Models/FileNode.swift RicCleanMyMac/Services/DirectoryScanner.swift RicCleanMyMac/Views/SunburstChartView.swift
git commit -m "perf(disk-analyzer): replace stored path with computed property from parent chain

Removes redundant full-path string storage from every FileNode, roughly
halving per-node memory and serialized cache size."
```

---

### Task 3: Temporal throttle for scan progress

**Files:**
- Modify: `RicCleanMyMac/Services/DirectoryScanner.swift:99-181` (performScan)

- [ ] **Step 1: Add lastProgressUpdate tracking**

In `DirectoryScanner.swift`, inside `performScan`, replace the modulo-based progress update with a time-based throttle. The full `performScan` method becomes:

Change the progress update block inside the `for itemURL in contents` loop (lines 152-159). Replace:

```swift
scannedCount += 1
if scannedCount % 1000 == 0 {
    let count = scannedCount
    let currentPath = url.lastPathComponent
    Task { @MainActor [weak self] in
        self?.progress = ScanProgress(filesScanned: count, currentPath: currentPath)
    }
}
```

With:

```swift
scannedCount += 1
let now = CFAbsoluteTimeGetCurrent()
if now - lastProgressUpdate >= 0.1 {
    lastProgressUpdate = now
    let count = scannedCount
    let currentPath = url.lastPathComponent
    Task { @MainActor [weak self] in
        self?.progress = ScanProgress(filesScanned: count, currentPath: currentPath)
    }
}
```

Also add the `lastProgressUpdate` variable at the top of the `Task.detached` closure, right after `var scannedCount = 0` (line 104):

```swift
var lastProgressUpdate: CFAbsoluteTime = 0
```

- [ ] **Step 2: Build and verify**

Run: `xcodebuild build -project RicCleanMyMac.xcodeproj -scheme RicCleanMyMac -destination 'platform=macOS' -quiet`

Expected: Build succeeds with no errors.

- [ ] **Step 3: Commit**

```bash
git add RicCleanMyMac/Services/DirectoryScanner.swift
git commit -m "perf(disk-analyzer): use 100ms temporal throttle for scan progress updates

Replaces the modulo-1000 counter with a time-based check so the UI
updates at a steady ~10fps regardless of scan speed."
```

---

### Task 4: Cache sunburst chart segments

**Files:**
- Modify: `RicCleanMyMac/Views/SunburstChartView.swift:125-186` (SunburstChartView body)

- [ ] **Step 1: Add cached segments state and compute on node change**

In `SunburstChartView.swift`, replace the view struct (lines 125-186) with a version that caches segments:

```swift
struct SunburstChartView: View {
    let rootNode: FileNode
    let onNavigate: (FileNode) -> Void

    @State private var hoveredSegment: UUID?
    @State private var segments: [SunburstSegment] = []

    private let ringWidth: CGFloat = 36
    private let centerRadius: CGFloat = 50

    var body: some View {
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height)

            ZStack {
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
                        if segment.node.isDirectory {
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
        .onAppear {
            segments = SunburstLayout.buildSegments(from: rootNode)
        }
        .onChange(of: rootNode) { _, newNode in
            segments = SunburstLayout.buildSegments(from: newNode)
        }
    }

    private func tooltipText(for segment: SunburstSegment) -> String {
        let percentage = String(format: "%.1f%%", segment.node.relativeSize * 100)
        return "\(segment.node.name) — \(segment.node.formattedSize) (\(percentage))"
    }
}
```

Key changes from original:
- Added `@State private var segments: [SunburstSegment] = []`
- Removed `let segments = SunburstLayout.buildSegments(from: rootNode)` from inside GeometryReader
- Added `.onAppear` and `.onChange(of: rootNode)` to compute segments only when the node changes
- The `.onTapGesture` check is simplified to `segment.node.isDirectory` (from Task 2 Step 6, already applied here)

- [ ] **Step 2: Build and verify**

Run: `xcodebuild build -project RicCleanMyMac.xcodeproj -scheme RicCleanMyMac -destination 'platform=macOS' -quiet`

Expected: Build succeeds with no errors.

- [ ] **Step 3: Commit**

```bash
git add RicCleanMyMac/Views/SunburstChartView.swift
git commit -m "perf(disk-analyzer): cache sunburst segments to avoid recalculation per frame

Segments are now computed once on appear and on node change, instead of
on every SwiftUI render pass."
```
