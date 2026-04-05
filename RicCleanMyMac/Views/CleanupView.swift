import SwiftUI

struct CleanupView: View {
    @EnvironmentObject var cleanupService: CleanupService
    @State private var selectedItems: Set<String> = []
    @State private var showConfirmation = false
    @State private var isCleaning = false
    @State private var showError = false
    @State private var cleanupResult: CleanupResult? = nil
    @State private var sortOrder: SortOrder = .size
    @State private var filterType: CleanupType? = nil

    enum SortOrder: String, CaseIterable {
        case size = "Size"
        case name = "Name"
        case type = "Type"
    }

    var displayedItems: [CleanupItem] {
        var items = cleanupService.cleanupItems
        if let filter = filterType {
            items = items.filter { $0.type == filter }
        }
        switch sortOrder {
        case .size: return items.sorted { $0.size > $1.size }
        case .name: return items.sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
        case .type: return items.sorted { $0.type.rawValue < $1.type.rawValue }
        }
    }

    var selectedCleanupItems: [CleanupItem] {
        cleanupService.cleanupItems.filter { selectedItems.contains($0.id) }
    }

    var selectedTotalSize: Int64 {
        selectedCleanupItems.reduce(Int64(0)) { $0 + $1.size }
    }

    var body: some View {
        VStack(spacing: 0) {
            if cleanupService.isScanning {
                scanningView
            } else if cleanupService.cleanupItems.isEmpty {
                EmptyStateView(onScan: { Task { await cleanupService.scan() } })
            } else {
                if let result = cleanupResult {
                    cleanupBannerView(result)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }

                toolbarView

                typeSummaryView

                Divider()

                List(displayedItems) { item in
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

                bottomToolbar
            }
        }
        .animation(.easeInOut(duration: 0.25), value: cleanupResult != nil)
        .cleanupConfirmation(
            isPresented: $showConfirmation,
            items: selectedCleanupItems,
            totalSize: selectedTotalSize
        ) {
            Task { await performCleanup() }
        }
    }

    // MARK: - Subviews

    private var scanningView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.2)
            Text(cleanupService.scanProgressLabel.isEmpty ? "Scanning..." : cleanupService.scanProgressLabel)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .animation(.default, value: cleanupService.scanProgressLabel)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func cleanupBannerView(_ result: CleanupResult) -> some View {
        let bannerColor: Color = result.isFullSuccess ? .green : (result.isFullFailure ? .red : .orange)
        let icon = result.isFullSuccess ? "checkmark.circle.fill" : (result.isFullFailure ? "xmark.circle.fill" : "exclamationmark.triangle.fill")

        return HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundColor(bannerColor)

            VStack(alignment: .leading, spacing: 2) {
                if result.isFullSuccess {
                    Text("Cleaned \(result.successCount) item(s) — freed \(ByteCountFormatter.string(fromByteCount: result.freedSize))")
                        .font(.subheadline)
                        .fontWeight(.medium)
                } else if result.isFullFailure {
                    Text("Cleanup failed — \(result.failedCount) item(s) could not be deleted")
                        .font(.subheadline)
                        .fontWeight(.medium)
                } else {
                    Text("Cleaned \(result.successCount) of \(result.totalCount) item(s) — freed \(ByteCountFormatter.string(fromByteCount: result.freedSize))")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Text("\(result.failedCount) item(s) could not be deleted")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            Button {
                withAnimation { cleanupResult = nil }
            } label: {
                Image(systemName: "xmark")
                    .foregroundColor(.secondary)
            }
            .buttonStyle(PlainButtonStyle())
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .background(bannerColor.opacity(0.12))
    }

    private var toolbarView: some View {
        HStack(spacing: 8) {
            Text("\(cleanupService.cleanupItems.count) items found")
                .font(.subheadline)
                .foregroundColor(.secondary)
            Spacer()
            Picker("Sort by", selection: $sortOrder) {
                ForEach(SortOrder.allCases, id: \.self) { order in
                    Text(order.rawValue).tag(order)
                }
            }
            .pickerStyle(.menu)
            .frame(width: 110)

            Picker("Filter", selection: $filterType) {
                Text("All Types").tag(Optional<CleanupType>.none)
                ForEach(CleanupType.allCases, id: \.self) { type in
                    Label(type.displayName, systemImage: type.icon).tag(Optional(type))
                }
            }
            .pickerStyle(.menu)
            .frame(width: 130)

            Button("Scan Again") {
                withAnimation { cleanupResult = nil }
                Task { await cleanupService.scan() }
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var typeSummaryView: some View {
        let typeGroups = Dictionary(grouping: cleanupService.cleanupItems, by: \.type)
        let activeTypes = CleanupType.allCases.filter { typeGroups[$0] != nil }
        if !activeTypes.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(activeTypes, id: \.self) { type in
                        let items = typeGroups[type]!
                        let size = items.reduce(Int64(0)) { $0 + $1.size }
                        typePill(type: type, size: size)
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
            }
            Divider()
        }
    }

    private func typePill(type: CleanupType, size: Int64) -> some View {
        let isActive = filterType == type
        return Button {
            withAnimation { filterType = isActive ? nil : type }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: type.icon)
                    .font(.caption)
                VStack(alignment: .leading, spacing: 1) {
                    Text(type.displayName)
                        .font(.caption)
                    Text(ByteCountFormatter.string(fromByteCount: size))
                        .font(.caption2)
                        .fontWeight(.medium)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(isActive ? Color.accentColor.opacity(0.15) : Color(NSColor.controlBackgroundColor))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(isActive ? Color.accentColor.opacity(0.5) : Color.clear, lineWidth: 1)
            )
            .cornerRadius(8)
        }
        .buttonStyle(PlainButtonStyle())
    }

    private var bottomToolbar: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 8) {
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
                    selectedItems = Set(displayedItems.map(\.id))
                }
                .disabled(displayedItems.allSatisfy { selectedItems.contains($0.id) })

                Button("Deselect All") {
                    selectedItems.removeAll()
                }
                .disabled(selectedItems.isEmpty)

                Button(action: { showConfirmation = true }) {
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

    // MARK: - Actions

    private func performCleanup() async {
        isCleaning = true
        let itemsToClean = selectedCleanupItems
        let result = await cleanupService.cleanup(items: itemsToClean)

        await MainActor.run {
            isCleaning = false
            selectedItems.removeAll()
            withAnimation {
                cleanupResult = result
            }
        }
    }
}

// MARK: - Supporting views

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
