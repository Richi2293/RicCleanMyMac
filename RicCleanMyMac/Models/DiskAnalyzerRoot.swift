import Foundation

/// Which directory the disk analyzer is scanning.
enum DiskAnalyzerRoot: Equatable {
    /// The user's home directory (`~`). This is the default.
    case home

    /// The entire boot volume (`/`).
    case entireDisk

    /// A user-chosen folder.
    case custom(path: String)

    /// The absolute filesystem path this root resolves to right now.
    var path: String {
        switch self {
        case .home:       return FileManager.default.homeDirectoryForCurrentUser.path
        case .entireDisk: return "/"
        case .custom(let path): return path
        }
    }

    /// Short human-readable label for the toolbar picker.
    var label: String {
        switch self {
        case .home:       return "Home"
        case .entireDisk: return "Entire disk"
        case .custom(let path): return (path as NSString).lastPathComponent
        }
    }

    // MARK: - UserDefaults codec

    private static let key = "diskAnalyzer.defaultRoot"

    /// Persist the current choice. Uses a simple string encoding:
    /// - `"home"` / `"root"` / `"custom:<absolutePath>"`
    func save(to defaults: UserDefaults = .standard) {
        let encoded: String
        switch self {
        case .home:       encoded = "home"
        case .entireDisk: encoded = "root"
        case .custom(let path): encoded = "custom:\(path)"
        }
        defaults.set(encoded, forKey: Self.key)
    }

    /// Load the persisted choice, defaulting to `.home` when no value was
    /// stored or when the stored value is malformed.
    static func load(from defaults: UserDefaults = .standard) -> DiskAnalyzerRoot {
        guard let raw = defaults.string(forKey: key) else { return .home }
        switch raw {
        case "home":       return .home
        case "root":       return .entireDisk
        default:
            if raw.hasPrefix("custom:") {
                let path = String(raw.dropFirst("custom:".count))
                if !path.isEmpty { return .custom(path: path) }
            }
            return .home
        }
    }
}
