import SwiftUI

struct DiskAnalyzerConfirmationSheet: View {
    let nodes: [FileNode]
    let totalSize: Int64
    let deleteMode: DeleteMode
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
        .frame(minWidth: 480, minHeight: 360)
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: deleteMode == .permanent ? "xmark.bin.fill" : "trash.circle.fill")
                .font(.largeTitle)
                .foregroundColor(.red)

            VStack(alignment: .leading, spacing: 4) {
                Text("Confirm Deletion")
                    .font(.headline)

                Text("\(deleteMode == .trash ? "Move" : "Permanently delete") \(nodes.count) item(s) (\(ByteCountFormatter.string(fromByteCount: totalSize, countStyle: .file)))")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                if deleteMode == .permanent {
                    Text("This action cannot be undone.")
                        .font(.caption)
                        .foregroundColor(.red)
                        .fontWeight(.medium)
                } else {
                    Text("Items will be moved to the Trash.")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
            }
        }
        .padding()
    }

    private var itemList: some View {
        List(nodes) { node in
            HStack(spacing: 10) {
                Image(systemName: node.icon)
                    .foregroundColor(node.isDirectory ? .accentColor : .secondary)
                    .frame(width: 20)

                VStack(alignment: .leading, spacing: 2) {
                    Text(node.name)
                        .font(.subheadline)
                    Text(node.path)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                HStack(spacing: 4) {
                    if node.size >= largeItemThreshold {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                    Text(node.formattedSize)
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(node.size >= largeItemThreshold ? .orange : .secondary)
                }
            }
        }
        .listStyle(.plain)
    }

    private var footer: some View {
        HStack {
            Spacer()
            Button("Cancel", action: onCancel)
                .keyboardShortcut(.escape)

            Button(role: .destructive, action: onConfirm) {
                Text(deleteMode == .trash
                     ? "Move to Trash (\(nodes.count))"
                     : "Delete Permanently (\(nodes.count))")
            }
            .keyboardShortcut(.return)
            .buttonStyle(.borderedProminent)
            .tint(.red)
        }
        .padding()
    }
}
