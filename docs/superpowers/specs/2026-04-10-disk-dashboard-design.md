# Disk Dashboard Header — Design Spec

## Problem

The disk analyzer currently drops the user straight into a file tree explorer
after scanning. There is no at-a-glance summary of disk usage, no guidance on
where space can be recovered, and no categorisation of space consumers. Users
must explore manually and decide on their own what is safe to delete.

## Solution

Add a collapsible **dashboard header** to `DiskAnalyzerView` that provides two
layers of information:

1. **Disk gauge** (instant) — overall disk usage with a circular gauge.
2. **Smart categories** (post-scan) — aggregated sizes for well-known
   expendable directories (caches, logs, temp, downloads) and a "large files"
   bucket, each linking into the existing tree explorer.

The header appears immediately on open (disk stats are a fast FS call), and
enriches itself once the scan completes. The user can collapse it to maximise
exploration space.

## User flow

1. **Open disk analyzer** → header appears with disk gauge (level 1).
   Scan or cache load starts in parallel.
2. **Scan/cache done** → smart categories row appears (level 2).
   Tree explorer (list + sunburst) renders below as today.
3. **Explore** → user can collapse the header via chevron. Clicking a smart
   category navigates to the corresponding node in the tree.

## Header structure

### Level 1 — Disk gauge

Visible as soon as `DiskAnalyzer.getDiskSpace()` returns (< 1 s).

- Circular gauge showing used percentage.
- Colour: green (< 60 %), yellow (60–80 %), red (> 80 %).
- Text: used / total, available space — formatted via `ByteCountFormatter`.
- Chevron to collapse/expand level 2.
- If `getDiskSpace()` fails: grey placeholder text, no blocking.

### Level 2 — Smart categories

Visible after scan result is available.

| Category   | What it captures                         | Detection rule                              |
|------------|------------------------------------------|---------------------------------------------|
| Cache      | `~/Library/Caches`, `.cache` dirs        | Path contains `/Caches` or `/.cache`        |
| Log        | `~/Library/Logs`, `.log` files           | Path contains `/Logs` or extension `.log`   |
| Temp       | `/tmp`, temporary directories            | Path contains `/tmp` or `/Temporary`        |
| Downloads  | `~/Downloads`                            | Exact path match `~/Downloads`              |
| Large files| Any single file > 1 GB                   | `size > 1 GB && isDirectory == false`       |

Each card shows: SF Symbol icon, category name, aggregated size.

**Click behaviour:**

- Cache, Log, Temp, Downloads → navigate to the corresponding directory node
  in the tree (same as clicking in the sunburst).
- Large files → open a popover/sheet listing files > 1 GB sorted by size.
  Each row is clickable and navigates to the file in the tree.

### Collapsed state

When collapsed, the header shrinks to a single compact row:

```
● 76% — 120 GB available
```

Collapse state is persisted via `@AppStorage`.

## State matrix

| App state                              | Level 1 (gauge)        | Level 2 (categories)        | Below header           |
|----------------------------------------|------------------------|-----------------------------|------------------------|
| No data yet                            | Small spinner          | Hidden                      | Empty state            |
| `getDiskSpace()` done, no scan         | Gauge with data        | "Start scan for details"    | Empty state            |
| `getDiskSpace()` done, scan in progress| Gauge with data        | Spinner + "Analysing…"      | Scanning view          |
| Everything complete                    | Gauge with data        | Clickable smart categories  | List + sunburst        |

## Architecture

### New files

| File                      | Kind  | Responsibility                                                        |
|---------------------------|-------|-----------------------------------------------------------------------|
| `SmartCategory.swift`     | Model | Struct: `name`, `icon` (SF Symbol), `totalSize` (Int64), `nodeIDs` ([ObjectIdentifier]) |
| `DiskDashboardHeader.swift`| View | Collapsible header with gauge + smart categories                      |

### Modified files

| File                      | Change                                                                                   |
|---------------------------|------------------------------------------------------------------------------------------|
| `DiskAnalyzerView.swift`  | Insert `DiskDashboardHeader` above existing content. Call `getDiskSpace()` on appear.     |
| `DirectoryScanner.swift`  | Add `@Published diskSpace: DiskSpace?` and `@Published smartCategories: [SmartCategory]`. Add method to compute categories from scan result. |
| `FileNode.swift`          | Add `extractSmartCategories() -> [SmartCategory]` — single-pass tree traversal.           |

### Unchanged files

- `SunburstChartView`, `FileListView`, `BreadcrumbBar` — untouched.
- `DiskAnalyzer.swift` — consumed, not modified.
- `SpaceUsageView` — stays in its own area.

### Data flow

```
onAppear
  ├── DiskAnalyzer.getDiskSpace()
  │     └── scanner.diskSpace ──► DiskDashboardHeader (level 1)
  └── startOrLoad(for:)
        └── scan / cache ──► scanResult
                                └── extractSmartCategories()
                                      └── scanner.smartCategories
                                            └── DiskDashboardHeader (level 2)
```

`DirectoryScanner` orchestrates everything: it already owns the scan lifecycle,
so it naturally owns `diskSpace` and `smartCategories` too.

## Error handling

- `getDiskSpace()` failure → level 1 shows grey "Disk space unavailable" text.
  No blocking.
- Scan failure → level 2 stays empty; error handled via existing alert
  mechanism. No new error paths.

## Design principles

- **Informational, not destructive.** Smart categories show size and link to
  the tree. They do not offer one-click delete — users navigate, review, then
  decide.
- **No extra I/O.** Categories are computed from the in-memory `FileNode` tree
  after scan. The only new I/O is the single `getDiskSpace()` call.
- **Progressive disclosure.** Gauge appears instantly; categories after scan;
  full explorer below. Each layer adds depth without blocking.
- **Minimal blast radius.** Two new files, three modified files, no layout
  changes to existing views.
