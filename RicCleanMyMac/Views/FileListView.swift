import SwiftUI

struct FileListView: View {
    let children: [FileNode]
    @Binding var selectedItems: Set<ObjectIdentifier>
    let isDeletable: (FileNode) -> Bool
    let onNavigate: (FileNode) -> Void
    let onDelete: (FileNode) -> Void

    var body: some View {
        List {
            ForEach(children) { node in
                FileListRow(
                    node: node,
                    isSelected: selectedItems.contains(node.id),
                    isDeletable: isDeletable(node),
                    onToggleSelection: { toggleSelection(node) },
                    onNavigate: { onNavigate(node) }
                )
                .contextMenu {
                    if isDeletable(node) {
                        Button(role: .destructive) {
                            onDelete(node)
                        } label: {
                            Label("Delete \"\(node.name)\"", systemImage: "trash")
                        }
                    }

                    if node.isDirectory {
                        Button {
                            onNavigate(node)
                        } label: {
                            Label("Open", systemImage: "folder")
                        }
                    }

                    Divider()

                    Button {
                        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: node.path)
                    } label: {
                        Label("Show in Finder", systemImage: "magnifyingglass")
                    }
                }
            }
        }
        .listStyle(.plain)
    }

    private func toggleSelection(_ node: FileNode) {
        if selectedItems.contains(node.id) {
            selectedItems.remove(node.id)
        } else {
            selectedItems.insert(node.id)
        }
    }
}

// MARK: - Row

struct FileListRow: View {
    let node: FileNode
    let isSelected: Bool
    let isDeletable: Bool
    let onToggleSelection: () -> Void
    let onNavigate: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            if isDeletable {
                Button(action: onToggleSelection) {
                    Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                        .foregroundColor(isSelected ? .accentColor : .secondary)
                }
                .buttonStyle(.plain)
            } else {
                Image(systemName: "lock.fill")
                    .foregroundColor(.secondary.opacity(0.5))
                    .frame(width: 16)
            }

            Image(systemName: node.icon)
                .foregroundColor(node.isDirectory ? .accentColor : .secondary)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(node.name)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(1)

                if node.isDirectory, let childCount = node.children?.count {
                    Text("\(childCount) item(s)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            sizeBar
                .frame(width: 60)

            Text(node.formattedSize)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(.secondary)
                .frame(width: 70, alignment: .trailing)

            if node.isDirectory {
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture {
            if node.isDirectory {
                onNavigate()
            } else if isDeletable {
                onToggleSelection()
            }
        }
    }

    private var sizeBar: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.secondary.opacity(0.15))
                    .frame(height: 6)

                RoundedRectangle(cornerRadius: 2)
                    .fill(barColor)
                    .frame(width: geo.size.width * CGFloat(node.relativeSize), height: 6)
            }
        }
        .frame(height: 6)
    }

    private var barColor: Color {
        switch node.relativeSize {
        case 0.5...: return .red.opacity(0.7)
        case 0.25...: return .orange.opacity(0.7)
        default: return .accentColor.opacity(0.7)
        }
    }
}
