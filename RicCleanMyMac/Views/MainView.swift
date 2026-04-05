import SwiftUI

struct MainView: View {
    @StateObject private var cleanupService = CleanupService()
    @State private var selectedSection: NavigationSection? = .dashboard

    enum NavigationSection: String, CaseIterable {
        case dashboard = "Dashboard"
        case cleanup = "Cleanup"

        var icon: String {
            switch self {
            case .dashboard: return "chart.bar.fill"
            case .cleanup: return "trash.fill"
            }
        }
    }

    var body: some View {
        NavigationSplitView {
            List(NavigationSection.allCases, id: \.self, selection: $selectedSection) { section in
                Label(section.rawValue, systemImage: section.icon)
                    .tag(section)
            }
            .listStyle(SidebarListStyle())
            .navigationSplitViewColumnWidth(min: 180, ideal: 200)
        } detail: {
            Group {
                switch selectedSection {
                case .cleanup:
                    CleanupView()
                case .dashboard, .none:
                    DashboardView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .environmentObject(cleanupService)
    }
}
