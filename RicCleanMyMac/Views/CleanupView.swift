import SwiftUI

struct CleanupView: View {
    @EnvironmentObject var cleanupService: CleanupService
    @State private var selectedItems: Set<UUID> = []
    @State private var showConfirmation = false
    @State private var isCleaning = false
    
    var selectedCleanupItems: [CleanupItem] {
        cleanupService.cleanupItems.filter { selectedItems.contains($0.id) }
    }
    
    var selectedTotalSize: Int64 {
        selectedCleanupItems.reduce(Int64(0)) { $0 + $1.size }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            if cleanupService.cleanupItems.isEmpty {
                EmptyStateView()
            } else {
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
                            Text("\(selectedItems.count) item(s) selected - \(ByteCountFormatter.string(fromByteCount: selectedTotalSize))")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        } else {
                            Text("Select items to clean")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        Button(action: {
                            selectedItems.removeAll()
                        }) {
                            Text("Deselect All")
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
                // Show error if validation failed
                // In a real app, you might want to show an alert here
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
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 60))
                .foregroundColor(.secondary)
            
            Text("No Items Found")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("Click 'Scan for Cleanup' in the Dashboard to find items that can be cleaned")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

