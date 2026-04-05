import SwiftUI

// MARK: - Data

struct SunburstSegment: Identifiable {
    let id = UUID()
    let node: FileNode
    let depth: Int
    let startAngle: Angle
    let endAngle: Angle
    let color: Color
}

// MARK: - Layout

enum SunburstLayout {
    /// Maximum children to show per node before aggregating into "Other"
    private static let maxChildrenPerNode = 10

    static func buildSegments(from root: FileNode, maxDepth: Int = 3) -> [SunburstSegment] {
        guard let children = root.children, root.size > 0 else { return [] }

        var segments: [SunburstSegment] = []
        let visibleChildren = Array(children.prefix(min(children.count, maxChildrenPerNode)))
        let palette = generatePalette(count: min(visibleChildren.count, 12))

        func traverse(node: FileNode, depth: Int, startAngle: Angle, sweep: Angle, color: Color) {
            guard depth <= maxDepth,
                  let children = node.children,
                  node.size > 0 else { return }

            let minSweep = Angle.degrees(360 * 0.01)
            var currentAngle = startAngle
            var otherSize: Int64 = 0

            // Children are already sorted by size descending — take only the top N
            let topChildren = Array(children.prefix(maxChildrenPerNode))
            let remainingSize = children.dropFirst(maxChildrenPerNode).reduce(Int64(0)) { $0 + $1.size }
            otherSize = remainingSize

            for (index, child) in topChildren.enumerated() {
                let ratio = Double(child.size) / Double(node.size)
                let childSweep = Angle.degrees(sweep.degrees * ratio)

                if childSweep < minSweep {
                    otherSize += child.size
                    continue
                }

                let childColor: Color
                if depth == 1 {
                    childColor = palette[index % palette.count]
                } else {
                    childColor = color.opacity(1.0 - Double(depth - 1) * 0.25)
                }

                segments.append(SunburstSegment(
                    node: child,
                    depth: depth,
                    startAngle: currentAngle,
                    endAngle: currentAngle + childSweep,
                    color: childColor
                ))

                if child.isDirectory {
                    traverse(
                        node: child,
                        depth: depth + 1,
                        startAngle: currentAngle,
                        sweep: childSweep,
                        color: childColor
                    )
                }

                currentAngle = currentAngle + childSweep
            }

            if otherSize > 0 {
                let otherSweep = Angle.degrees(sweep.degrees * Double(otherSize) / Double(node.size))
                if otherSweep >= minSweep {
                    segments.append(SunburstSegment(
                        node: FileNode(name: "Other", size: otherSize, isDirectory: false),
                        depth: depth,
                        startAngle: currentAngle,
                        endAngle: currentAngle + otherSweep,
                        color: Color.gray.opacity(0.3)
                    ))
                }
            }
        }

        traverse(node: root, depth: 1, startAngle: .degrees(0), sweep: .degrees(360), color: .accentColor)
        return segments
    }

    private static func generatePalette(count: Int) -> [Color] {
        (0..<count).map { index in
            Color(hue: Double(index) / Double(max(count, 1)), saturation: 0.55, brightness: 0.80)
        }
    }
}

// MARK: - Shape

struct AnnularSector: Shape {
    let innerRadius: CGFloat
    let outerRadius: CGFloat
    let startAngle: Angle
    let endAngle: Angle

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        var path = Path()
        let start = startAngle - .degrees(90)
        let end = endAngle - .degrees(90)
        path.addArc(center: center, radius: outerRadius, startAngle: start, endAngle: end, clockwise: false)
        path.addArc(center: center, radius: innerRadius, startAngle: end, endAngle: start, clockwise: true)
        path.closeSubpath()
        return path
    }
}

// MARK: - View

struct SunburstChartView: View {
    let rootNode: FileNode
    let onNavigate: (FileNode) -> Void

    @State private var hoveredSegment: UUID?

    private let ringWidth: CGFloat = 36
    private let centerRadius: CGFloat = 50

    var body: some View {
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height)
            let segments = SunburstLayout.buildSegments(from: rootNode)

            ZStack {
                VStack(spacing: 2) {
                    Text(rootNode.name)
                        .font(.caption)
                        .fontWeight(.semibold)
                        .lineLimit(1)
                    Text(rootNode.formattedSize)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .frame(width: centerRadius * 1.6)

                ForEach(segments) { segment in
                    let innerR = centerRadius + CGFloat(segment.depth - 1) * ringWidth
                    let outerR = innerR + ringWidth

                    AnnularSector(
                        innerRadius: innerR,
                        outerRadius: outerR,
                        startAngle: segment.startAngle,
                        endAngle: segment.endAngle
                    )
                    .fill(hoveredSegment == segment.id ? segment.color.opacity(0.9) : segment.color)
                    .overlay(
                        AnnularSector(
                            innerRadius: innerR,
                            outerRadius: outerR,
                            startAngle: segment.startAngle,
                            endAngle: segment.endAngle
                        )
                        .stroke(Color(NSColor.windowBackgroundColor), lineWidth: 1)
                    )
                    .onHover { isHovered in
                        hoveredSegment = isHovered ? segment.id : nil
                    }
                    .onTapGesture {
                        if segment.node.isDirectory {
                            onNavigate(segment.node)
                        }
                    }
                    .help(tooltipText(for: segment))
                }
            }
            .frame(width: size, height: size)
            .position(x: geo.size.width / 2, y: geo.size.height / 2)
        }
        .padding()
    }

    private func tooltipText(for segment: SunburstSegment) -> String {
        let percentage = String(format: "%.1f%%", segment.node.relativeSize * 100)
        return "\(segment.node.name) — \(segment.node.formattedSize) (\(percentage))"
    }
}
