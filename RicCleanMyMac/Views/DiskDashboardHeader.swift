import SwiftUI

struct DiskDashboardHeader: View {
    let diskSpace: DiskSpace?
    let smartCategories: [SmartCategory]
    let isScanComplete: Bool
    let isScanning: Bool
    let onCategoryTapped: (SmartCategory) -> Void

    @AppStorage("diskDashboardExpanded") private var isExpanded = true

    var body: some View {
        VStack(spacing: 0) {
            if isExpanded {
                expandedView
            } else {
                collapsedView
            }
        }
        .background(Color(NSColor.controlBackgroundColor))
    }

    // MARK: - Collapsed

    private var collapsedView: some View {
        HStack(spacing: 8) {
            if let ds = diskSpace {
                Circle()
                    .fill(gaugeColor(for: ds.usedPercentage))
                    .frame(width: 8, height: 8)
                Text("\(Int(ds.usedPercentage * 100))% — \(ds.formattedAvailable) available")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                ProgressView()
                    .scaleEffect(0.5)
                Text("Loading disk info…")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            expandCollapseButton
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    // MARK: - Expanded

    private var expandedView: some View {
        VStack(spacing: 12) {
            // Level 1: Disk gauge
            HStack(spacing: 16) {
                if let ds = diskSpace {
                    diskGauge(ds)
                    diskStats(ds)
                } else {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Loading disk info…")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                Spacer()
                expandCollapseButton
            }

            // Level 2: Smart categories
            if isScanComplete && !smartCategories.isEmpty {
                Divider()
                categoriesRow
            } else if isScanning {
                Divider()
                HStack(spacing: 6) {
                    ProgressView()
                        .scaleEffect(0.5)
                    Text("Analysing categories…")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 2)
            } else if !isScanComplete {
                Divider()
                Text("Start a scan to see space breakdown by category")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.vertical, 2)
            }
        }
        .padding(12)
    }

    // MARK: - Gauge

    private func diskGauge(_ ds: DiskSpace) -> some View {
        ZStack {
            Circle()
                .stroke(Color.gray.opacity(0.2), lineWidth: 6)
            Circle()
                .trim(from: 0, to: ds.usedPercentage)
                .stroke(
                    gaugeColor(for: ds.usedPercentage),
                    style: StrokeStyle(lineWidth: 6, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))

            Text("\(Int(ds.usedPercentage * 100))%")
                .font(.system(.caption, design: .rounded, weight: .bold))
        }
        .frame(width: 48, height: 48)
    }

    private func diskStats(_ ds: DiskSpace) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(ds.formattedUsed) used of \(ds.formattedTotal)")
                .font(.subheadline)
                .fontWeight(.medium)
            Text("\(ds.formattedAvailable) available")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    // MARK: - Categories

    private var categoriesRow: some View {
        HStack(spacing: 8) {
            ForEach(smartCategories) { category in
                categoryCard(category)
            }
        }
    }

    private func categoryCard(_ category: SmartCategory) -> some View {
        Button {
            onCategoryTapped(category)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: category.icon)
                    .font(.caption)
                    .foregroundColor(.accentColor)
                VStack(alignment: .leading, spacing: 1) {
                    Text(category.name)
                        .font(.caption2)
                        .foregroundColor(.primary)
                    Text(category.formattedSize)
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(6)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.gray.opacity(0.2), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Helpers

    private var expandCollapseButton: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                isExpanded.toggle()
            }
        } label: {
            Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .buttonStyle(.plain)
    }

    private func gaugeColor(for percentage: Double) -> Color {
        if percentage >= 0.8 { return .red }
        if percentage >= 0.6 { return .yellow }
        return .green
    }
}
