# Disk Analyzer — Custom Binary Cache Format

## Context

The disk analyzer caches scan results to avoid re-scanning on every app launch. The current format (binary plist + LZFSE) takes 59 seconds to decode 10.4M nodes via PropertyListDecoder. The bottleneck is Codable's per-key reflection and type-checking overhead, not the data format itself.

## Goal

Replace Codable-based serialization with a custom binary format that reads/writes raw bytes sequentially. Target: decode 10.4M nodes in 2-4 seconds.

## Binary Format

### File Header (37 bytes)

```
[magic: 4 bytes "RCSN"]
[version: UInt8 = 1]
[totalFiles: UInt32]
[totalDirectories: UInt32]
[totalSize: Int64]
[scanDuration: Float64]
[scanDate: Float64]
```

Magic number validates the file. Version enables future format changes without crashes.

### Nodes (depth-first, recursive)

Each node is written immediately followed by its children (depth-first order):

```
[nameLength: UInt16]
[name: UTF8 bytes (nameLength)]
[size: Int64]
[flags: UInt8]         — bit 0: isDirectory, bit 1: accessDenied
[childCount: UInt32]
[...children nodes follow immediately...]
```

Children are written recursively in depth-first order. On read, the reader reconstructs the tree by reading `childCount` children after each directory node.

### Estimated sizes

- Per node overhead: ~15 bytes fixed + name length
- Average node: ~35 bytes (20-char name)
- 10.4M nodes: ~364 MB decompressed
- LZFSE compression applies on top (in the existing save/load layer)

## New File: ScanCacheSerializer

**Path:** `RicCleanMyMac/Services/ScanCacheSerializer.swift`

A stateless serializer with two methods:

```swift
enum ScanCacheSerializer {
    static func write(_ result: DirectoryScanResult) throws -> Data
    static func read(from data: Data) throws -> DirectoryScanResult
}
```

### Write

1. Pre-allocate Data buffer (estimated from node count)
2. Write header (magic, version, metadata)
3. Walk tree depth-first, appending each node's bytes
4. Return the complete Data

### Read

1. Validate magic number and version
2. Read header metadata
3. Read nodes depth-first using a recursive function that:
   - Reads name, size, flags, childCount
   - Creates FileNode
   - Recursively reads `childCount` children, setting parent references immediately
4. Return DirectoryScanResult with reconstructed tree

Parent references are set during read — no separate `rebuildParentReferences()` call needed.

### Error Handling

A single `ScanCacheError` enum:
- `.invalidMagic` — file is not a scan cache
- `.unsupportedVersion(UInt8)` — written by a newer app version
- `.truncatedData` — unexpected end of buffer

All errors result in cache deletion and re-scan (existing behavior).

### Read Safety

The reader tracks a current position index and checks bounds before every read. If the index would exceed `data.count`, it throws `.truncatedData`. No unsafe pointer access.

## Changes to Existing Files

### DirectoryScanner.swift

- `cacheURL`: change filename to `scan-cache.bin.lzfse` (invalidates old plist cache)
- `saveToDisk`: replace `PropertyListEncoder` with `ScanCacheSerializer.write`
- `loadFromDisk`: replace `PropertyListDecoder` with `ScanCacheSerializer.read`
- `loadCachedResult`: remove `rebuildParentReferences()` call (reader sets parents during decode)
- Keep timing logs for now

### FileNode.swift

- Remove entire `Codable` extension (CodingKeys, init(from:), encode(to:), rebuildParentReferences)
- The class itself, Hashable conformance, and all other methods stay unchanged

### DirectoryScanResult.swift

- Remove `Codable` conformance from struct declaration

## What Does NOT Change

- FileNode class structure (name, size, isDirectory, accessDenied, children, parent)
- DirectoryScanner scanning logic (performScan, buildTree)
- All views (DiskAnalyzerView, FileListView, SunburstChartView, BreadcrumbBar)
- LZFSE compression layer (stays on top of the binary data)
- Navigation, deletion, selection logic

## Expected Impact

| Metric | Before (plist) | After (binary) |
|--------|---------------|----------------|
| Decode time (10.4M nodes) | 59s | 2-4s |
| rebuildParentReferences | 2.1s | 0s (built during read) |
| Total cache load | ~62s | 2-4s |
| Decompressed size | 378 MB | ~364 MB (similar) |
