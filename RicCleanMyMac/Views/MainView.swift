import SwiftUI

struct MainView: View {
    @StateObject private var cleanupService = CleanupService()
    @State private var selectedSection: NavigationSection = .dashboard
    
    enum NavigationSection: String, CaseIterable {
        case dashboard = "Dashboard"
        case cleanup = "Cleanup"
        
        var icon: String {
            switch self {
            case .dashboard:
                return "chart.bar.fill"
            case .cleanup:
                return "trash.fill"
            }
        }
    }
    
    var body: some View {
        NavigationSplitView {
            // Sidebar
            List(NavigationSection.allCases, id: \.self, selection: $selectedSection) { section in
                Label(section.rawValue, systemImage: section.icon)
                    .tag(section)
            }
            .navigationTitle("RicCleanMyMac")
            .frame(minWidth: 200)
        } detail: {
            // Detail view
            Group {
                switch selectedSection {
                case .dashboard:
                    DashboardView()
                case .cleanup:
                    CleanupView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .environmentObject(cleanupService)
    }
}

