# Disk Analyzer — Design Spec

## Overview

A new "Disk Analyzer" feature for RicCleanMyMac that lets users visually explore which folders and files consume the most disk space, navigate the filesystem hierarchy intuitively, and delete files/folders directly from the interface.

## Requirements

- Full disk navigation — user chooses any starting directory
- Navigable list sorted by size + sunburst chart as visual companion
- Breadcrumb-based drill-down navigation
- Deletion: multi-select bulk + single-item context menu
- User chooses Trash or permanent delete (default: Trash)
- Full recursive scan upfront (Approach A)
- No search/filter functionality in this iteration

## Architecture: Approach A — Upfront Full Scan

Scan the entire directory tree in background, building an in-memory tree. The UI navigates instantly because all data is preloaded. The sunburst chart is generated from the same tree.

Trade-offs:
- Initial scan may take 30-60s on large disks (mitigated by progress indicator)
- Memory for ~500K nodes is ~100-200MB (acceptable for a desktop app)
- Data can become stale if files change during the session (mitigated by re-scan button)

---

## Data Model

### FileNode

Core tree structure representing the filesystem. Implemented as a **class** (reference type) to support the weak `parent` reference and efficient in-place mutation during deletion.

```
FileNode (class, ObservableObject)
  id: UUID
  name: String                  — file/folder name
  path: String                  — absolute path
  size: Int64                   — bytes (files: actual size, folders: recursive sum of children)
  isDirectory: Bool
  children: [FileNode]?         — nil for files, sorted by size descending for directories
  parent: FileNode? (weak)      — enables breadcrumb traversal back to root
  accessDenied: Bool            — true if directory could not be read (permissions)
```

### DirectoryScanResult

Wraps the complete scan output.

```
DirectoryScanResult
  root: FileNode
  totalSize: Int64
  totalFiles: Int
  totalDirectories: Int
  scanDuration: TimeInterval
```

---

## Service: DirectoryScanner

A new `ObservableObject` service, independent from the existing `FileScanner` and `CleanupService`.

### Interface

```
DirectoryScanner: ObservableObject
  @Published isScanning: Bool
  @Published progress: ScanProgress   — { filesScanned: Int, currentPath: String }

  func scan(rootPath: String) async -> DirectoryScanResult
  func cancel()
```

### Scanning strategy

- Uses `FileManager.enumerator(at:includingPropertiesForKeys:)` with prefetch of `.fileSizeKey` and `.isDirectoryKey`
- Runs on `Task.detached(priority: .userInitiated)`
- Progress updates emitted every ~1000 files to minimize overhead
- Supports cancellation via `Task.isCancelled`
- Directories without read permissions are skipped silently with `accessDenied: true` on the node

### Size calculation

Bottom-up aggregation: leaf file sizes bubble up to parent directories after the full enumeration completes.

---

## UI: Navigation View

The main view is `DiskAnalyzerView`, split into list (left, ~60%) and sunburst chart (right, ~40%).

### Toolbar (top)

- **"Choose folder..." button** — opens `NSOpenPanel` for directory selection
- **"Re-scan" button** — re-scans the current root
- **Trash/Permanent toggle** — segmented picker, default: Trash

### Breadcrumb bar

- Clickable path segments: `~ > Library > Caches > com.apple.Safari`
- Each segment is a button that navigates to that level
- Current segment is bold and non-clickable
- Overflow: middle segments collapse into `...` with dropdown menu

### File list

Each row displays:
- Checkbox (left) for multi-select
- Icon: folder or file type icon
- Name
- Formatted size (e.g., "2.3 GB")
- Relative progress bar (percentage of parent's size)
- Chevron `>` for directories

Interactions:
- Click on directory row → drill-down (updates breadcrumb + list)
- Right-click on any row → context menu with "Delete"
- Checkbox toggle → adds/removes from selection

### Bottom bar (sticky)

- Shows when items are selected: "3 items selected (4.7 GB)"
- "Delete selected" button
- Hidden when no selection

### Sorting

Fixed: size descending (largest first). No user-configurable sort in this iteration.

---

## UI: Sunburst Chart

### Layout

- Positioned in the right panel (~40% width)
- Circular chart centered in the panel

### Structure

- **Center**: current directory name + total size
- **First ring**: direct children of current directory
- **Subsequent rings**: deeper levels (max 3 rings for readability)
- Arc width proportional to size relative to siblings
- Distinct colors for first-ring segments, lighter shades for inner levels

### Interactivity

- **Hover** on arc → tooltip: name + size + percentage
- **Click** on directory arc → drill-down (synchronized with list)
- Sunburst and list are always in sync: navigating one updates the other

### Rendering limits

- Items under 1% of total size are aggregated into an "Other" arc
- Maximum 3 visible depth rings
- If current directory contains only files (no subdirectories), shows a single ring

### Implementation

SwiftUI `Canvas` or `Path` with geometrically calculated arcs (start/end angles per segment). No external libraries.

---

## Deletion

### Single-item (context menu)

- Right-click → "Delete"
- Inline confirmation: "Delete `FileName` (2.3 GB)? [Cancel] [Delete]"
- Executes and updates tree in-place

### Multi-select (bulk)

- Checkboxes on rows for selection
- Bottom bar shows count + total size + "Delete selected" button
- Opens `ConfirmationDialog` sheet listing all items with sizes
- User confirms to proceed

### Trash vs Permanent

- Toggle in toolbar: `Trash | Permanent`
- Default: Trash
- When set to Permanent: confirm button turns red, explicit warning that the operation is irreversible
- Implementation:
  - Trash: `FileManager.trashItem(at:resultingItemURL:)`
  - Permanent: `FileManager.removeItem(at:)`

### Post-deletion update

- Deleted nodes are removed from the in-memory tree
- Parent node sizes are recalculated up to the root
- No re-scan needed — in-place model update
- Sunburst updates accordingly

### Safety

- Cannot delete the scan root directory
- System-protected paths blocked: `/System`, `/usr`, `/bin`, `/sbin`, `/Library` (system-level), `/private`
- Nodes with `accessDenied: true` do not show delete option

---

## Integration in Existing App

### New sidebar entry

- **"Disk Analyzer"** added to `MainView` sidebar in `NavigationSplitView`
- Positioned between "Dashboard" and "Cleanup"
- SF Symbol icon: `internaldrive`

### New files to create

| File | Role |
|------|------|
| `Models/FileNode.swift` | Filesystem tree model |
| `Models/DirectoryScanResult.swift` | Scan result wrapper |
| `Services/DirectoryScanner.swift` | Recursive scanning service |
| `Views/DiskAnalyzerView.swift` | Container view (list + sunburst) |
| `Views/BreadcrumbBar.swift` | Clickable breadcrumb navigation |
| `Views/FileListView.swift` | Navigable list with checkboxes and context menu |
| `Views/SunburstChartView.swift` | Interactive sunburst chart |
| `Views/DeleteConfirmationSheet.swift` | Deletion confirmation sheet |

### Existing files to modify

| File | Change |
|------|--------|
| `Views/MainView.swift` | Add "Disk Analyzer" entry in sidebar |
| `App/RicCleanMyMacApp.swift` | Instantiate `DirectoryScanner` as `@StateObject` and inject into environment |

### No changes to

`CleanupService`, `FileScanner`, `DiskAnalyzer` — this feature is fully independent from the existing cleanup flow.
