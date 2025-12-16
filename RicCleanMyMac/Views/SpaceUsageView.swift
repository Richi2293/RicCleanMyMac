import SwiftUI

struct SpaceUsageView: View {
    @EnvironmentObject var cleanupService: CleanupService
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Space Usage by Directory")
                    .font(.headline)
                
                Spacer()
                
                if cleanupService.isScanningSpaceUsage {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle())
                        .scaleEffect(0.7)
                } else {
                    Button(action: {
                        Task {
                            await cleanupService.scanSpaceUsage()
                        }
                    }) {
                        Image(systemName: "arrow.clockwise")
                            .font(.caption)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            
            if cleanupService.spaceUsageItems.isEmpty && !cleanupService.isScanningSpaceUsage {
                Text("No directories found")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 8)
            } else if cleanupService.isScanningSpaceUsage {
                Text("Scanning directories...")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 8)
            } else {
                let maxSize = cleanupService.spaceUsageItems.first?.size ?? 1
                
                ForEach(cleanupService.spaceUsageItems) { item in
                    SpaceUsageRow(item: item, maxSize: maxSize)
                }
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(10)
    }
}

struct SpaceUsageRow: View {
    let item: SpaceUsageItem
    let maxSize: Int64
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(item.displayName)
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Spacer()
                
                Text(item.formattedSize)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.accentColor)
            }
            
            // Progress bar showing relative size
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(Color.gray.opacity(0.2))
                        .frame(height: 6)
                        .cornerRadius(3)
                    
                    Rectangle()
                        .fill(Color.accentColor)
                        .frame(
                            width: geometry.size.width * CGFloat(Double(item.size) / Double(maxSize)),
                            height: 6
                        )
                        .cornerRadius(3)
                }
            }
            .frame(height: 6)
            
            // Path (truncated)
            Text(item.path)
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(.vertical, 4)
    }
}

