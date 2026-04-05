# Disk Analyzer — Performance Optimization (Approach A: Quick Wins)

## Context

The disk analyzer scans from `/` and persists results with JSON + LZFSE compression. On subsequent launches, loading the cached scan is slow because:

1. **JSON decode** of the full tree is the primary bottleneck (~70% of load time)
2. **Full path strings** stored per node double RAM usage and serialized size
3. **Scan progress** updates every 1000 files — irregular UX feedback
4. **Sunburst segments** recalculated on every SwiftUI render, not just on navigation

Benchmarks from professional apps (DaisyDisk, ncdu, GrandPerspective) show that compact data models (~25-60 bytes/node vs our ~320) and binary formats drastically improve load times.

## Changes

### 1. Binary plist instead of JSON

**Files:** `Services/DirectoryScanner.swift`

Replace `JSONEncoder`/`JSONDecoder` with `PropertyListEncoder(.binary)`/`PropertyListDecoder` in `saveToDisk()` and `loadFromDisk()`.

- Binary plist is natively optimized by Apple for Codable encode/decode
- Expected improvement: 3-5x faster decode vs JSON
- LZFSE compression stays on top of the binary plist output
- Cache file renamed to `scan-cache.bplist.lzfse` to auto-invalidate old JSON caches

**Changes:**
```swift
// saveToDisk
let encoder = PropertyListEncoder()
encoder.outputFormat = .binary
let data = try encoder.encode(result)
let compressed = try (data as NSData).compressed(using: .lzfse) as Data

// loadFromDisk
let data = try (compressed as NSData).decompressed(using: .lzfse) as Data
let result = try PropertyListDecoder().decode(DirectoryScanResult.self, from: data)
```

### 2. Remove stored `path` from FileNode

**Files:** `Models/FileNode.swift`, `Services/DirectoryScanner.swift`

Replace the stored `path: String` property with a computed property that reconstructs the path from the parent chain.

- Removes ~150 bytes/node of redundant string data
- Halves RAM usage (~350 MB → ~175 MB for 1M files)
- Reduces serialized cache size proportionally
- All call sites (`path` used for delete, open in Finder, etc.) continue to work — same API, computed instead of stored

**FileNode changes:**
```swift
// Remove from stored properties and init
// Remove from CodingKeys

// Add computed property
var path: String {
    guard let parent else { return name }
    return parent.path + "/" + name
}
```

**DirectoryScanner changes:**
- `FileNode` init calls no longer pass `path:` argument
- Root node `name` set to the scan root path (e.g. `"/"`)

### 3. Temporal throttle for scan progress

**Files:** `Services/DirectoryScanner.swift`

Replace the `scannedCount % 1000 == 0` check with a time-based throttle of 100ms.

- Uniform ~10fps progress updates regardless of scan speed
- Prevents both over-updating (many small files) and under-updating (few large files)

**Changes:**
```swift
// Add property
private var lastProgressUpdate: Date = .distantPast

// In buildTree, replace modulo check with:
if Date().timeIntervalSince(lastProgressUpdate) >= 0.1 {
    lastProgressUpdate = Date()
    Task { @MainActor [weak self] in
        self?.progress = ScanProgress(filesScanned: count, currentPath: currentPath)
    }
}
```

### 4. Cache sunburst segments

**Files:** `Views/SunburstChartView.swift`

Cache the result of `SunburstLayout.buildSegments(from:)` and only recalculate when the root node changes.

- Prevents redundant tree traversal on hover, resize, and other SwiftUI redraws
- Segments recalculated only on navigation (node change)

**Changes:**
```swift
// Add state
@State private var cachedSegments: [SunburstSegment] = []

// Compute on node change instead of every render
.onAppear { cachedSegments = SunburstLayout.buildSegments(from: rootNode) }
.onChange(of: rootNode) { _, newNode in
    cachedSegments = SunburstLayout.buildSegments(from: newNode)
}

// Use cachedSegments in body instead of calling buildSegments inline
```

## What is NOT changing

- Overall architecture (class-based FileNode, in-memory tree, DirectoryScanner as ObservableObject)
- Scanning API (still FileManager.contentsOfDirectory)
- UI structure (List, SunburstChartView, BreadcrumbBar)
- LZFSE compression layer
- Async loading flow (Task.detached + MainActor.run)

## Expected impact

| Metric | Before | After (estimated) |
|--------|--------|--------------------|
| Cache decode time | ~3-5s (1M files) | ~0.7-1.5s |
| RAM usage (1M files) | ~350-450 MB | ~175-250 MB |
| Cache file size | Large JSON + LZFSE | ~40-60% smaller |
| Progress UX | Irregular bursts | Smooth 10fps |
| Sunburst redraw | Full traversal per frame | Once per navigation |

## Future considerations (not in scope)

- BSD fts for faster scanning
- Flat array with indices instead of class tree
- SQLite persistence for partial loading
- NSTableView for large directory lists
