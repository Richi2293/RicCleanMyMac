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
        HSplitView {
            // Sidebar
            List(NavigationSection.allCases, id: \.self) { section in
                Button(action: {
                    selectedSection = section
                }) {
                    Label(section.rawValue, systemImage: section.icon)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PlainButtonStyle())
                .background(selectedSection == section ? Color.accentColor.opacity(0.2) : Color.clear)
            }
            .frame(minWidth: 200)
            .listStyle(SidebarListStyle())
            
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

