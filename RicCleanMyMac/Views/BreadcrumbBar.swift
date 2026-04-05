import SwiftUI

struct BreadcrumbBar: View {
    let path: [FileNode]
    let onNavigate: (FileNode) -> Void

    private let maxVisibleSegments = 5

    var body: some View {
        HStack(spacing: 2) {
            if path.count <= maxVisibleSegments {
                fullBreadcrumb
            } else {
                collapsedBreadcrumb
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color(NSColor.controlBackgroundColor))
    }

    @ViewBuilder
    private var fullBreadcrumb: some View {
        ForEach(Array(path.enumerated()), id: \.element.id) { index, node in
            if index > 0 {
                chevronSeparator
            }
            breadcrumbSegment(node: node, isLast: index == path.count - 1)
        }
    }

    @ViewBuilder
    private var collapsedBreadcrumb: some View {
        breadcrumbSegment(node: path[0], isLast: false)
        chevronSeparator

        Menu {
            ForEach(Array(path[1..<(path.count - 2)].enumerated()), id: \.element.id) { _, node in
                Button(node.name) { onNavigate(node) }
            }
        } label: {
            Text("...")
                .font(.subheadline)
                .foregroundColor(.accentColor)
                .padding(.horizontal, 4)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()

        chevronSeparator

        breadcrumbSegment(node: path[path.count - 2], isLast: false)
        chevronSeparator

        breadcrumbSegment(node: path[path.count - 1], isLast: true)
    }

    private func breadcrumbSegment(node: FileNode, isLast: Bool) -> some View {
        Group {
            if isLast {
                Text(displayName(for: node))
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
            } else {
                Button(action: { onNavigate(node) }) {
                    Text(displayName(for: node))
                        .font(.subheadline)
                        .foregroundColor(.accentColor)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var chevronSeparator: some View {
        Image(systemName: "chevron.right")
            .font(.caption2)
            .foregroundColor(.secondary)
            .padding(.horizontal, 2)
    }

    private func displayName(for node: FileNode) -> String {
        if node.path == NSHomeDirectory() {
            return "~"
        }
        if node.path == "/" {
            return "/"
        }
        return node.name
    }
}
