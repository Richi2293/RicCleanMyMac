import SwiftUI

// MARK: - Confirmation Sheet

struct CleanupConfirmationSheet: View {
    let items: [CleanupItem]
    let totalSize: Int64
    let onConfirm: () -> Void
    let onCancel: () -> Void

    private let largeItemThreshold: Int64 = 500_000_000 // 500 MB

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            itemList
            Divider()
            footer
        }
        .frame(minWidth: 440, minHeight: 340)
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "trash.circle.fill")
                .font(.largeTitle)
                .foregroundColor(.red)
            VStack(alignment: .leading, spacing: 4) {
                Text("Confirm Cleanup")
                    .font(.headline)
                Text("Permanently delete \(items.count) item(s) and free \(ByteCountFormatter.string(fromByteCount: totalSize)).")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Text("This action cannot be undone.")
                    .font(.caption)
                    .foregroundColor(.orange)
            }
        }
        .padding()
    }

    private var itemList: some View {
        List(items) { item in
            HStack(spacing: 10) {
                Image(systemName: item.type.icon)
                    .foregroundColor(.secondary)
                    .frame(width: 20)

                VStack(alignment: .leading, spacing: 2) {
                    Text(item.name)
                        .font(.subheadline)
                    Text(item.path)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                HStack(spacing: 4) {
                    if item.size >= largeItemThreshold {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                    Text(item.formattedSize)
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(item.size >= largeItemThreshold ? .orange : .secondary)
                }
            }
        }
        .listStyle(PlainListStyle())
    }

    private var footer: some View {
        HStack {
            Spacer()
            Button("Cancel", action: onCancel)
                .keyboardShortcut(.escape)
            Button(role: .destructive, action: onConfirm) {
                Text("Delete \(items.count) Item(s)")
            }
            .keyboardShortcut(.return)
            .buttonStyle(.borderedProminent)
            .tint(.red)
        }
        .padding()
    }
}

// MARK: - View Modifier

struct CleanupConfirmationModifier: ViewModifier {
    @Binding var isPresented: Bool
    let items: [CleanupItem]
    let totalSize: Int64
    let onConfirm: () -> Void

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $isPresented) {
                CleanupConfirmationSheet(
                    items: items,
                    totalSize: totalSize,
                    onConfirm: {
                        onConfirm()
                        isPresented = false
                    },
                    onCancel: {
                        isPresented = false
                    }
                )
            }
    }
}

extension View {
    func cleanupConfirmation(
        isPresented: Binding<Bool>,
        items: [CleanupItem],
        totalSize: Int64,
        onConfirm: @escaping () -> Void
    ) -> some View {
        modifier(CleanupConfirmationModifier(
            isPresented: isPresented,
            items: items,
            totalSize: totalSize,
            onConfirm: onConfirm
        ))
    }
}
