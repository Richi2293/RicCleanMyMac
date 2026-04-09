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

            if scanner.isLoadingCache {
                loadingCacheView
            } else if scanner.isScanning {
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
        .sheet(isPresented: $showConfirmation) {
            bulkDeleteSheet
        }
        .sheet(isPresented: $showSingleDeleteConfirmation) {
            singleDeleteSheet
        }
        .alert(
            scanner.lastError?.title ?? "",
            isPresented: Binding(
                get: { scanner.lastError != nil },
                set: { if !$0 { scanner.lastError = nil } }
            ),
            presenting: scanner.lastError
        ) { _ in
            Button("OK", role: .cancel) { scanner.lastError = nil }
        } message: { error in
            Text(error.message)
        }
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: 12) {
            if scanner.scanResult != nil {
                Button {
                    scanner.scan(rootPath: "/")
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
                    Image(systemName: "clock")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("Scanned: \(result.formattedScanDate)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("(\(result.totalFiles) files, \(result.totalDirectories) folders, \(result.formattedDuration))")
                        .font(.caption)
                        .foregroundColor(.secondary.opacity(0.7))
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

    // MARK: - Loading states

    private var loadingCacheView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.2)
            Text("Loading previous scan...")
                .font(.headline)
            Text("This will only take a moment")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

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
            Text("No scan results available.")
                .font(.subheadline)
                .foregroundColor(.secondary)
            Button {
                scanner.scan(rootPath: "/")
            } label: {
                Label("Scan Now", systemImage: "magnifyingglass")
            }
            .buttonStyle(.borderedProminent)
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
            if result.failedCount > 0 {
                Text("\(result.successCount) deleted, \(result.failedCount) failed — freed \(ByteCountFormatter.string(fromByteCount: result.freedSize, countStyle: .file))")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                Text("Freed \(ByteCountFormatter.string(fromByteCount: result.freedSize, countStyle: .file))")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

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
