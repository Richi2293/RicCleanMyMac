# Binary Cache Format — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace Codable-based cache serialization with a custom binary format to reduce decode time from 59s to 2-4s for 10.4M nodes.

**Architecture:** New `ScanCacheSerializer` enum handles binary read/write. `DirectoryScanner` delegates to it instead of PropertyListEncoder/Decoder. Codable conformance removed from FileNode and DirectoryScanResult.

**Tech Stack:** Swift, Foundation Data, LZFSE compression (unchanged).

**Spec:** `docs/superpowers/specs/2026-04-05-binary-cache-design.md`

---

### Task 1: Create ScanCacheSerializer with write support

**Files:**
- Create: `RicCleanMyMac/Services/ScanCacheSerializer.swift`

- [ ] **Step 1: Create the serializer file with error types and write method**

Create `RicCleanMyMac/Services/ScanCacheSerializer.swift`:

```swift
import Foundation

enum ScanCacheError: Error {
    case invalidMagic
    case unsupportedVersion(UInt8)
    case truncatedData
}

enum ScanCacheSerializer {
    private static let magic: [UInt8] = [0x52, 0x43, 0x53, 0x4E] // "RCSN"
    private static let currentVersion: UInt8 = 1

    // MARK: - Write

    static func write(_ result: DirectoryScanResult) -> Data {
        let estimatedSize = (result.totalFiles + result.totalDirectories) * 36
        var data = Data(capacity: estimatedSize)

        // Header
        data.append(contentsOf: magic)
        data.appendUInt8(currentVersion)
        data.appendUInt32(UInt32(result.totalFiles))
        data.appendUInt32(UInt32(result.totalDirectories))
        data.appendInt64(result.totalSize)
        data.appendFloat64(result.scanDuration)
        data.appendFloat64(result.scanDate.timeIntervalSinceReferenceDate)

        // Tree (depth-first)
        writeNode(result.root, to: &data)

        return data
    }

    private static func writeNode(_ node: FileNode, to data: inout Data) {
        // Name
        let nameBytes = Array(node.name.utf8)
        data.appendUInt16(UInt16(nameBytes.count))
        data.append(contentsOf: nameBytes)

        // Size
        data.appendInt64(node.size)

        // Flags: bit 0 = isDirectory, bit 1 = accessDenied
        var flags: UInt8 = 0
        if node.isDirectory { flags |= 1 }
        if node.accessDenied { flags |= 2 }
        data.appendUInt8(flags)

        // Child count
        let childCount = UInt32(node.children?.count ?? 0)
        data.appendUInt32(childCount)

        // Children (depth-first recursion)
        if let children = node.children {
            for child in children {
                writeNode(child, to: &data)
            }
        }
    }
}

// MARK: - Data Writing Helpers

private extension Data {
    mutating func appendUInt8(_ value: UInt8) {
        append(value)
    }

    mutating func appendUInt16(_ value: UInt16) {
        var v = value.littleEndian
        append(UnsafeBufferPointer(start: &v, count: 1))
    }

    mutating func appendUInt32(_ value: UInt32) {
        var v = value.littleEndian
        append(UnsafeBufferPointer(start: &v, count: 1))
    }

    mutating func appendInt64(_ value: Int64) {
        var v = value.littleEndian
        append(UnsafeBufferPointer(start: &v, count: 1))
    }

    mutating func appendFloat64(_ value: Float64) {
        var v = value.bitPattern.littleEndian
        append(UnsafeBufferPointer(start: &v, count: 1))
    }
}
```

- [ ] **Step 2: Build and verify**

Run: `xcodebuild build -project RicCleanMyMac.xcodeproj -scheme RicCleanMyMac -destination 'platform=macOS' -quiet`

Expected: Build succeeds.

- [ ] **Step 3: Commit**

```bash
git add RicCleanMyMac/Services/ScanCacheSerializer.swift
git commit -m "feat(disk-analyzer): add ScanCacheSerializer with binary write support"
```

---

### Task 2: Add read support to ScanCacheSerializer

**Files:**
- Modify: `RicCleanMyMac/Services/ScanCacheSerializer.swift`

- [ ] **Step 1: Add the BinaryReader helper and read method**

Append the following to `ScanCacheSerializer.swift`, inside the `ScanCacheSerializer` enum (after the `writeNode` method, before the closing `}`):

```swift
    // MARK: - Read

    static func read(from data: Data) throws -> DirectoryScanResult {
        var reader = BinaryReader(data: data)

        // Header
        let fileMagic = try reader.readBytes(4)
        guard fileMagic == magic else { throw ScanCacheError.invalidMagic }

        let version = try reader.readUInt8()
        guard version == currentVersion else { throw ScanCacheError.unsupportedVersion(version) }

        let totalFiles = try reader.readUInt32()
        let totalDirectories = try reader.readUInt32()
        let totalSize = try reader.readInt64()
        let scanDuration = try reader.readFloat64()
        let scanDate = Date(timeIntervalSinceReferenceDate: try reader.readFloat64())

        // Tree
        let root = try readNode(from: &reader, parent: nil)

        return DirectoryScanResult(
            root: root,
            totalSize: totalSize,
            totalFiles: Int(totalFiles),
            totalDirectories: Int(totalDirectories),
            scanDuration: scanDuration,
            scanDate: scanDate
        )
    }

    private static func readNode(from reader: inout BinaryReader, parent: FileNode?) throws -> FileNode {
        let nameLength = try reader.readUInt16()
        let nameBytes = try reader.readBytes(Int(nameLength))
        let name = String(bytes: nameBytes, encoding: .utf8) ?? ""

        let size = try reader.readInt64()
        let flags = try reader.readUInt8()
        let childCount = try reader.readUInt32()

        let node = FileNode(
            name: name,
            size: size,
            isDirectory: flags & 1 != 0,
            accessDenied: flags & 2 != 0
        )
        node.parent = parent

        if childCount > 0 {
            var children: [FileNode] = []
            children.reserveCapacity(Int(childCount))
            for _ in 0..<childCount {
                let child = try readNode(from: &reader, parent: node)
                children.append(child)
            }
            node.children = children
        }

        return node
    }
```

- [ ] **Step 2: Add the BinaryReader struct**

Append the following after the `ScanCacheSerializer` enum closing brace, before the `Data` extension:

```swift
// MARK: - Binary Reader

private struct BinaryReader {
    let data: Data
    var offset: Int = 0

    mutating func readBytes(_ count: Int) throws -> [UInt8] {
        guard offset + count <= data.count else { throw ScanCacheError.truncatedData }
        let bytes = data.withUnsafeBytes { buffer in
            Array(buffer[offset..<offset + count])
        }
        offset += count
        return bytes
    }

    mutating func readUInt8() throws -> UInt8 {
        guard offset + 1 <= data.count else { throw ScanCacheError.truncatedData }
        let value = data[offset]
        offset += 1
        return value
    }

    mutating func readUInt16() throws -> UInt16 {
        guard offset + 2 <= data.count else { throw ScanCacheError.truncatedData }
        let value = data.withUnsafeBytes { buffer in
            buffer.load(fromByteOffset: offset, as: UInt16.self)
        }
        offset += 2
        return UInt16(littleEndian: value)
    }

    mutating func readUInt32() throws -> UInt32 {
        guard offset + 4 <= data.count else { throw ScanCacheError.truncatedData }
        let value = data.withUnsafeBytes { buffer in
            buffer.load(fromByteOffset: offset, as: UInt32.self)
        }
        offset += 4
        return UInt32(littleEndian: value)
    }

    mutating func readInt64() throws -> Int64 {
        guard offset + 8 <= data.count else { throw ScanCacheError.truncatedData }
        let value = data.withUnsafeBytes { buffer in
            buffer.load(fromByteOffset: offset, as: Int64.self)
        }
        offset += 8
        return Int64(littleEndian: value)
    }

    mutating func readFloat64() throws -> Float64 {
        guard offset + 8 <= data.count else { throw ScanCacheError.truncatedData }
        let bits = data.withUnsafeBytes { buffer in
            buffer.load(fromByteOffset: offset, as: UInt64.self)
        }
        offset += 8
        return Float64(bitPattern: UInt64(littleEndian: bits))
    }
}
```

- [ ] **Step 3: Build and verify**

Run: `xcodebuild build -project RicCleanMyMac.xcodeproj -scheme RicCleanMyMac -destination 'platform=macOS' -quiet`

Expected: Build succeeds.

- [ ] **Step 4: Commit**

```bash
git add RicCleanMyMac/Services/ScanCacheSerializer.swift
git commit -m "feat(disk-analyzer): add binary read support to ScanCacheSerializer"
```

---

### Task 3: Wire ScanCacheSerializer into DirectoryScanner

**Files:**
- Modify: `RicCleanMyMac/Services/DirectoryScanner.swift:18-22` (cacheURL)
- Modify: `RicCleanMyMac/Services/DirectoryScanner.swift:68-92` (loadCachedResult)
- Modify: `RicCleanMyMac/Services/DirectoryScanner.swift:288-335` (saveToDisk, loadFromDisk)

- [ ] **Step 1: Update cacheURL filename**

In `DirectoryScanner.swift`, change the cache filename to invalidate old plist cache:

Change:
```swift
private var cacheURL: URL? {
    fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
        .appendingPathComponent("RicCleanMyMac")
        .appendingPathComponent("scan-cache.bplist.lzfse")
}
```

To:
```swift
private var cacheURL: URL? {
    fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
        .appendingPathComponent("RicCleanMyMac")
        .appendingPathComponent("scan-cache.bin.lzfse")
}
```

- [ ] **Step 2: Update saveToDisk to use ScanCacheSerializer**

Replace the `saveToDisk` method:

Change:
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

To:
```swift
private func saveToDisk(_ result: DirectoryScanResult) {
    guard let cacheURL else { return }

    do {
        let directory = cacheURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

        let data = ScanCacheSerializer.write(result)
        let compressed = try (data as NSData).compressed(using: .lzfse) as Data
        try compressed.write(to: cacheURL, options: .atomic)

        logger.info("Saved scan cache (\(compressed.count) bytes compressed, \(data.count) bytes raw)")
    } catch {
        logger.error("Failed to save scan cache: \(error.localizedDescription, privacy: .public)")
    }
}
```

- [ ] **Step 3: Update loadFromDisk to use ScanCacheSerializer**

Replace the `loadFromDisk` method:

```swift
private func loadFromDisk() -> DirectoryScanResult? {
    guard let cacheURL, fileManager.fileExists(atPath: cacheURL.path) else { return nil }

    do {
        var t0 = CFAbsoluteTimeGetCurrent()

        let compressed = try Data(contentsOf: cacheURL)
        let t1 = CFAbsoluteTimeGetCurrent()

        let data = try (compressed as NSData).decompressed(using: .lzfse) as Data
        let t2 = CFAbsoluteTimeGetCurrent()

        let result = try ScanCacheSerializer.read(from: data)
        let t3 = CFAbsoluteTimeGetCurrent()

        logger.info("""
            Cache load timing — \
            read: \(String(format: "%.2f", t1 - t0))s, \
            decompress: \(String(format: "%.2f", t2 - t1))s, \
            decode: \(String(format: "%.2f", t3 - t2))s, \
            compressed: \(compressed.count) bytes, \
            decompressed: \(data.count) bytes, \
            files: \(result.totalFiles), \
            folders: \(result.totalDirectories)
            """)
        return result
    } catch {
        logger.error("Failed to load scan cache: \(error.localizedDescription, privacy: .public)")
        try? fileManager.removeItem(at: cacheURL)
        return nil
    }
}
```

- [ ] **Step 4: Remove rebuildParentReferences from loadCachedResult**

In `loadCachedResult()`, the binary reader already sets parent references during decode. Remove the rebuild call and its timing log.

Change:
```swift
        Task { [weak self] in
            let result = await Task.detached(priority: .userInitiated) { [weak self] () -> DirectoryScanResult? in
                guard let self else { return nil }
                guard let loaded = self.loadFromDisk() else { return nil }
                let t0 = CFAbsoluteTimeGetCurrent()
                loaded.root.rebuildParentReferences()
                let t1 = CFAbsoluteTimeGetCurrent()
                logger.info("rebuildParentReferences: \(String(format: "%.2f", t1 - t0))s")
                return loaded
            }.value
```

To:
```swift
        Task { [weak self] in
            let result = await Task.detached(priority: .userInitiated) { [weak self] () -> DirectoryScanResult? in
                guard let self else { return nil }
                return self.loadFromDisk()
            }.value
```

- [ ] **Step 5: Build and verify**

Run: `xcodebuild build -project RicCleanMyMac.xcodeproj -scheme RicCleanMyMac -destination 'platform=macOS' -quiet`

Expected: Build succeeds.

- [ ] **Step 6: Commit**

```bash
git add RicCleanMyMac/Services/DirectoryScanner.swift
git commit -m "perf(disk-analyzer): wire ScanCacheSerializer into DirectoryScanner

Replaces PropertyListEncoder/Decoder with custom binary serializer.
Parent references are now set during decode, removing the separate
rebuildParentReferences pass."
```

---

### Task 4: Remove Codable from FileNode and DirectoryScanResult

**Files:**
- Modify: `RicCleanMyMac/Models/FileNode.swift:101-136` (remove Codable extension)
- Modify: `RicCleanMyMac/Models/DirectoryScanResult.swift:3` (remove Codable conformance)

- [ ] **Step 1: Remove Codable extension from FileNode**

In `FileNode.swift`, delete the entire `// MARK: - Codable` section (lines 100-136):

```swift
// MARK: - Codable

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

    /// Rebuild weak parent references after decoding from cache.
    /// Required for correct `path` computation (which walks the parent chain).
    func rebuildParentReferences() {
        guard let children else { return }
        for child in children {
            child.parent = self
            child.rebuildParentReferences()
        }
    }
}
```

Delete all of the above. The entire extension including `rebuildParentReferences()` is removed — it's no longer needed because the binary reader sets parent references during decode.

- [ ] **Step 2: Remove Codable from DirectoryScanResult**

In `DirectoryScanResult.swift`, remove `Codable` from the struct declaration:

Change:
```swift
struct DirectoryScanResult: Codable {
```

To:
```swift
struct DirectoryScanResult {
```

- [ ] **Step 3: Build and verify**

Run: `xcodebuild build -project RicCleanMyMac.xcodeproj -scheme RicCleanMyMac -destination 'platform=macOS' -quiet`

Expected: Build succeeds. No remaining references to Codable on these types.

- [ ] **Step 4: Commit**

```bash
git add RicCleanMyMac/Models/FileNode.swift RicCleanMyMac/Models/DirectoryScanResult.swift
git commit -m "refactor(disk-analyzer): remove Codable from FileNode and DirectoryScanResult

No longer needed — serialization is handled by ScanCacheSerializer's
custom binary format."
```
