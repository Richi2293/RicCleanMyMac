# Disk Dashboard Header — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a collapsible dashboard header to the disk analyzer showing disk usage gauge and smart categories.

**Architecture:** A new `DiskDashboardHeader` view sits above the existing list+sunburst content. `DirectoryScanner` gains two published properties (`diskSpace`, `smartCategories`) populated from `DiskAnalyzer.getDiskSpace()` and a new `FileNode.extractSmartCategories()` method. The header renders in two layers: gauge (instant) and categories (post-scan).

**Tech Stack:** SwiftUI, macOS 14+, Foundation

**Spec:** `docs/superpowers/specs/2026-04-10-disk-dashboard-design.md`

---

## File map

| File | Action | Responsibility |
|------|--------|----------------|
| `RicCleanMyMac/Models/SmartCategory.swift` | Create | Data model for a smart category |
| `RicCleanMyMac/Models/FileNode.swift` | Modify | Add `extractSmartCategories()` tree traversal |
| `RicCleanMyMac/Services/DirectoryScanner.swift` | Modify | Add `diskSpace`, `smartCategories`, loading logic |
| `RicCleanMyMac/Views/DiskDashboardHeader.swift` | Create | Collapsible header view with gauge + categories |
| `RicCleanMyMac/Views/DiskAnalyzerView.swift` | Modify | Insert header above existing content |

---

### Task 1: Create `SmartCategory` model

**Files:**
- Create: `RicCleanMyMac/Models/SmartCategory.swift`

- [ ] **Step 1: Create SmartCategory.swift**

```swift
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
```

`id` is set by the extraction logic (e.g. `"cache"`, `"log"`) so categories are stable across recalculations.

- [ ] **Step 2: Verify build**

Run: `xcodebuild build -scheme RicCleanMyMac -destination 'platform=macOS' -quiet 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
git add RicCleanMyMac/Models/SmartCategory.swift
git commit -m "feat(disk-analyzer): add SmartCategory model"
```

---

### Task 2: Add `extractSmartCategories()` to `FileNode`

**Files:**
- Modify: `RicCleanMyMac/Models/FileNode.swift`

- [ ] **Step 1: Add the extraction method**

Add this method to `FileNode`, after the existing `findNodes(withIDs:)` method (after line 143):

```swift
// MARK: - Smart categories

func extractSmartCategories() -> [SmartCategory] {
    var cacheSize: Int64 = 0
    var cacheIDs: [ObjectIdentifier] = []
    var logSize: Int64 = 0
    var logIDs: [ObjectIdentifier] = []
    var tempSize: Int64 = 0
    var tempIDs: [ObjectIdentifier] = []
    var downloadsSize: Int64 = 0
    var downloadsIDs: [ObjectIdentifier] = []
    var largeFileSize: Int64 = 0
    var largeFileIDs: [ObjectIdentifier] = []

    let largeFileThreshold: Int64 = 1_073_741_824 // 1 GB

    func walk(_ node: FileNode) {
        if node.isDirectory {
            let lower = node.name.lowercased()

            if lower == "caches" || lower == ".cache" {
                cacheSize += node.size
                cacheIDs.append(node.id)
                return // don't recurse — whole subtree counted
            }
            if lower == "logs" {
                logSize += node.size
                logIDs.append(node.id)
                return
            }
            if lower == "tmp" || lower == "temporary items" {
                tempSize += node.size
                tempIDs.append(node.id)
                return
            }
            if lower == "downloads" && node.parent?.name.lowercased() != "downloads" {
                downloadsSize += node.size
                downloadsIDs.append(node.id)
                return
            }

            for child in node.children ?? [] {
                walk(child)
            }
        } else {
            // Leaf file: check for .log extension
            let ext = (node.name as NSString).pathExtension.lowercased()
            if ext == "log" {
                logSize += node.size
                logIDs.append(node.id)
            }
            if node.size >= largeFileThreshold {
                largeFileSize += node.size
                largeFileIDs.append(node.id)
            }
        }
    }

    // The root node's name is the absolute path (e.g. "/Users/foo"),
    // so we pass an empty pathSoFar and let walk use node.name directly.
    for child in children ?? [] {
        walk(child)
    }

    var categories: [SmartCategory] = []

    if cacheSize > 0 {
        categories.append(SmartCategory(
            id: "cache", name: "Cache", icon: "archivebox",
            totalSize: cacheSize, nodeIDs: cacheIDs
        ))
    }
    if logSize > 0 {
        categories.append(SmartCategory(
            id: "log", name: "Log", icon: "doc.text",
            totalSize: logSize, nodeIDs: logIDs
        ))
    }
    if tempSize > 0 {
        categories.append(SmartCategory(
            id: "temp", name: "Temp", icon: "clock.arrow.circlepath",
            totalSize: tempSize, nodeIDs: tempIDs
        ))
    }
    if downloadsSize > 0 {
        categories.append(SmartCategory(
            id: "downloads", name: "Downloads", icon: "arrow.down.circle",
            totalSize: downloadsSize, nodeIDs: downloadsIDs
        ))
    }
    if largeFileSize > 0 {
        categories.append(SmartCategory(
            id: "largeFiles", name: "Large files", icon: "doc.badge.ellipsis",
            totalSize: largeFileSize, nodeIDs: largeFileIDs
        ))
    }

    return categories.sorted { $0.totalSize > $1.totalSize }
}
```

**Important detail:** the `walk` function checks directory names (not full paths) because `FileNode.name` is always the last path component for non-root nodes. When a matching directory is found, we count its entire subtree size and stop recursion to avoid double-counting.

- [ ] **Step 2: Verify build**

Run: `xcodebuild build -scheme RicCleanMyMac -destination 'platform=macOS' -quiet 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
git add RicCleanMyMac/Models/FileNode.swift
git commit -m "feat(disk-analyzer): add extractSmartCategories to FileNode"
```

---

### Task 3: Add `diskSpace` and `smartCategories` to `DirectoryScanner`

**Files:**
- Modify: `RicCleanMyMac/Services/DirectoryScanner.swift`

- [ ] **Step 1: Add published properties**

Add after the existing `@Published var lastError: ScanError?` (line 20):

```swift
@Published var diskSpace: DiskSpace?
@Published var smartCategories: [SmartCategory] = []
```

- [ ] **Step 2: Add `loadDiskSpace()` method**

Add a new method in the `// MARK: - Scanning` section, after `prepareForNewRoot`:

```swift
func loadDiskSpace() {
    Task {
        let space = await DiskAnalyzer().getDiskSpace()
        self.diskSpace = space
    }
}
```

This uses the existing `DiskAnalyzer` service. It's fire-and-forget — `diskSpace` is published, the UI reacts automatically.

- [ ] **Step 3: Compute smart categories after scan success**

In `handleScanSuccess(_:)`, add the smart categories computation right after setting `currentNode`. The method currently reads:

```swift
private func handleScanSuccess(_ result: DirectoryScanResult) async {
    scanResult = result
    currentNode = result.root
    isScanning = false
```

Change it to:

```swift
private func handleScanSuccess(_ result: DirectoryScanResult) async {
    scanResult = result
    currentNode = result.root
    smartCategories = result.root.extractSmartCategories()
    isScanning = false
```

- [ ] **Step 4: Compute smart categories after cache load**

In `loadCachedResult(forRootPath:)`, the `.success` branch currently reads:

```swift
case .success(let result):
    self.scanResult = result
    self.currentNode = result.root
```

Change it to:

```swift
case .success(let result):
    self.scanResult = result
    self.currentNode = result.root
    self.smartCategories = result.root.extractSmartCategories()
```

- [ ] **Step 5: Clear smart categories on root reset**

In `prepareForNewRoot(_:)`, add after `selectedItems.removeAll()`:

```swift
smartCategories = []
```

`diskSpace` is intentionally NOT cleared — it reflects the volume, not the scan root.

- [ ] **Step 6: Verify build**

Run: `xcodebuild build -scheme RicCleanMyMac -destination 'platform=macOS' -quiet 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

- [ ] **Step 7: Commit**

```bash
git add RicCleanMyMac/Services/DirectoryScanner.swift
git commit -m "feat(disk-analyzer): add diskSpace and smartCategories to DirectoryScanner"
```

---

### Task 4: Create `DiskDashboardHeader` view

**Files:**
- Create: `RicCleanMyMac/Views/DiskDashboardHeader.swift`

- [ ] **Step 1: Create the view file**

```swift
import SwiftUI

struct DiskDashboardHeader: View {
    let diskSpace: DiskSpace?
    let smartCategories: [SmartCategory]
    let isScanComplete: Bool
    let isScanning: Bool
    let onCategoryTapped: (SmartCategory) -> Void

    @AppStorage("diskDashboardExpanded") private var isExpanded = true

    var body: some View {
        VStack(spacing: 0) {
            if isExpanded {
                expandedView
            } else {
                collapsedView
            }
        }
        .background(Color(NSColor.controlBackgroundColor))
    }

    // MARK: - Collapsed

    private var collapsedView: some View {
        HStack(spacing: 8) {
            if let ds = diskSpace {
                Circle()
                    .fill(gaugeColor(for: ds.usedPercentage))
                    .frame(width: 8, height: 8)
                Text("\(Int(ds.usedPercentage * 100))% — \(ds.formattedAvailable) available")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                ProgressView()
                    .scaleEffect(0.5)
                Text("Loading disk info…")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            expandCollapseButton
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    // MARK: - Expanded

    private var expandedView: some View {
        VStack(spacing: 12) {
            // Level 1: Disk gauge
            HStack(spacing: 16) {
                if let ds = diskSpace {
                    diskGauge(ds)
                    diskStats(ds)
                } else {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Loading disk info…")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                Spacer()
                expandCollapseButton
            }

            // Level 2: Smart categories
            if isScanComplete && !smartCategories.isEmpty {
                Divider()
                categoriesRow
            } else if isScanning {
                Divider()
                HStack(spacing: 6) {
                    ProgressView()
                        .scaleEffect(0.5)
                    Text("Analysing categories…")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 2)
            } else if !isScanComplete {
                Divider()
                Text("Start a scan to see space breakdown by category")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.vertical, 2)
            }
        }
        .padding(12)
    }

    // MARK: - Gauge

    private func diskGauge(_ ds: DiskSpace) -> some View {
        ZStack {
            Circle()
                .stroke(Color.gray.opacity(0.2), lineWidth: 6)
            Circle()
                .trim(from: 0, to: ds.usedPercentage)
                .stroke(
                    gaugeColor(for: ds.usedPercentage),
                    style: StrokeStyle(lineWidth: 6, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))

            Text("\(Int(ds.usedPercentage * 100))%")
                .font(.system(.caption, design: .rounded, weight: .bold))
        }
        .frame(width: 48, height: 48)
    }

    private func diskStats(_ ds: DiskSpace) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(ds.formattedUsed) used of \(ds.formattedTotal)")
                .font(.subheadline)
                .fontWeight(.medium)
            Text("\(ds.formattedAvailable) available")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    // MARK: - Categories

    private var categoriesRow: some View {
        HStack(spacing: 8) {
            ForEach(smartCategories) { category in
                categoryCard(category)
            }
        }
    }

    private func categoryCard(_ category: SmartCategory) -> some View {
        Button {
            onCategoryTapped(category)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: category.icon)
                    .font(.caption)
                    .foregroundColor(.accentColor)
                VStack(alignment: .leading, spacing: 1) {
                    Text(category.name)
                        .font(.caption2)
                        .foregroundColor(.primary)
                    Text(category.formattedSize)
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(6)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.gray.opacity(0.2), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Helpers

    private var expandCollapseButton: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                isExpanded.toggle()
            }
        } label: {
            Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .buttonStyle(.plain)
    }

    private func gaugeColor(for percentage: Double) -> Color {
        if percentage >= 0.8 { return .red }
        if percentage >= 0.6 { return .yellow }
        return .green
    }
}
```

- [ ] **Step 2: Verify build**

Run: `xcodebuild build -scheme RicCleanMyMac -destination 'platform=macOS' -quiet 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
git add RicCleanMyMac/Views/DiskDashboardHeader.swift
git commit -m "feat(disk-analyzer): add DiskDashboardHeader view"
```

---

### Task 5: Integrate header into `DiskAnalyzerView`

**Files:**
- Modify: `RicCleanMyMac/Views/DiskAnalyzerView.swift`

- [ ] **Step 1: Add large files sheet state**

Add after the existing `@State private var selectedRoot` (line 11):

```swift
@State private var showLargeFiles = false
@State private var largeFileCategory: SmartCategory?
```

- [ ] **Step 2: Insert dashboard header**

The current body starts with a `VStack(spacing: 0)` containing `toolbar`, then `Divider()`, then content. Insert the dashboard header between the toolbar divider and the content.

Replace the body from `toolbar` through the first content block. The current structure is:

```swift
VStack(spacing: 0) {
    toolbar
    Divider()

    if scanner.isLoadingCache {
```

Change it to:

```swift
VStack(spacing: 0) {
    toolbar
    Divider()

    DiskDashboardHeader(
        diskSpace: scanner.diskSpace,
        smartCategories: scanner.smartCategories,
        isScanComplete: scanner.scanResult != nil,
        isScanning: scanner.isScanning,
        onCategoryTapped: { category in
            handleCategoryTap(category)
        }
    )
    Divider()

    if scanner.isLoadingCache {
```

- [ ] **Step 3: Add `loadDiskSpace()` call on appear**

In the `.onAppear` block, add the disk space call. The current block is:

```swift
.onAppear {
    if scanner.scanResult == nil && !scanner.isScanning && !scanner.isLoadingCache {
        startOrLoad(for: selectedRoot)
    }
}
```

Change it to:

```swift
.onAppear {
    scanner.loadDiskSpace()
    if scanner.scanResult == nil && !scanner.isScanning && !scanner.isLoadingCache {
        startOrLoad(for: selectedRoot)
    }
}
```

- [ ] **Step 4: Add category tap handler**

Add a new method in the `// MARK: - Helpers` section:

```swift
private func handleCategoryTap(_ category: SmartCategory) {
    if category.id == "largeFiles" {
        largeFileCategory = category
        showLargeFiles = true
    } else if let firstID = category.nodeIDs.first,
              let node = scanner.scanResult?.root.findNodes(withIDs: Set([firstID])).first {
        scanner.navigateTo(node)
    }
}
```

- [ ] **Step 5: Add large files sheet**

Add a `.sheet` modifier after the existing `.alert(...)` block (after line 61):

```swift
.sheet(isPresented: $showLargeFiles) {
    if let category = largeFileCategory,
       let root = scanner.scanResult?.root {
        LargeFilesSheet(
            nodes: root.findNodes(withIDs: Set(category.nodeIDs)),
            onNavigate: { node in
                showLargeFiles = false
                if let parent = node.parent {
                    scanner.navigateTo(parent)
                }
            },
            onDismiss: { showLargeFiles = false }
        )
    }
}
```

- [ ] **Step 6: Create `LargeFilesSheet` as a private view in the same file**

Add at the bottom of `DiskAnalyzerView.swift`, outside the main struct:

```swift
private struct LargeFilesSheet: View {
    let nodes: [FileNode]
    let onNavigate: (FileNode) -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Large files (> 1 GB)")
                    .font(.headline)
                Spacer()
                Button("Close") { onDismiss() }
                    .buttonStyle(.plain)
            }
            .padding()

            Divider()

            List(sortedNodes, id: \.id) { node in
                Button {
                    onNavigate(node)
                } label: {
                    HStack {
                        Image(systemName: node.icon)
                            .foregroundColor(.secondary)
                        Text(node.name)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        Text(node.formattedSize)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundColor(.accentColor)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .frame(width: 500, height: 400)
    }

    private var sortedNodes: [FileNode] {
        nodes.sorted { $0.size > $1.size }
    }
}
```

- [ ] **Step 7: Verify build**

Run: `xcodebuild build -scheme RicCleanMyMac -destination 'platform=macOS' -quiet 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

- [ ] **Step 8: Manual smoke test**

1. Launch the app, open Disk Analyzer
2. Verify the gauge appears immediately with disk space info
3. Verify smart categories appear after scan completes
4. Click a category (e.g. Cache) — should navigate to that directory
5. Click "Large files" — should open a sheet with files > 1 GB
6. Collapse the header with the chevron — should show compact row
7. Quit and reopen — collapse state should persist

- [ ] **Step 9: Commit**

```bash
git add RicCleanMyMac/Views/DiskAnalyzerView.swift
git commit -m "feat(disk-analyzer): integrate dashboard header into main view"
```
