import SwiftUI

struct DashboardView: View {
    @EnvironmentObject var cleanupService: CleanupService

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                if let diskSpace = cleanupService.diskSpace {
                    DiskSpaceCard(diskSpace: diskSpace)
                } else {
                    DiskSpaceUnavailableCard {
                        Task { await cleanupService.scanSpaceUsage() }
                    }
                }

                SpaceUsageView()
                    .environmentObject(cleanupService)

                VStack(spacing: 16) {
                    Button(action: {
                        Task { await cleanupService.scan() }
                    }) {
                        HStack {
                            if cleanupService.isScanning {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle())
                                    .scaleEffect(0.8)
                            } else {
                                Image(systemName: "magnifyingglass")
                            }
                            Text(cleanupService.isScanning ? "Scanning..." : "Scan for Cleanup")
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.accentColor)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                    }
                    .disabled(cleanupService.isScanning)

                    if cleanupService.totalSize > 0 {
                        Text("Found \(ByteCountFormatter.string(fromByteCount: cleanupService.totalSize)) that can be cleaned")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
                .padding()
            }
            .padding()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - DiskSpaceCard

struct DiskSpaceCard: View {
    let diskSpace: DiskSpace

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Disk Space")
                .font(.headline)

            HStack(spacing: 24) {
                DonutChart(usedPercentage: diskSpace.usedPercentage)

                VStack(alignment: .leading, spacing: 10) {
                    diskLegendRow(color: usageColor, label: "Used", value: diskSpace.formattedUsed)
                    diskLegendRow(color: .green.opacity(0.7), label: "Available", value: diskSpace.formattedAvailable)
                    if diskSpace.purgeable > 0 {
                        diskLegendRow(color: .green.opacity(0.35), label: "Purgeable", value: diskSpace.formattedPurgeable, caption: "reclaimable by macOS")
                        Divider()
                        diskLegendRow(color: .green, label: "Total Available", value: diskSpace.formattedAvailableForImportantUsage, caption: "as shown by macOS")
                    }
                    diskLegendRow(color: Color(NSColor.separatorColor), label: "Total", value: diskSpace.formattedTotal)
                }

                Spacer()
            }

            if diskSpace.purgeable > 0 {
                HStack(spacing: 6) {
                    Image(systemName: "info.circle")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text("macOS reports \(diskSpace.formattedAvailableForImportantUsage) available (includes purgeable space)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(10)
    }

    private var usageColor: Color {
        switch diskSpace.usedPercentage {
        case ..<0.7: return .accentColor
        case ..<0.85: return .orange
        default: return .red
        }
    }

    private func diskLegendRow(color: Color, label: String, value: String, caption: String? = nil) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(color)
                .frame(width: 10, height: 10)
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
            Text(value)
                .font(.caption)
                .fontWeight(.semibold)
            if let caption {
                Text("(\(caption))")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
    }
}

// MARK: - DiskSpaceUnavailableCard

struct DiskSpaceUnavailableCard: View {
    let onRetry: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "externaldrive.trianglebadge.exclamationmark")
                .font(.title)
                .foregroundColor(.secondary)
            Text("Unable to load disk space information")
                .font(.subheadline)
                .foregroundColor(.secondary)
            Button("Retry", action: onRetry)
                .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(10)
    }
}

// MARK: - DonutChart

struct DonutChart: View {
    let usedPercentage: Double

    private let size: CGFloat = 110
    private let lineWidth: CGFloat = 16

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.green.opacity(0.25), lineWidth: lineWidth)
                .frame(width: size, height: size)

            Circle()
                .trim(from: 0, to: CGFloat(min(usedPercentage, 1.0)))
                .stroke(
                    LinearGradient(
                        colors: arcColors,
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .frame(width: size, height: size)
                .rotationEffect(.degrees(-90))
                .animation(.easeOut(duration: 0.6), value: usedPercentage)

            VStack(spacing: 2) {
                Text("\(Int(usedPercentage * 100))%")
                    .font(.title2)
                    .fontWeight(.bold)
                Text("used")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
    }

    private var arcColors: [Color] {
        switch usedPercentage {
        case ..<0.7: return [.accentColor, .accentColor.opacity(0.7)]
        case ..<0.85: return [.orange, .yellow]
        default: return [.red, .orange]
        }
    }
}
