# Scan Policy Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make disk analyzer scans faster and safer by introducing a stateless `ScanPolicy` that classifies paths as `scanned`, `readOnly`, or `skipped`, plus a selectable scan root (home / entire disk / custom folder).

**Architecture:** A new `ScanPolicy` enum holds all knowledge of "what to do with this path". `FileNode` gains a `NodeStatus` field replacing `accessDenied`. `DirectoryScanner.buildTree` consults `ScanPolicy` for every entry it encounters and acts accordingly. The scan root becomes configurable in the UI and persisted, with the cache keyed per-root.

**Tech Stack:** Swift 5.9+, SwiftUI, macOS, XCTest-free (the project has no test target — see "No TDD" note below).

**Spec:** `docs/superpowers/specs/2026-04-09-scan-policy-design.md`

**No TDD note:** The RicCleanMyMac Xcode project does not have a unit test target. Adding one is explicitly out of scope for this plan per user decision. Tasks therefore contain no test steps. Validation is done by running a clean build after each task and by end-to-end manual checks at the end. When a test target is eventually added, the test cases documented in the spec's "Testing" section should be implemented against the code this plan produces.

**Build command used in every verification step:**

```bash
xcodebuild -project RicCleanMyMac.xcodeproj -scheme RicCleanMyMac -destination 'platform=macOS' -quiet build
```

---

## File Structure

### New files

- `RicCleanMyMac/Services/ScanPolicy.swift` — stateless classifier. Owns the hard-skip list, the `~/Library` whitelist, the other soft-skip list, and the boot-volume exception logic. Exposes a single public method `ScanPolicy.classify(_:homeDirectory:bootVolumeName:)`.
- `RicCleanMyMac/Models/DiskAnalyzerRoot.swift` — enum with associated values describing the three root choices plus `UserDefaults` codec.

### Modified files

- `RicCleanMyMac/Models/FileNode.swift` — introduce `NodeStatus`, replace `accessDenied`, update factories and `icon`.
- `RicCleanMyMac/Services/DirectoryScanner.swift` — wire `ScanPolicy` into `buildTree`, delete `protectedPrefixes` / `isPathProtected`, update `isNodeDeletable`, per-root cache URL, API changes for `loadCachedResult` / `hasCachedResult`, deletion failure message.
- `RicCleanMyMac/Services/ScanCacheSerializer.swift` — encode/decode `NodeStatus` in the flags byte. Format doc-comment update.
- `RicCleanMyMac/Views/DiskAnalyzerView.swift` — root picker in toolbar, `NSOpenPanel` for custom, `UserDefaults` persistence, route all scan/load calls through a helper that reads the current root.
- `RicCleanMyMac/Views/FileListView.swift` — differentiate `.readOnly` / `.skipped` / `.inaccessible` in the row badge and tap behavior.

---

## Task 1: Create `ScanPolicy`

**Files:**
- Create: `RicCleanMyMac/Services/ScanPolicy.swift`

This task is purely additive — no other file is touched. The build must still succeed because nothing references `ScanPolicy` yet, but the file itself must compile.

- [ ] **Step 1: Create the file with `Classification` enum**

Create `RicCleanMyMac/Services/ScanPolicy.swift` with this initial content:

```swift
import Foundation

/// How the scanner should treat a given path.
enum Classification: Equatable {
    /// Traverse normally, node is deletable.
    case scanned

    /// Traverse and measure, but the node (and descendants that don't override)
    /// must not be deletable from the UI.
    case readOnly

    /// Do not traverse at all. The scanner emits a placeholder directory node
    /// with `size == 0` so the user still sees that the path exists.
    case skipped(reason: String)
}
```

- [ ] **Step 2: Add the `ScanPolicy` enum skeleton and normalization helper**

Append to the same file:

```swift
/// Stateless classifier that decides, for any URL, whether the scanner should
/// traverse it, traverse-but-mark-read-only, or skip it entirely.
///
/// All knowledge of "which system paths should be hidden from the cleaner" is
/// centralized here so the deletion gate and the traversal gate can never
/// diverge. The type is a pure function of its input: no filesystem access,
/// no mutable state.
enum ScanPolicy {
    /// Hard-skip list: these paths (and any descendants) are not traversed.
    /// Matches are applied after path normalization and lowercasing.
    private static let hardSkipPrefixes: [String] = [
        "/system",
        "/usr",
        "/bin",
        "/sbin",
        "/dev",
        "/cores",
        "/.vol",
        "/private/var/db",
        "/private/var/folders",
        "/.spotlight-v100",
        "/.fseventsd",
        "/.documentrevisions-v100",
        "/.temporaryitems",
        "/.trashes",
        "/volumes"
    ]

    /// Exceptions to `hardSkipPrefixes`. If a path matches both a hard-skip
    /// prefix and an exception prefix, the exception wins and the path is
    /// treated normally (`.scanned`).
    private static let hardSkipExceptions: [String] = [
        "/usr/local"
    ]

    /// Soft-skip prefixes outside of `~/Library`. Paths under these roots are
    /// traversed and measured, but the resulting nodes are marked `.readOnly`.
    private static let softSkipPrefixes: [String] = [
        "/library",
        "/applications",
        "/opt"
    ]

    /// Sub-paths of `~/Library` that should remain `.scanned` (deletable) even
    /// though `~/Library` itself is otherwise soft-skipped. These are the
    /// classic "safe to delete to free space" targets.
    ///
    /// Stored without the `~/Library/` prefix; the classifier prepends the
    /// actual home directory at match time.
    private static let libraryWhitelist: [String] = [
        "caches",
        "logs",
        "saved application state",
        "application support/crashreporter",
        "developer/xcode/deriveddata",
        "developer/xcode/ios devicesupport",
        "developer/xcode/watchos devicesupport",
        "developer/xcode/tvos devicesupport",
        "developer/coresimulator/caches"
    ]

    /// Returns `true` if `path` equals `prefix` or starts with `prefix + "/"`.
    /// Both inputs must already be lowercase and not have a trailing slash.
    private static func path(_ path: String, isUnderPrefix prefix: String) -> Bool {
        if path == prefix { return true }
        return path.hasPrefix(prefix + "/")
    }
}
```

- [ ] **Step 3: Add the public `classify` method**

Append inside the `ScanPolicy` enum body (before the closing brace):

```swift
    /// Classify a URL against the policy rules.
    ///
    /// - Parameters:
    ///   - url: The URL to classify. It is standardized internally.
    ///   - homeDirectory: The user's home directory (defaults to the current
    ///     user's home; overridable for future tests).
    ///   - bootVolumeName: The name of the boot volume under `/Volumes` that
    ///     should be allowed through `/Volumes`'s hard-skip. When `nil`, the
    ///     name is resolved lazily from the filesystem.
    /// - Returns: How the scanner should treat this path.
    static func classify(
        _ url: URL,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        bootVolumeName: String? = nil
    ) -> Classification {
        let normalized = url.standardizedFileURL.path
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let absolute = normalized.isEmpty ? "/" : "/" + normalized
        let lower = absolute.lowercased()

        // The root "/" itself is always scanned. Without this, the whole tree
        // starts as `.scanned` because "/" does not match any prefix anyway,
        // but being explicit protects against future rule additions.
        if lower == "/" { return .scanned }

        // Hard-skip exceptions win over hard-skip prefixes.
        for exception in hardSkipExceptions {
            if path(lower, isUnderPrefix: exception) { return .scanned }
        }

        // `/Volumes/<bootVolume>` is allowed through so the user's own disk,
        // which is firmlinked at `/Volumes/<name>` on modern macOS, remains
        // scannable when scanning from `/`.
        if lower.hasPrefix("/volumes/") {
            let resolvedBootName = (bootVolumeName ?? Self.bootVolumeName()).lowercased()
            if !resolvedBootName.isEmpty {
                let bootPrefix = "/volumes/" + resolvedBootName
                if path(lower, isUnderPrefix: bootPrefix) { return .scanned }
            }
        }

        for prefix in hardSkipPrefixes {
            if path(lower, isUnderPrefix: prefix) {
                return .skipped(reason: "System")
            }
        }

        // `~/Library` handling — whitelist first, then soft-skip fallback.
        let homeLower = homeDirectory.standardizedFileURL.path.lowercased()
        let libraryRoot = homeLower.hasSuffix("/")
            ? homeLower + "library"
            : homeLower + "/library"
        if path(lower, isUnderPrefix: libraryRoot) {
            let relative = String(lower.dropFirst(libraryRoot.count))
                .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            for entry in libraryWhitelist {
                if relative == entry || relative.hasPrefix(entry + "/") {
                    return .scanned
                }
            }
            return .readOnly
        }

        for prefix in softSkipPrefixes {
            if path(lower, isUnderPrefix: prefix) {
                return .readOnly
            }
        }

        return .scanned
    }

    /// Resolve the name of the boot volume (the one mounted at `/`). This is
    /// used exactly once per scan run from `DirectoryScanner`, so the cost of
    /// the filesystem call is negligible.
    private static func bootVolumeName() -> String {
        let rootURL = URL(fileURLWithPath: "/")
        let values = try? rootURL.resourceValues(forKeys: [.volumeNameKey])
        return values?.volumeName ?? ""
    }
```

- [ ] **Step 4: Add the file to the Xcode project**

Open `RicCleanMyMac.xcodeproj` in Xcode, right-click the `Services` group in the Project Navigator, pick **Add Files to "RicCleanMyMac"…**, select `RicCleanMyMac/Services/ScanPolicy.swift`, ensure the **RicCleanMyMac** target checkbox is ticked, and click **Add**.

Close Xcode after saving.

- [ ] **Step 5: Build**

Run:
```bash
xcodebuild -project RicCleanMyMac.xcodeproj -scheme RicCleanMyMac -destination 'platform=macOS' -quiet build
```
Expected: `** BUILD SUCCEEDED **` with no errors and no new warnings.

- [ ] **Step 6: Commit**

```bash
git add RicCleanMyMac/Services/ScanPolicy.swift RicCleanMyMac.xcodeproj/project.pbxproj
git commit -m "feat(disk-analyzer): add ScanPolicy classifier

Stateless type that decides whether a path should be scanned, marked
read-only, or skipped entirely. Centralizes the system-path knowledge
that was previously scattered between DirectoryScanner.protectedPrefixes
and ad-hoc checks. Not wired into the scanner yet."
```

---

## Task 2: Migrate `FileNode` to `NodeStatus`

**Files:**
- Modify: `RicCleanMyMac/Models/FileNode.swift`
- Modify: `RicCleanMyMac/Services/DirectoryScanner.swift:224,278,33-35,383-391`
- Modify: `RicCleanMyMac/Services/ScanCacheSerializer.swift:30-35,84-87,146-166`

This is one atomic commit: the type changes in `FileNode`, and every call site is updated in the same commit so the project stays green. No shim.

- [ ] **Step 1: Replace `accessDenied` with `status` in `FileNode.swift`**

In `RicCleanMyMac/Models/FileNode.swift`, replace the property declaration at line 8:

```swift
    private(set) var accessDenied: Bool
```

with:

```swift
    private(set) var status: NodeStatus
```

Then add this enum declaration **above** the `FileNode` class (after the `import Foundation`):

```swift
/// The scanner's verdict on a node, capturing both policy decisions
/// (`.readOnly`, `.skipped`) and runtime failures (`.inaccessible`).
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
```

- [ ] **Step 2: Update `FileNode.icon` to read `status`**

Replace the body of the `icon` computed property (lines 16-22):

```swift
    var icon: String {
        if isDirectory {
            return accessDenied ? "folder.badge.questionmark" : "folder.fill"
        }
        return fileIcon(for: name)
    }
```

with:

```swift
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
```

- [ ] **Step 3: Update the private initializer and factories**

Replace the initializer (lines 41-46):

```swift
    private init(name: String, size: Int64, isDirectory: Bool, accessDenied: Bool) {
        self.name = name
        self.size = size
        self.isDirectory = isDirectory
        self.accessDenied = accessDenied
    }
```

with:

```swift
    private init(name: String, size: Int64, isDirectory: Bool, status: NodeStatus) {
        self.name = name
        self.size = size
        self.isDirectory = isDirectory
        self.status = status
    }
```

Replace the `file` factory (lines 52-54):

```swift
    static func file(name: String, size: Int64) -> FileNode {
        FileNode(name: name, size: size, isDirectory: false, accessDenied: false)
    }
```

with:

```swift
    static func file(name: String, size: Int64, status: NodeStatus = .normal) -> FileNode {
        FileNode(name: name, size: size, isDirectory: false, status: status)
    }
```

Replace the `directory` factory (lines 59-72):

```swift
    static func directory(
        name: String,
        children: [FileNode],
        size: Int64? = nil,
        accessDenied: Bool = false
    ) -> FileNode {
        let totalSize = size ?? children.reduce(Int64(0)) { $0 + $1.size }
        let node = FileNode(name: name, size: totalSize, isDirectory: true, accessDenied: accessDenied)
        node.children = children
        for child in children {
            child.parent = node
        }
        return node
    }
```

with:

```swift
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
```

Replace the `inaccessibleDirectory` factory (lines 75-77):

```swift
    static func inaccessibleDirectory(name: String) -> FileNode {
        FileNode(name: name, size: 0, isDirectory: true, accessDenied: true)
    }
```

with:

```swift
    static func inaccessibleDirectory(name: String) -> FileNode {
        FileNode(name: name, size: 0, isDirectory: true, status: .inaccessible)
    }

    /// Convenience for creating a placeholder node for a directory the scanner
    /// chose not to traverse because `ScanPolicy` returned `.skipped`.
    static func skippedDirectory(name: String, reason: String) -> FileNode {
        FileNode(name: name, size: 0, isDirectory: true, status: .skipped(reason: reason))
    }
```

- [ ] **Step 4: Update `DirectoryScanner.swift` call site in `buildTree`**

In `RicCleanMyMac/Services/DirectoryScanner.swift`, on line 224 replace:

```swift
                return FileNode.directory(name: name, children: children, size: totalSize, accessDenied: false)
```

with:

```swift
                return FileNode.directory(name: name, children: children, size: totalSize, status: .normal)
```

- [ ] **Step 5: Update `DirectoryScanner.isNodeDeletable`**

Replace the `isNodeDeletable` function (lines 277-281):

```swift
    func isNodeDeletable(_ node: FileNode) -> Bool {
        if node.accessDenied { return false }
        if node === scanResult?.root { return false }
        return !isPathProtected(node.path)
    }
```

with:

```swift
    func isNodeDeletable(_ node: FileNode) -> Bool {
        if node === scanResult?.root { return false }
        switch node.status {
        case .normal: return true
        case .readOnly, .skipped, .inaccessible: return false
        }
    }
```

- [ ] **Step 6: Delete `protectedPrefixes` and `isPathProtected`**

In `RicCleanMyMac/Services/DirectoryScanner.swift`, delete the `protectedPrefixes` property declaration (lines 32-36):

```swift
    /// Protected system paths that cannot be deleted. Matched against the
    /// standardized absolute path of each candidate node.
    private let protectedPrefixes: [String] = [
        "/System", "/usr", "/bin", "/sbin", "/private", "/Library"
    ]
```

And delete the `isPathProtected` method (lines 383-391):

```swift
    private func isPathProtected(_ path: String) -> Bool {
        let normalized = URL(fileURLWithPath: path).standardized.path
        for prefix in protectedPrefixes {
            if normalized == prefix || normalized.hasPrefix(prefix + "/") {
                return true
            }
        }
        return false
    }
```

- [ ] **Step 7: Update deletion failure message in `deleteNodes`**

In `RicCleanMyMac/Services/DirectoryScanner.swift`, find the failure block in `deleteNodes` (around line 313-317):

```swift
            guard isNodeDeletable(node) else {
                logger.warning("Skipped non-deletable path: \(node.path, privacy: .public)")
                failures.append(DeletionFailure(
                    path: node.path,
                    reason: "Protected or not deletable"
                ))
                continue
            }
```

Replace with:

```swift
            guard isNodeDeletable(node) else {
                let reason: String
                switch node.status {
                case .readOnly: reason = "Path is read-only"
                case .skipped: reason = "Path is skipped by scan policy"
                case .inaccessible: reason = "Path could not be read during the scan"
                case .normal: reason = "Path is the scan root"
                }
                logger.warning("Skipped non-deletable path: \(node.path, privacy: .public)")
                failures.append(DeletionFailure(path: node.path, reason: reason))
                continue
            }
```

- [ ] **Step 8: Update `ScanCacheSerializer` flag encoding**

In `RicCleanMyMac/Services/ScanCacheSerializer.swift`, update the documentation comment at lines 30-34 from:

```swift
///     flags           1 byte     bit 0 = isDirectory, bit 1 = accessDenied
```

to:

```swift
///     flags           1 byte     bit 0 = isDirectory
///                                bits 1-2 = status (00 = normal, 01 = readOnly,
///                                                   10 = skipped, 11 = inaccessible)
///     skipReasonLen   2 bytes    UInt16, present only when status == skipped
///     skipReasonBytes variable   UTF-8, present only when status == skipped
```

Replace the `writeNode` status-writing block (lines 84-87):

```swift
        var flags: UInt8 = 0
        if node.isDirectory { flags |= 1 }
        if node.accessDenied { flags |= 2 }
        data.appendUInt8(flags)
```

with:

```swift
        var flags: UInt8 = 0
        if node.isDirectory { flags |= 1 }

        let statusBits: UInt8
        switch node.status {
        case .normal:       statusBits = 0b00
        case .readOnly:     statusBits = 0b01
        case .skipped:      statusBits = 0b10
        case .inaccessible: statusBits = 0b11
        }
        flags |= (statusBits << 1)
        data.appendUInt8(flags)

        if case .skipped(let reason) = node.status {
            let reasonBytes = Array(reason.utf8)
            guard reasonBytes.count <= Int(UInt16.max) else {
                throw ScanCacheError.valueTooLarge("skip reason UTF-8 length \(reasonBytes.count) exceeds UInt16 range")
            }
            data.appendUInt16(UInt16(reasonBytes.count))
            data.append(contentsOf: reasonBytes)
        }
```

Replace the `readNode` status-reading block (lines 140-166) — find this section:

```swift
        let size = try reader.readInt64()
        let flags = try reader.readUInt8()
        let childCount = try reader.readUInt32()
        guard childCount <= maxChildCount else {
            throw ScanCacheError.childCountTooLarge(childCount)
        }

        let isDirectory = flags & 1 != 0
        let accessDenied = flags & 2 != 0

        if !isDirectory {
            // Ignore any child entries on a leaf (should be 0 in a valid file).
            return FileNode.file(name: name, size: size)
        }

        var children: [FileNode] = []
        if childCount > 0 {
            children.reserveCapacity(Int(childCount))
            for _ in 0..<childCount {
                children.append(try readNode(from: &reader))
            }
        }
        return FileNode.directory(
            name: name,
            children: children,
            size: size,
            accessDenied: accessDenied
        )
```

and replace with:

```swift
        let size = try reader.readInt64()
        let flags = try reader.readUInt8()

        let isDirectory = flags & 1 != 0
        let statusBits = (flags >> 1) & 0b11
        let status: NodeStatus
        switch statusBits {
        case 0b00: status = .normal
        case 0b01: status = .readOnly
        case 0b10:
            let reasonLen = try reader.readUInt16()
            let reasonBytes = try reader.readBytes(Int(reasonLen))
            guard let reason = String(bytes: reasonBytes, encoding: .utf8) else {
                throw ScanCacheError.corruptedString
            }
            status = .skipped(reason: reason)
        case 0b11: status = .inaccessible
        default:
            // Unreachable because statusBits is two bits, but keep the compiler happy.
            status = .normal
        }

        let childCount = try reader.readUInt32()
        guard childCount <= maxChildCount else {
            throw ScanCacheError.childCountTooLarge(childCount)
        }

        if !isDirectory {
            // Ignore any child entries on a leaf (should be 0 in a valid file).
            return FileNode.file(name: name, size: size, status: status)
        }

        var children: [FileNode] = []
        if childCount > 0 {
            children.reserveCapacity(Int(childCount))
            for _ in 0..<childCount {
                children.append(try readNode(from: &reader))
            }
        }
        return FileNode.directory(
            name: name,
            children: children,
            size: size,
            status: status
        )
```

Note the reorder: we read `size`, then `flags`, then (conditionally) the skip reason, then `childCount`. This matches the new write order.

- [ ] **Step 9: Build**

```bash
xcodebuild -project RicCleanMyMac.xcodeproj -scheme RicCleanMyMac -destination 'platform=macOS' -quiet build
```
Expected: `** BUILD SUCCEEDED **`. If you see `'accessDenied' is not a member` errors, you missed a call site — grep for it and fix.

- [ ] **Step 10: Manual smoke check**

Run the app from Xcode, trigger a scan of a small folder (not `/` — this task hasn't changed the default yet). Expected: scan completes, file list renders, no crashes on nodes that previously had `accessDenied = true`. If a crash happens decoding an old cache, delete it manually: `rm -f "$HOME/Library/Application Support/RicCleanMyMac/scan-cache.bin.lzfse"`. Close the app.

- [ ] **Step 11: Commit**

```bash
git add RicCleanMyMac/Models/FileNode.swift \
        RicCleanMyMac/Services/DirectoryScanner.swift \
        RicCleanMyMac/Services/ScanCacheSerializer.swift
git commit -m "refactor(disk-analyzer): replace FileNode.accessDenied with NodeStatus

Adds a four-case status enum (normal / readOnly / skipped / inaccessible)
to FileNode, replacing the single accessDenied bool. Deletes the now
redundant protectedPrefixes/isPathProtected in DirectoryScanner — the
status is authoritative. Updates ScanCacheSerializer to encode status in
bits 1-2 of the flags byte, with a variable-length reason string for
.skipped. Existing cache files on disk will fail to decode on next load
and be dropped by the existing corrupt-cache fallback."
```

---

## Task 3: Wire `ScanPolicy` into `DirectoryScanner.buildTree`

**Files:**
- Modify: `RicCleanMyMac/Services/DirectoryScanner.swift:156-248`

Now that `FileNode` understands `NodeStatus` and `ScanPolicy` exists, plug them together.

- [ ] **Step 1: Resolve the boot volume name once per scan**

In `RicCleanMyMac/Services/DirectoryScanner.swift`, inside `performScan` (around line 161), right after the opening `return await Task.detached(...)` block and the `let fileManager = FileManager.default` line, add:

```swift
            let bootVolumeName = (try? URL(fileURLWithPath: "/")
                .resourceValues(forKeys: [.volumeNameKey])
                .volumeName) ?? ""
            let homeDirectory = FileManager.default.homeDirectoryForCurrentUser
```

These two values get captured by `buildTree` and passed to `ScanPolicy.classify` on every call, so we avoid resolving them millions of times during recursion.

- [ ] **Step 2: Classify every entry before recursing**

Inside `performScan`'s `buildTree(at:)` function, find the `for itemURL in contents` loop (around line 192-221). Replace the `if isDir { ... } else { ... }` block:

```swift
                    if isDir {
                        let childNode = buildTree(at: itemURL)
                        totalSize += childNode.size
                        children.append(childNode)
                    } else {
                        let fileSize = Int64(values?.fileSize ?? 0)
                        children.append(FileNode.file(name: itemURL.lastPathComponent, size: fileSize))
                        totalSize += fileSize
                        filesCount += 1
                    }
```

with:

```swift
                    if isDir {
                        let classification = ScanPolicy.classify(
                            itemURL,
                            homeDirectory: homeDirectory,
                            bootVolumeName: bootVolumeName
                        )
                        let childNode: FileNode
                        switch classification {
                        case .scanned:
                            childNode = buildTree(at: itemURL)
                        case .readOnly:
                            // Still traverse & measure, but mark as read-only
                            // so the UI and deletion gate know.
                            let scanned = buildTree(at: itemURL)
                            childNode = FileNode.directory(
                                name: scanned.name,
                                children: scanned.children ?? [],
                                size: scanned.size,
                                status: scanned.status == .inaccessible ? .inaccessible : .readOnly
                            )
                        case .skipped(let reason):
                            childNode = FileNode.skippedDirectory(
                                name: itemURL.lastPathComponent,
                                reason: reason
                            )
                            directoriesCount += 1
                        }
                        totalSize += childNode.size
                        children.append(childNode)
                    } else {
                        let fileSize = Int64(values?.fileSize ?? 0)
                        children.append(FileNode.file(name: itemURL.lastPathComponent, size: fileSize))
                        totalSize += fileSize
                        filesCount += 1
                    }
```

Note that the `.readOnly` branch reparents the children: `buildTree` returned them with a stale parent pointer (the inner temporary node), so we rebuild with the same children list. The `FileNode.directory` factory reassigns parents, so after this the parents are correct.

For `.skipped` we increment `directoriesCount` manually because `buildTree` is not called on that subtree; without this, the stats banner would under-count directories.

Inaccessible children retain their `.inaccessible` status when we "re-wrap" for read-only (the `status == .inaccessible ? .inaccessible : .readOnly` line).

- [ ] **Step 3: Do not skip the scan root itself**

The root URL passed to `performScan` should be scanned regardless of policy. Look at `performScan` — it calls `buildTree(at: rootURL)` directly, which works today because `buildTree` doesn't classify `url` itself, only its children. That's correct for this design. No change needed at the top level.

However, if the user explicitly picks `/Library` as root, we want its children to be visible (not classified as read-only by the per-entry check). To support this without special-casing, we just let `ScanPolicy` mark them as `.readOnly` — the user can see the tree but not delete anything, which matches the design.

No code change in this step — just a verification that you understand why no override is needed.

- [ ] **Step 4: Build**

```bash
xcodebuild -project RicCleanMyMac.xcodeproj -scheme RicCleanMyMac -destination 'platform=macOS' -quiet build
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 5: Manual smoke check**

Run the app, trigger a scan from the root (`/`) by temporarily editing `DiskAnalyzerView.swift` to keep `scanner.scan(rootPath: "/")` (it's already the default). The scan should now be noticeably faster, and if you navigate into `/System` or `/usr` you should see a placeholder directory with size 0.

Delete any stale cache first:
```bash
rm -f "$HOME/Library/Application Support/RicCleanMyMac/scan-cache.bin.lzfse"
```

- [ ] **Step 6: Commit**

```bash
git add RicCleanMyMac/Services/DirectoryScanner.swift
git commit -m "feat(disk-analyzer): skip system paths and mark readOnly during traversal

DirectoryScanner now consults ScanPolicy for every directory entry and
emits a placeholder for .skipped subtrees, a read-only wrapper for
.readOnly subtrees, and normal traversal for .scanned. Boot volume name
and home directory are resolved once per scan to avoid filesystem hits
in the hot loop."
```

---

## Task 4: Per-root cache keying

**Files:**
- Modify: `RicCleanMyMac/Services/DirectoryScanner.swift:25-29,39-78,101-135,80-99`
- Modify: `RicCleanMyMac/Views/DiskAnalyzerView.swift:38-46`

The cache must be keyed on the scan root so switching roots doesn't serve the wrong data.

- [ ] **Step 1: Track the current root on the scanner**

In `RicCleanMyMac/Services/DirectoryScanner.swift`, add a new `@Published` property near the top of the class (right after `@Published var lastError: ScanError?` on line 19):

```swift
    /// The root path the scanner is currently working on (either actively
    /// scanning, loading from cache, or showing results for). `nil` when
    /// no scan has started yet this session.
    @Published private(set) var currentRootPath: String?
```

- [ ] **Step 2: Make `cacheURL` take a root path**

Still in `DirectoryScanner.swift`, replace the `cacheURL` property (lines 25-29):

```swift
    private var cacheURL: URL? {
        fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("RicCleanMyMac")
            .appendingPathComponent("scan-cache.bin.lzfse")
    }
```

with:

```swift
    /// Returns the cache URL for a given scan root. The filename embeds a
    /// short hash of the root so different roots never collide.
    private func cacheURL(forRootPath rootPath: String) -> URL? {
        let normalized = URL(fileURLWithPath: rootPath).standardizedFileURL.path
        let digest = Self.shortHash(of: normalized)
        return fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("RicCleanMyMac")
            .appendingPathComponent("scan-cache-\(digest).bin.lzfse")
    }

    /// 16-hex-char prefix of the SHA-256 of the input. Cryptographic strength
    /// is not required — we just need a filename-safe, stable, collision-rare
    /// fingerprint of the root path.
    private static func shortHash(of string: String) -> String {
        let data = Data(string.utf8)
        var hash = [UInt8](repeating: 0, count: 32)
        data.withUnsafeBytes { buffer in
            _ = CC_SHA256(buffer.baseAddress, CC_LONG(buffer.count), &hash)
        }
        return hash.prefix(8).map { String(format: "%02x", $0) }.joined()
    }
```

Add this import at the top of the file (after `import os`):

```swift
import CommonCrypto
```

- [ ] **Step 3: Update `scan(rootPath:)` to set `currentRootPath` and pass it to the cache save**

Still in `DirectoryScanner.swift`, update `scan(rootPath:)` so it records the root and passes it to `handleScanSuccess`.

Find the current `scan` function (lines 39-78) and replace the opening block:

```swift
    func scan(rootPath: String) {
        scanTask?.cancel()
        loadTask?.cancel()
        loadTask = nil

        isScanning = true
        isLoadingCache = false
        scanResult = nil
        currentNode = nil
        selectedItems.removeAll()
        progress = ScanProgress(filesScanned: 0, currentPath: "")
```

with:

```swift
    func scan(rootPath: String) {
        scanTask?.cancel()
        loadTask?.cancel()
        loadTask = nil

        currentRootPath = rootPath
        isScanning = true
        isLoadingCache = false
        scanResult = nil
        currentNode = nil
        selectedItems.removeAll()
        progress = ScanProgress(filesScanned: 0, currentPath: "")
```

And update `handleScanSuccess` (lines 80-99) to use the new cache-URL API:

```swift
    private func handleScanSuccess(_ result: DirectoryScanResult) async {
        scanResult = result
        currentNode = result.root
        isScanning = false

        // Save happens on a detached task so the main thread is not blocked by
        // serialization and LZFSE compression (both are CPU-bound on large trees).
        let cacheURL = self.cacheURL
        Task.detached(priority: .utility) { [weak self] in
            guard let cacheURL else { return }
            do {
                try Self.saveToDisk(result, cacheURL: cacheURL)
            } catch {
                logger.error("Failed to save scan cache: \(error.localizedDescription, privacy: .public)")
                await MainActor.run { [weak self] in
                    self?.lastError = .cacheSaveFailed(error.localizedDescription)
                }
            }
        }
    }
```

Replace with:

```swift
    private func handleScanSuccess(_ result: DirectoryScanResult) async {
        scanResult = result
        currentNode = result.root
        isScanning = false

        // Save happens on a detached task so the main thread is not blocked by
        // serialization and LZFSE compression (both are CPU-bound on large trees).
        guard let rootPath = currentRootPath,
              let cacheURL = cacheURL(forRootPath: rootPath) else { return }
        Task.detached(priority: .utility) { [weak self] in
            do {
                try Self.saveToDisk(result, cacheURL: cacheURL)
            } catch {
                logger.error("Failed to save scan cache: \(error.localizedDescription, privacy: .public)")
                await MainActor.run { [weak self] in
                    self?.lastError = .cacheSaveFailed(error.localizedDescription)
                }
            }
        }
    }
```

- [ ] **Step 4: Update `hasCachedResult` and `loadCachedResult` to take a root path**

Still in `DirectoryScanner.swift`, replace the `hasCachedResult` property (around line 102) and `loadCachedResult` function (around lines 108-135):

```swift
    /// Whether a cached scan exists on disk.
    var hasCachedResult: Bool {
        guard let cacheURL else { return false }
        return fileManager.fileExists(atPath: cacheURL.path)
    }

    /// Load cached scan result asynchronously (off the main thread).
    func loadCachedResult() {
        guard scanResult == nil, !isLoadingCache, !isScanning else { return }
        isLoadingCache = true

        let cacheURL = self.cacheURL
        loadTask = Task { [weak self] in
            let outcome: CacheLoadOutcome = await Task.detached(priority: .userInitiated) {
                guard let cacheURL else { return .notFound }
                return Self.loadFromDisk(cacheURL: cacheURL)
            }.value

            guard let self, !Task.isCancelled else { return }

            self.isLoadingCache = false
            self.loadTask = nil

            switch outcome {
            case .success(let result):
                self.scanResult = result
                self.currentNode = result.root
            case .notFound:
                // No cache yet — UI handles this by offering a fresh scan.
                break
            case .failed(let reason):
                self.lastError = .cacheLoadFailed(reason)
            }
        }
    }
```

Replace with:

```swift
    /// Whether a cached scan exists on disk for the given root path.
    func hasCachedResult(forRootPath rootPath: String) -> Bool {
        guard let cacheURL = cacheURL(forRootPath: rootPath) else { return false }
        return fileManager.fileExists(atPath: cacheURL.path)
    }

    /// Load the cached scan result for the given root path asynchronously
    /// (off the main thread).
    func loadCachedResult(forRootPath rootPath: String) {
        guard scanResult == nil, !isLoadingCache, !isScanning else { return }
        currentRootPath = rootPath
        isLoadingCache = true

        let cacheURL = self.cacheURL(forRootPath: rootPath)
        loadTask = Task { [weak self] in
            let outcome: CacheLoadOutcome = await Task.detached(priority: .userInitiated) {
                guard let cacheURL else { return .notFound }
                return Self.loadFromDisk(cacheURL: cacheURL)
            }.value

            guard let self, !Task.isCancelled else { return }

            self.isLoadingCache = false
            self.loadTask = nil

            switch outcome {
            case .success(let result):
                self.scanResult = result
                self.currentNode = result.root
            case .notFound:
                // No cache yet — UI handles this by offering a fresh scan.
                break
            case .failed(let reason):
                self.lastError = .cacheLoadFailed(reason)
            }
        }
    }
```

- [ ] **Step 5: Update `DiskAnalyzerView` call sites**

In `RicCleanMyMac/Views/DiskAnalyzerView.swift`, update the `onAppear` block (lines 38-46):

```swift
        .onAppear {
            if scanner.scanResult == nil && !scanner.isScanning && !scanner.isLoadingCache {
                if scanner.hasCachedResult {
                    scanner.loadCachedResult()
                } else {
                    scanner.scan(rootPath: "/")
                }
            }
        }
```

Replace with:

```swift
        .onAppear {
            if scanner.scanResult == nil && !scanner.isScanning && !scanner.isLoadingCache {
                let root = "/"
                if scanner.hasCachedResult(forRootPath: root) {
                    scanner.loadCachedResult(forRootPath: root)
                } else {
                    scanner.scan(rootPath: root)
                }
            }
        }
```

(The hardcoded `"/"` here will be replaced in Task 5 when we add the root picker. For now it preserves current behavior.)

- [ ] **Step 6: Build**

```bash
xcodebuild -project RicCleanMyMac.xcodeproj -scheme RicCleanMyMac -destination 'platform=macOS' -quiet build
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 7: Manual smoke check**

Delete any old single-file cache first:
```bash
rm -f "$HOME/Library/Application Support/RicCleanMyMac/scan-cache.bin.lzfse"
```

Run the app and trigger a scan. Confirm that after the scan completes, a new file appears under Application Support whose name matches `scan-cache-<hex>.bin.lzfse`:
```bash
ls -la "$HOME/Library/Application Support/RicCleanMyMac/"
```

- [ ] **Step 8: Commit**

```bash
git add RicCleanMyMac/Services/DirectoryScanner.swift \
        RicCleanMyMac/Views/DiskAnalyzerView.swift
git commit -m "feat(disk-analyzer): key scan cache by root path

Cache filename now embeds a short SHA-256 prefix of the normalized root
path, so scans of different roots don't overwrite each other. The
scanner tracks the current root explicitly, and the cache load/save
paths route through a single helper that derives the URL from the
current root. DiskAnalyzerView's onAppear is updated to pass the root
through the new API."
```

---

## Task 5: Root selection UI

**Files:**
- Create: `RicCleanMyMac/Models/DiskAnalyzerRoot.swift`
- Modify: `RicCleanMyMac/Views/DiskAnalyzerView.swift`

The user needs to be able to pick between home, entire disk, and a custom folder, and the choice must persist across launches.

- [ ] **Step 1: Create the `DiskAnalyzerRoot` model**

Create `RicCleanMyMac/Models/DiskAnalyzerRoot.swift`:

```swift
import Foundation

/// Which directory the disk analyzer is scanning.
enum DiskAnalyzerRoot: Equatable {
    /// The user's home directory (`~`). This is the default.
    case home

    /// The entire boot volume (`/`).
    case entireDisk

    /// A user-chosen folder.
    case custom(path: String)

    /// The absolute filesystem path this root resolves to right now.
    var path: String {
        switch self {
        case .home:       return FileManager.default.homeDirectoryForCurrentUser.path
        case .entireDisk: return "/"
        case .custom(let path): return path
        }
    }

    /// Short human-readable label for the toolbar picker.
    var label: String {
        switch self {
        case .home:       return "Home"
        case .entireDisk: return "Entire disk"
        case .custom(let path): return (path as NSString).lastPathComponent
        }
    }

    // MARK: - UserDefaults codec

    private static let key = "diskAnalyzer.defaultRoot"

    /// Persist the current choice. Uses a simple string encoding:
    /// - `"home"` / `"root"` / `"custom:<absolutePath>"`
    func save(to defaults: UserDefaults = .standard) {
        let encoded: String
        switch self {
        case .home:       encoded = "home"
        case .entireDisk: encoded = "root"
        case .custom(let path): encoded = "custom:\(path)"
        }
        defaults.set(encoded, forKey: Self.key)
    }

    /// Load the persisted choice, defaulting to `.home` when no value was
    /// stored or when the stored value is malformed.
    static func load(from defaults: UserDefaults = .standard) -> DiskAnalyzerRoot {
        guard let raw = defaults.string(forKey: key) else { return .home }
        switch raw {
        case "home":       return .home
        case "root":       return .entireDisk
        default:
            if raw.hasPrefix("custom:") {
                let path = String(raw.dropFirst("custom:".count))
                if !path.isEmpty { return .custom(path: path) }
            }
            return .home
        }
    }
}
```

- [ ] **Step 2: Add the file to the Xcode project**

In Xcode, right-click the `Models` group, **Add Files to "RicCleanMyMac"…**, select `RicCleanMyMac/Models/DiskAnalyzerRoot.swift`, verify the target checkbox, click **Add**, close Xcode.

- [ ] **Step 3: Add state and a helper to `DiskAnalyzerView`**

In `RicCleanMyMac/Views/DiskAnalyzerView.swift`, add new `@State` right after the existing `@State` declarations (around line 10, after `@State private var isDeleting = false`):

```swift
    @State private var selectedRoot: DiskAnalyzerRoot = DiskAnalyzerRoot.load()
```

Then add a private helper at the end of the view (before the closing `}`):

```swift
    /// Start a scan (or load the cache) for the currently selected root.
    /// Persists the choice so the next app launch reopens the same root.
    private func startOrLoad(for root: DiskAnalyzerRoot) {
        selectedRoot = root
        root.save()
        let path = root.path
        if scanner.hasCachedResult(forRootPath: path) {
            scanner.loadCachedResult(forRootPath: path)
        } else {
            scanner.scan(rootPath: path)
        }
    }

    /// Force a fresh re-scan of the current root, ignoring any cache.
    private func rescanCurrentRoot() {
        scanner.scan(rootPath: selectedRoot.path)
    }
```

- [ ] **Step 4: Replace the `onAppear` body**

In `DiskAnalyzerView.swift`, replace the current `onAppear` block:

```swift
        .onAppear {
            if scanner.scanResult == nil && !scanner.isScanning && !scanner.isLoadingCache {
                let root = "/"
                if scanner.hasCachedResult(forRootPath: root) {
                    scanner.loadCachedResult(forRootPath: root)
                } else {
                    scanner.scan(rootPath: root)
                }
            }
        }
```

with:

```swift
        .onAppear {
            if scanner.scanResult == nil && !scanner.isScanning && !scanner.isLoadingCache {
                startOrLoad(for: selectedRoot)
            }
        }
```

- [ ] **Step 5: Add the root picker to the toolbar**

In `DiskAnalyzerView.swift`, find the `toolbar` computed property (around line 69-101). Locate the "Re-scan" button block:

```swift
            if scanner.scanResult != nil {
                Button {
                    scanner.scan(rootPath: "/")
                } label: {
                    Label("Re-scan", systemImage: "arrow.clockwise")
                }
            }
```

Replace with:

```swift
            rootPicker

            if scanner.scanResult != nil {
                Button {
                    rescanCurrentRoot()
                } label: {
                    Label("Re-scan", systemImage: "arrow.clockwise")
                }
            }
```

Then add the `rootPicker` view at the end of the file (inside the struct, before the closing brace, alongside the other `@ViewBuilder` helpers):

```swift
    @ViewBuilder
    private var rootPicker: some View {
        Menu {
            Button("Home") { startOrLoad(for: .home) }
            Button("Entire disk") { startOrLoad(for: .entireDisk) }
            Divider()
            Button("Choose folder…") { pickCustomRoot() }
        } label: {
            Label(selectedRoot.label, systemImage: "folder")
                .font(.subheadline)
        }
        .menuStyle(.borderlessButton)
        .frame(minWidth: 120)
    }

    private func pickCustomRoot() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Scan this folder"
        panel.message = "Pick a folder to scan."
        if panel.runModal() == .OK, let url = panel.url {
            startOrLoad(for: .custom(path: url.path))
        }
    }
```

- [ ] **Step 6: Replace the remaining hardcoded `"/"` in `emptyState`**

In `DiskAnalyzerView.swift`, find the `emptyState` (around line 181-200). Replace:

```swift
            Button {
                scanner.scan(rootPath: "/")
            } label: {
                Label("Scan Now", systemImage: "magnifyingglass")
            }
```

with:

```swift
            Button {
                startOrLoad(for: selectedRoot)
            } label: {
                Label("Scan \(selectedRoot.label)", systemImage: "magnifyingglass")
            }
```

- [ ] **Step 7: Verify no hardcoded `"/"` calls remain**

Run from the project root:
```bash
grep -n 'scan(rootPath: "/")' RicCleanMyMac/Views/DiskAnalyzerView.swift
```
Expected: no output. If any hits remain, replace them with `startOrLoad(for: selectedRoot)` or `rescanCurrentRoot()` depending on whether the action is "kick off (possibly from cache)" or "force a fresh scan".

- [ ] **Step 8: Build**

```bash
xcodebuild -project RicCleanMyMac.xcodeproj -scheme RicCleanMyMac -destination 'platform=macOS' -quiet build
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 9: Manual smoke check**

Run the app. The disk analyzer should open on the Home root by default. Use the menu to switch to Entire disk and back — each switch should trigger either a cached load or a fresh scan. Then pick a small folder via "Choose folder…" and confirm it scans that folder. Quit the app and relaunch: it should reopen on the last-selected root.

- [ ] **Step 10: Commit**

```bash
git add RicCleanMyMac/Models/DiskAnalyzerRoot.swift \
        RicCleanMyMac/Views/DiskAnalyzerView.swift \
        RicCleanMyMac.xcodeproj/project.pbxproj
git commit -m "feat(disk-analyzer): selectable scan root with home as default

Adds a menu in the toolbar to pick between Home (new default), Entire
disk, and a custom folder (via NSOpenPanel). The choice is persisted to
UserDefaults under diskAnalyzer.defaultRoot and restored on next launch.
All scan/cache-load call sites now route through a single helper that
reads the current root, so the hardcoded '/' is gone from the view."
```

---

## Task 6: UI badges for `readOnly` and `skipped`

**Files:**
- Modify: `RicCleanMyMac/Views/FileListView.swift:60-149`

Make it obvious in the file list which rows are read-only and which are skipped placeholders.

- [ ] **Step 1: Show status-specific leading icon in the row**

In `RicCleanMyMac/Views/FileListView.swift`, find the `FileListRow.body` (around lines 68-125). Replace the leading HStack section (the `if isDeletable { ... } else { ... }` block at lines 70-80):

```swift
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
```

with:

```swift
            leadingControl
```

Then add this computed property at the end of `FileListRow` (before the `sizeBar` helper):

```swift
    @ViewBuilder
    private var leadingControl: some View {
        if isDeletable {
            Button(action: onToggleSelection) {
                Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                    .foregroundColor(isSelected ? .accentColor : .secondary)
            }
            .buttonStyle(.plain)
        } else {
            switch node.status {
            case .readOnly:
                Image(systemName: "lock.fill")
                    .foregroundColor(.secondary.opacity(0.6))
                    .frame(width: 16)
                    .help("Read-only: protected by scan policy")
            case .skipped:
                Image(systemName: "minus.circle")
                    .foregroundColor(.secondary.opacity(0.5))
                    .frame(width: 16)
                    .help("Skipped: not scanned")
            case .inaccessible:
                Image(systemName: "exclamationmark.triangle")
                    .foregroundColor(.orange.opacity(0.7))
                    .frame(width: 16)
                    .help("Could not be read")
            case .normal:
                // Only reached for the scan root (which is .normal but
                // `isDeletable` returns false). Use a neutral placeholder.
                Image(systemName: "circle.dashed")
                    .foregroundColor(.secondary.opacity(0.4))
                    .frame(width: 16)
            }
        }
    }
```

- [ ] **Step 2: Add a status badge next to the name**

Still in `FileListRow.body`, find the `VStack(alignment: .leading, spacing: 2)` that shows the name (around lines 86-97):

```swift
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
```

Replace with:

```swift
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(node.name)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .lineLimit(1)
                        .foregroundColor(nameColor)
                    statusBadge
                }

                if node.isDirectory, let childCount = node.children?.count {
                    Text("\(childCount) item(s)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
```

Then add these two helpers to `FileListRow`, next to `leadingControl`:

```swift
    private var nameColor: Color {
        switch node.status {
        case .skipped, .inaccessible: return .secondary
        default: return .primary
        }
    }

    @ViewBuilder
    private var statusBadge: some View {
        switch node.status {
        case .readOnly:
            Text("read-only")
                .font(.caption2)
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(Color.secondary.opacity(0.12))
                .cornerRadius(3)
                .foregroundColor(.secondary)
        case .skipped(let reason):
            Text("skipped: \(reason.lowercased())")
                .font(.caption2)
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(Color.secondary.opacity(0.12))
                .cornerRadius(3)
                .foregroundColor(.secondary)
        default:
            EmptyView()
        }
    }
```

- [ ] **Step 3: Blank the size column for skipped nodes**

Still in `FileListRow.body`, find the size label (around lines 104-108):

```swift
            Text(node.formattedSize)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(.secondary)
                .frame(width: 70, alignment: .trailing)
```

Replace with:

```swift
            Text(sizeText)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(.secondary)
                .frame(width: 70, alignment: .trailing)
```

And add this helper right after `statusBadge`:

```swift
    private var sizeText: String {
        if case .skipped = node.status { return "—" }
        return node.formattedSize
    }
```

- [ ] **Step 4: Do not tap-to-navigate into skipped placeholders**

Still in `FileListRow.body`, find the `onTapGesture` block (around lines 118-124):

```swift
        .onTapGesture {
            if node.isDirectory {
                onNavigate()
            } else if isDeletable {
                onToggleSelection()
            }
        }
```

Replace with:

```swift
        .onTapGesture {
            if case .skipped = node.status {
                return
            }
            if node.isDirectory {
                onNavigate()
            } else if isDeletable {
                onToggleSelection()
            }
        }
```

- [ ] **Step 5: Build**

```bash
xcodebuild -project RicCleanMyMac.xcodeproj -scheme RicCleanMyMac -destination 'platform=macOS' -quiet build
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 6: Manual smoke check**

Delete any leftover cache:
```bash
rm -f "$HOME/Library/Application Support/RicCleanMyMac/scan-cache-"*.bin.lzfse
```

Run the app, pick **Entire disk** from the root picker, wait for the scan. Navigate to `/` and verify:
- `/System`, `/usr`, `/bin`, `/sbin`, `/Volumes` etc. show with a "minus.circle" icon, grey name, "skipped: system" badge, and size `—`. Tapping them does nothing.
- `/Library`, `/Applications`, `/opt` show with a lock icon, a "read-only" badge, and their normal size. Tapping navigates into them, but you cannot delete anything inside.
- Navigate into `~/Library`: most entries are read-only, but `Caches`, `Logs`, `Saved Application State`, and `Developer/Xcode/DerivedData` (if present) are normal and deletable.

- [ ] **Step 7: Commit**

```bash
git add RicCleanMyMac/Views/FileListView.swift
git commit -m "feat(disk-analyzer): show readOnly and skipped states in file list

Read-only rows get a lock icon + 'read-only' badge; skipped placeholders
get a minus icon + 'skipped: <reason>' badge and a blank size column,
and don't respond to tap. Inaccessible nodes now use a warning triangle
to distinguish them from the policy-driven states."
```

---

## End-to-end verification

- [ ] **Step 1: Clean state**

Delete all scan caches and `UserDefaults` for the app so the test starts cold:

```bash
rm -f "$HOME/Library/Application Support/RicCleanMyMac/scan-cache-"*.bin.lzfse
defaults delete "$(defaults read-type -app RicCleanMyMac 2>/dev/null | head -1)" 2>/dev/null || true
```

(The `defaults delete` is best-effort — if the app uses a non-standard bundle identifier the command may no-op, which is fine. We only care about the `diskAnalyzer.defaultRoot` key being absent.)

- [ ] **Step 2: Fresh launch, home-default scan**

Run the app from Xcode. Expected:
- Disk analyzer opens on **Home** root.
- Scan runs and completes in noticeably less time than before the plan (the old default was `/`; now it's `~`).
- File list shows top-level home contents. `Library` shows as read-only with a lock badge.

- [ ] **Step 3: Switch roots**

From the root picker, pick **Entire disk**. A fresh scan runs. Expected:
- Much faster than a pre-plan scan of `/` would have been.
- Top level shows `/System`, `/usr`, `/bin`, `/sbin`, `/Volumes`, `/.Spotlight-V100`, etc. as **skipped** with size `—`.
- `/Library`, `/Applications`, `/opt` show as **read-only** with their normal sizes.
- `/Users` is normal and deletable.

- [ ] **Step 4: Custom folder**

Pick **Choose folder…** and select `~/Downloads`. Expected: scan completes quickly, all entries are normal and deletable.

- [ ] **Step 5: Persistence**

Quit the app and relaunch. Expected: disk analyzer opens on `~/Downloads` (the last selection) and loads the cache for that root without re-scanning.

- [ ] **Step 6: Cache isolation**

```bash
ls "$HOME/Library/Application Support/RicCleanMyMac/"
```
Expected: three `scan-cache-<hex>.bin.lzfse` files — one per root you scanned (Home, Entire disk, Downloads).

- [ ] **Step 7: Deletion gate**

In any scan, navigate into a read-only subtree (e.g. `/Library/Frameworks`) and right-click a file. The context menu must **not** show the Delete option, and the checkbox in the row must be absent. Go back to a normal subtree (e.g. `~/Downloads`) and confirm deletion is still offered.

---

## Self-review

**Spec coverage:**
- ✅ §1 `ScanPolicy` classifier — Task 1
- ✅ §2 `NodeStatus` replaces `accessDenied` — Task 2
- ✅ §3 `DirectoryScanner` wiring — Tasks 2 (deletion gate) + 3 (traversal)
- ✅ §4 Root selection UI + `UserDefaults` — Task 5
- ✅ §5 Per-root cache — Task 4
- ✅ §6 Cache format update (no version bump) — Task 2, Step 8
- ✅ §7 UI treatment for readOnly / skipped — Task 6
- ⚠️ Testing section — intentionally deferred (see "No TDD note" at top). The test cases in the spec remain as documentation for when a test target is added.

**Placeholder scan:** no TBD / TODO / "add appropriate error handling" / "similar to Task N" strings. Every code step contains complete snippets.

**Type consistency:**
- `NodeStatus` cases (`normal` / `readOnly` / `skipped(reason:)` / `inaccessible`) are used identically in every task that references them.
- `Classification` cases (`scanned` / `readOnly` / `skipped(reason:)`) are distinct from `NodeStatus` by design — the classifier output and the node status are not the same type.
- `ScanPolicy.classify(_:homeDirectory:bootVolumeName:)` signature matches between its definition (Task 1) and call site (Task 3).
- `DirectoryScanner.hasCachedResult(forRootPath:)` and `loadCachedResult(forRootPath:)` signatures match between Task 4 Step 4 and Task 5 helper usage.
- `DiskAnalyzerRoot.load()` / `save()` / `path` / `label` members used in Task 5 match the definition in that same task.
- `FileNode.skippedDirectory(name:reason:)` introduced in Task 2 Step 3 is used in Task 3 Step 2.
