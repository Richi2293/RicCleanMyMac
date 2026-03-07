import SwiftUI

struct CleanupView: View {
    @EnvironmentObject var cleanupService: CleanupService
    @State private var selectedItems: Set<UUID> = []
    @State private var showConfirmation = false
    @State private var isCleaning = false
    @State private var showError = false

    var selectedCleanupItems: [CleanupItem] {
        cleanupService.cleanupItems.filter { selectedItems.contains($0.id) }
    }

    var selectedTotalSize: Int64 {
        selectedCleanupItems.reduce(Int64(0)) { $0 + $1.size }
    }

    var body: some View {
        VStack(spacing: 0) {
            if cleanupService.isScanning {
                ProgressView("Scanning...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if cleanupService.cleanupItems.isEmpty {
                EmptyStateView(onScan: { Task { await cleanupService.scan() } })
            } else {
                // Toolbar
                HStack {
                    Text("\(cleanupService.cleanupItems.count) items found")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Spacer()
                    Button("Scan Again") {
                        Task { await cleanupService.scan() }
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 8)

                Divider()

                // List of cleanup items
                List(cleanupService.cleanupItems) { item in
                    CleanupItemRow(
                        item: item,
                        isSelected: selectedItems.contains(item.id)
                    ) {
                        if selectedItems.contains(item.id) {
                            selectedItems.remove(item.id)
                        } else {
                            selectedItems.insert(item.id)
                        }
                    }
                }
                .listStyle(PlainListStyle())

                // Bottom toolbar
                VStack(spacing: 12) {
                    Divider()

                    HStack {
                        if !selectedItems.isEmpty {
                            Text("\(selectedItems.count) item(s) selected — \(ByteCountFormatter.string(fromByteCount: selectedTotalSize))")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        } else {
                            Text("Select items to clean")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }

                        Spacer()

                        Button("Select All") {
                            selectedItems = Set(cleanupService.cleanupItems.map(\.id))
                        }
                        .disabled(selectedItems.count == cleanupService.cleanupItems.count)

                        Button("Deselect All") {
                            selectedItems.removeAll()
                        }
                        .disabled(selectedItems.isEmpty)

                        Button(action: {
                            showConfirmation = true
                        }) {
                            HStack {
                                if isCleaning {
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle())
                                        .scaleEffect(0.8)
                                } else {
                                    Image(systemName: "trash.fill")
                                }
                                Text(isCleaning ? "Cleaning..." : "Clean Selected")
                            }
                            .padding(.horizontal, 20)
                            .padding(.vertical, 8)
                        }
                        .disabled(selectedItems.isEmpty || isCleaning)
                        .buttonStyle(.borderedProminent)
                    }
                    .padding()
                }
                .background(Color(NSColor.windowBackgroundColor))
            }
        }
        .cleanupConfirmation(
            isPresented: $showConfirmation,
            items: selectedCleanupItems,
            totalSize: selectedTotalSize
        ) {
            Task {
                await performCleanup()
            }
        }
        .alert("Cleanup Failed", isPresented: $showError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Some items could not be cleaned because they are outside the allowed directories.")
        }
    }

    private func performCleanup() async {
        isCleaning = true

        let itemsToClean = selectedCleanupItems
        let result = await cleanupService.cleanup(items: itemsToClean)

        await MainActor.run {
            isCleaning = false

            if result != nil {
                selectedItems.removeAll()
            } else {
                showError = true
            }
        }
    }
}

struct CleanupItemRow: View {
    let item: CleanupItem
    let isSelected: Bool
    let onToggle: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onToggle) {
                Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                    .foregroundColor(isSelected ? .accentColor : .secondary)
            }
            .buttonStyle(PlainButtonStyle())

            Image(systemName: item.type.icon)
                .foregroundColor(.secondary)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 4) {
                Text(item.name)
                    .font(.headline)

                Text(item.path)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Text(item.formattedSize)
                .font(.subheadline)
                .fontWeight(.medium)
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .onTapGesture {
            onToggle()
        }
    }
}

struct EmptyStateView: View {
    let onScan: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 60))
                .foregroundColor(.secondary)

            Text("No Items Found")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Scan your system to find files that can be safely removed.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            Button(action: onScan) {
                Label("Scan Now", systemImage: "magnifyingglass")
                    .padding(.horizontal, 20)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
