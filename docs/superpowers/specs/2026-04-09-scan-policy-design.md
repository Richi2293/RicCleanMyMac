# Disk Analyzer — Scan Policy (selective traversal + read-only zones)

## Context

Today `DirectoryScanner` starts every scan from `/` (hardcoded in three call sites of
`DiskAnalyzerView.swift`) and walks the entire volume. The only protection mechanism is
`protectedPrefixes` in `DirectoryScanner.swift:33`, which prevents deletion of a fixed list
of system roots — but it does **not** prevent the scanner from traversing them. As a result:

1. Every scan spends time reading `/System`, `/Library`, `/usr`, `/private/var/folders`, etc.
   — content the user can never act on anyway.
2. External volumes under `/Volumes` are traversed too, which can block the scan on slow or
   network-mounted drives.
3. There is no way for the user to scope the scan to their home or to an arbitrary folder.
4. The deletion allow-list (`protectedPrefixes`) and the scan traversal logic are disconnected,
   so changes to "what is safe" have to be made in two places.

Reference behavior of existing cleaners:

- **CleanMyMac X**'s "Space Lens" defaults to `~` (not `/`) and explicitly marks `~/Library` as
  read-only "system data". It never does a full-disk walk from `/`.
- **DaisyDisk** does walk from `/`, but uses a privileged helper and visually segregates
  system-owned regions so the user never tries to act on them.

We want to support both styles: a fast default (`~`) aligned with the cleaner use case, and an
explicit "entire disk" mode for power users.

## Goals

1. **Faster scans** by not traversing paths that can never yield actionable results.
2. **Safer UI** by surfacing read-only regions explicitly so the user can see their weight
   without being able to delete them by mistake.
3. **Single source of truth** for "what is scannable / deletable / skipped", isolated in a
   testable type.
4. **Configurable scan root** so the user can scan their home, the entire disk, or a custom
   folder.

## Non-goals

- Exposing the skip policy as user-editable preferences (may come later; not in this spec).
- Running scans with elevated privileges (DaisyDisk-style) to reach paths the user cannot read.
- Replacing or redesigning the treemap / sunburst visualization.

## Design

### 1. `ScanPolicy` — single source of truth

A new file `RicCleanMyMac/Services/ScanPolicy.swift` owns all knowledge about how a given path
should be treated.

```swift
enum Classification: Equatable {
    case scanned                          // traverse normally, deletable
    case readOnly                         // traverse and measure, NOT deletable
    case skipped(reason: String)          // do not traverse, emit placeholder node
}

enum ScanPolicy {
    static func classify(
        _ url: URL,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        bootVolumeName: String? = nil     // resolved lazily inside when nil
    ) -> Classification
}
```

Rules, applied in order:

1. **Normalize** the input via `url.standardized.path`. Comparison is case-insensitive
   (macOS APFS/HFS+ is case-insensitive by default).
2. **Hard-skip list** — return `.skipped(reason:)` if the normalized path equals or is a
   child of any of:
   ```
   /System
   /usr                  (exception: /usr/local and its subtree → .scanned)
   /bin
   /sbin
   /dev
   /cores
   /.vol
   /private/var/db
   /private/var/folders
   /.Spotlight-V100
   /.fseventsd
   /.DocumentRevisions-V100
   /.TemporaryItems
   /.Trashes             (root-level only, NOT ~/.Trash)
   /Volumes              (exception: the boot volume's own firmlink → .scanned)
   ```
3. **`~/Library` whitelist** — if the path is inside `~/Library` and inside one of these
   subtrees, return `.scanned`:
   ```
   ~/Library/Caches
   ~/Library/Logs
   ~/Library/Saved Application State
   ~/Library/Application Support/CrashReporter
   ~/Library/Developer/Xcode/DerivedData
   ~/Library/Developer/Xcode/iOS DeviceSupport
   ~/Library/Developer/Xcode/watchOS DeviceSupport
   ~/Library/Developer/Xcode/tvOS DeviceSupport
   ~/Library/Developer/CoreSimulator/Caches
   ```
4. **`~/Library` soft skip** — any other path under `~/Library` returns `.readOnly`.
5. **Other soft-skip list** — return `.readOnly` if the normalized path equals or is a
   child of any of:
   ```
   /Library
   /Applications
   /opt
   ```
6. Otherwise return `.scanned`.

The chosen root URL itself is **never** skipped: if the user explicitly picks a path that would
normally be classified as `.skipped` or `.readOnly`, the root node is forced to `.scanned` so
the scan can actually run. This is a small override on the root node only, applied in
`DirectoryScanner`, not in `ScanPolicy` itself.

### 2. `NodeStatus` replaces `accessDenied`

`FileNode.accessDenied: Bool` conflates two distinct things today (I/O failure vs. not
deletable). Replace it with:

```swift
enum NodeStatus: Equatable {
    case normal                        // scanned, deletable
    case readOnly                      // scanned, NOT deletable per policy
    case skipped(reason: String)       // not traversed, size is 0
    case inaccessible                  // I/O error during traversal (former accessDenied)
}
```

`FileNode.inaccessibleDirectory(name:)` remains as a convenience constructor but now produces
a node with `status == .inaccessible`.

A backwards-compatible computed property `accessDenied: Bool` returns `true` for
`.inaccessible` only, so any residual callers continue to behave correctly until migrated.

### 3. `DirectoryScanner` wiring

- `performScan` receives the `ScanPolicy` type as a parameter (default: production `ScanPolicy`),
  so tests can inject a fake.
- `buildTree(at:)` calls `ScanPolicy.classify(url)` on every directory entry it encounters
  and acts on the result:
  - `.scanned` — current behavior: recurse if directory, read size if file.
  - `.readOnly` — still recurse and measure children (the UI needs the size), but mark the
    resulting node with `status = .readOnly`.
  - `.skipped(reason)` — do NOT recurse; emit a leaf-like placeholder directory node with
    `size = 0` and `status = .skipped(reason)`.

  `ScanPolicy` is stateless: each entry is classified independently, so a `.readOnly`
  parent does not need to "propagate" its status to children. A child of `~/Library` that
  falls into the whitelist (e.g. `~/Library/Caches`) naturally classifies as `.scanned`
  without any special handling, and all other children naturally classify as `.readOnly`
  because of rule 4 in the classification order above.
- `protectedPrefixes` and `isPathProtected(_:)` are **deleted**. Deletion gating becomes:
  ```swift
  func isNodeDeletable(_ node: FileNode) -> Bool {
      if node === scanResult?.root { return false }
      if case .normal = node.status { return true }
      return false
  }
  ```

### 4. Scan root selection

`DiskAnalyzerView` gets a small control in its header (picker or segmented control) with three
options:

- **Home** (`~`) — new default
- **Entire disk** (`/`) — equivalent to current behavior
- **Choose folder…** — opens `NSOpenPanel` with `canChooseDirectories = true`

The three hardcoded `scanner.scan(rootPath: "/")` call sites in `DiskAnalyzerView.swift`
(lines 43, 73, 193) all route through a single helper that reads the current root from the
view model.

The selected root is persisted in `UserDefaults` under `diskAnalyzer.defaultRoot` with values:
- `"home"` → `FileManager.default.homeDirectoryForCurrentUser.path`
- `"root"` → `"/"`
- `"custom:<absolutePath>"` → the saved path

On app launch, the view model reads this preference and uses it as the current root.

### 5. Per-root cache

`DirectoryScanner.cacheURL` is currently a single file `scan-cache.bin.lzfse`. Because the root
is now variable, the cache filename must be keyed on the root so a cached scan of `~` is never
mistakenly loaded when the user asked for `/`.

New cache path:
```
<AppSupport>/RicCleanMyMac/scan-cache-<sha256(rootPath).prefix(16)>.bin.lzfse
```

This is a one-line change in `cacheURL`. Since a new root means a new cache file, switching
roots naturally falls back to "no cache found → offer a fresh scan", which is already handled
by `hasCachedResult` / `loadCachedResult`.

### 6. Cache format bump (v1 → v2)

`ScanCacheSerializer` must encode the new `NodeStatus` enum. Bump the serializer version
from `v1` to `v2`.

The loader rejects `v1` caches cleanly: on reading an unknown version byte, it returns
`.failed("Unsupported cache version")`, removes the stale file (as it already does for corrupt
caches in `DirectoryScanner.swift:444`), and falls back to a fresh scan. No migration — we are
still pre-release, there are no users with persistent v1 caches worth preserving.

### 7. UI treatment

| Status | Row appearance | Navigable | Deletable |
|---|---|---|---|
| `.normal` | As today | yes | yes |
| `.readOnly` | Lock icon + "read-only" badge, size shown normally | yes | no |
| `.skipped(reason)` | Grey name, size shown as "—", "Skipped: \(reason)" badge | no | no |
| `.inaccessible` | As today | no | no |

On the sunburst/treemap: `.readOnly` segments are drawn with a desaturated fill (concrete
palette decision deferred to implementation). `.skipped` segments do not contribute to the
chart at all since their size is 0.

The deletion error message in `DirectoryScanner.deleteNodes` changes from
`"Protected or not deletable"` to a status-aware string (e.g. `"Path is read-only"` or
`"Path is skipped by scan policy"`).

## Testing

### Unit — `ScanPolicyTests` (pure, no filesystem)

Drives `ScanPolicy.classify(_:)` with synthesized `URL` values. Injects a fake home directory
and boot volume name so tests are fully hermetic.

- Hard skip: `/System`, `/System/Library/X`, `/usr`, `/usr/bin/ls`, `/bin/sh`, `/Volumes/Ext` →
  `.skipped(...)`
- Hard skip exceptions: `/usr/local`, `/usr/local/bin/brew`, `/Volumes/Macintosh HD/Users` →
  `.scanned`
- Soft skip: `/Library`, `/Library/Frameworks`, `/Applications`, `/opt/homebrew` → `.readOnly`
- `~/Library` soft skip: `~/Library`, `~/Library/Preferences`, `~/Library/Mail`,
  `~/Library/Containers`, `~/Library/Keychains` → `.readOnly`
- `~/Library` whitelist: `~/Library/Caches`, `~/Library/Caches/com.apple.Safari`,
  `~/Library/Logs`, `~/Library/Developer/Xcode/DerivedData/MyApp`,
  `~/Library/Developer/Xcode/iOS DeviceSupport/16.0 (…)` → `.scanned`
- Whitelist boundary: `~/Library/Developer/Xcode/Archives` → `.readOnly` (NOT whitelisted)
- Normal paths: `~/Documents/foo.txt`, `~/Downloads`, `~/Projects` → `.scanned`

### Unit — `ScanPolicyEdgeTests`

- Trailing slash: `/System/` → `.skipped`
- Dot-segments: `/Users/x/./Library/./Caches` → `.scanned`
- Case: `/system`, `/SYSTEM` → `.skipped` (case-insensitive match)
- Empty path and `/` → `.scanned` (the root itself is never skipped)
- Symlink resolution: a URL whose `.standardized` resolves to `/System/...` → `.skipped`

### Integration — `DirectoryScannerTests`

A new test creates a sandbox directory `sandbox/{visible/fileA.txt, fake_system/large.bin}`
and injects a fake `ScanPolicy` that classifies `fake_system` as `.skipped`. Assertions:

1. `buildTree` emits a node for `fake_system` with `status == .skipped(...)`.
2. The emitted node has `size == 0` and **no children**, even though `large.bin` exists.
3. `visible/fileA.txt` is fully scanned and its size is reported.

Requires adding a `scanPolicy` parameter to `performScan` (default = production).

### Integration — `ScanCacheSerializerTests`

- **v2 round trip**: encode and decode a tree containing each of the 4 `NodeStatus` values,
  verify statuses survive the round trip.
- **v1 rejection**: hand-craft a byte stream starting with the old version marker, call
  `ScanCacheSerializer.read(from:)`, expect a thrown error.
- **`DirectoryScanner` fallback on v1**: write a v1 file at `cacheURL`, call
  `loadCachedResult`, expect the file to be removed and `lastError` to be
  `.cacheLoadFailed(...)` with an "unsupported version" reason.

## Files touched

**New:**
- `RicCleanMyMac/Services/ScanPolicy.swift`
- `RicCleanMyMacTests/ScanPolicyTests.swift`
- `RicCleanMyMacTests/ScanPolicyEdgeTests.swift`

**Modified:**
- `RicCleanMyMac/Models/FileNode.swift` — introduce `NodeStatus`, replace `accessDenied`
- `RicCleanMyMac/Services/DirectoryScanner.swift` — delete `protectedPrefixes` /
  `isPathProtected`, wire `ScanPolicy` into `buildTree`, per-root `cacheURL`, updated
  `isNodeDeletable` and delete-failure messages
- `RicCleanMyMac/Services/ScanCacheSerializer.swift` — bump to v2, encode/decode `NodeStatus`,
  reject v1 cleanly
- `RicCleanMyMac/Views/DiskAnalyzerView.swift` — root picker, route all scan calls through a
  helper, persist choice in `UserDefaults`, read-only/skipped row rendering
- Any other view that renders `FileNode` rows (file list / treemap) — adapt to `NodeStatus`
- `RicCleanMyMacTests/DirectoryScannerTests.swift` — new test case for skipped traversal
- `RicCleanMyMacTests/ScanCacheSerializerTests.swift` — v2 round trip + v1 rejection

## Risks

- **`/Volumes` boot firmlink detection.** On modern macOS the boot volume is firmlinked
  through `/Volumes/<boot name>`. Getting the name wrong means we either skip the user's own
  disk or fail to skip anything under `/Volumes`. Implementation will use
  `URLResourceKey.volumeURLKey` on `/` to resolve the name rather than hardcoding "Macintosh HD".
- **Case-insensitivity assumption.** The classifier assumes APFS/HFS+ default case-insensitive
  behavior. On case-sensitive volumes this is safe (still matches exact lowercase), but the
  logic needs to be spelled out in code so a future reader understands the choice.
- **`~/Library` whitelist drift.** Xcode changes its cache layout across versions. If Apple
  moves `DerivedData` or renames `DeviceSupport`, the whitelist silently stops matching. Add a
  unit test for each entry so at least the shape is regression-tested.
