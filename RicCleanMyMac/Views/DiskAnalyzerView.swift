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

            Text("\(selectedCount) item(s) selected — \(ByteCountFormatter.string(fromByteCount: selectedSize, countStyle: .file))")
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
            Text("Freed \(ByteCountFormatter.string(fromByteCount: result.freedSize, countStyle: .file))")
                .font(.caption)
                .foregroundColor(.secondary)

            Button {
                withAnimation { deletionResult = nil }
            } label: {
                Image(systemName: "xmark")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
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
