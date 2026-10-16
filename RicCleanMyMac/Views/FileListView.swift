import SwiftUI

struct FileListView: View {
    let children: [FileNode]
    @Binding var selectedItems: Set<ObjectIdentifier>
    let isDeletable: (FileNode) -> Bool
    /// While a deletion runs, no other deletion can be started from the list.
    let isDeletionRunning: Bool
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
                    if isDeletable(node) && !isDeletionRunning {
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
            leadingControl

            Image(systemName: node.icon)
                .foregroundColor(node.isDirectory ? .accentColor : .secondary)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(node.name)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .lineLimit(1)
                        .foregroundColor(nameColor)
                    statusBadge
                }

                if node.isDirectory, let childCount = node.children?.count {
                    Text("\(childCount) item(s)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            sizeBar

            Text(sizeText)
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
        .accessibilityAction(named: "Open") {
            if node.isDirectory, !isSkipped { onNavigate() }
        }
        .onTapGesture {
            if case .skipped = node.status {
                return
            }
            if node.isDirectory {
                onNavigate()
            } else if isDeletable {
                onToggleSelection()
            }
        }
    }

    @ViewBuilder
    private var leadingControl: some View {
        if isDeletable {
            Button(action: onToggleSelection) {
                Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                    .foregroundColor(isSelected ? .accentColor : .secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Select \(node.name)")
            .accessibilityAddTraits(isSelected ? .isSelected : [])
        } else {
            switch node.status {
            case .readOnly:
                Image(systemName: "lock.fill")
                    .foregroundColor(.secondary.opacity(0.6))
                    .frame(width: 16)
                    .help("Read-only: protected by scan policy")
            case .skipped:
                Image(systemName: "minus.circle")
                    .foregroundColor(.secondary.opacity(0.5))
                    .frame(width: 16)
                    .help("Skipped: not scanned")
            case .inaccessible:
                Image(systemName: "exclamationmark.triangle")
                    .foregroundColor(.orange.opacity(0.7))
                    .frame(width: 16)
                    .help("Could not be read")
            case .normal:
                // A `.normal` node that is not deletable: a folder holding
                // protected content, the home folder, or a folder such as
                // `~/Library/Caches` that must stay while its contents go.
                Image(systemName: "lock")
                    .foregroundColor(.secondary.opacity(0.6))
                    .frame(width: 16)
                    .help("Protected: this folder cannot be deleted")
            }
        }
    }

    private var isSkipped: Bool {
        if case .skipped = node.status { return true }
        return false
    }

    private var nameColor: Color {
        switch node.status {
        case .skipped, .inaccessible: return .secondary
        default: return .primary
        }
    }

    @ViewBuilder
    private var statusBadge: some View {
        switch node.status {
        case .readOnly:
            Text("read-only")
                .font(.caption2)
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(Color.secondary.opacity(0.12))
                .cornerRadius(3)
                .foregroundColor(.secondary)
        case .skipped(let reason):
            Text("skipped: \(reason.lowercased())")
                .font(.caption2)
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(Color.secondary.opacity(0.12))
                .cornerRadius(3)
                .foregroundColor(.secondary)
        default:
            EmptyView()
        }
    }

    private var sizeText: String {
        if case .skipped = node.status { return "-" }
        return node.formattedSize
    }

    private static let sizeBarWidth: CGFloat = 60

    private var sizeBar: some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 2)
                .fill(Color.secondary.opacity(0.15))

            RoundedRectangle(cornerRadius: 2)
                .fill(barColor)
                .frame(width: Self.sizeBarWidth * CGFloat(node.relativeSize))
        }
        .frame(width: Self.sizeBarWidth, height: 6)
        .accessibilityHidden(true)
    }

    private var barColor: Color {
        switch node.relativeSize {
        case 0.5...: return .red.opacity(0.7)
        case 0.25...: return .orange.opacity(0.7)
        default: return .accentColor.opacity(0.7)
        }
    }
}
