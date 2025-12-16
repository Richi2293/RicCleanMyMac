import SwiftUI

struct DashboardView: View {
    @EnvironmentObject var cleanupService: CleanupService
    
    var body: some View {
        VStack(spacing: 30) {
            // Disk space information
            if let diskSpace = cleanupService.diskSpace {
                DiskSpaceCard(diskSpace: diskSpace)
            }
            
            // Scan button
            VStack(spacing: 16) {
                Button(action: {
                    Task {
                        await cleanupService.scan()
                    }
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
            
            Spacer()
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct DiskSpaceCard: View {
    let diskSpace: DiskSpace
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Disk Space")
                .font(.headline)
            
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Total")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(diskSpace.formattedTotal)
                        .font(.title3)
                        .fontWeight(.semibold)
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 4) {
                    Text("Available")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(diskSpace.formattedAvailable)
                        .font(.title3)
                        .fontWeight(.semibold)
                        .foregroundColor(.green)
                }
            }
            
            // Progress bar
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(Color.gray.opacity(0.2))
                        .frame(height: 8)
                        .cornerRadius(4)
                    
                    Rectangle()
                        .fill(Color.accentColor)
                        .frame(width: geometry.size.width * CGFloat(diskSpace.usedPercentage), height: 8)
                        .cornerRadius(4)
                }
            }
            .frame(height: 8)
            
            Text("\(Int(diskSpace.usedPercentage * 100))% used")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(10)
    }
}

