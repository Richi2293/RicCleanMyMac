import SwiftUI

@main
struct RicCleanMyMacApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    /// `true` when the app is launched only to host the unit tests. The window
    /// then stays empty, so the startup work of the services (disk space,
    /// space usage) does not run and does not slow the tests down.
    private static let isHostingTests =
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil

    var body: some Scene {
        WindowGroup {
            if Self.isHostingTests {
                EmptyView()
            } else {
                MainView()
            }
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) { }
        }
    }
}
