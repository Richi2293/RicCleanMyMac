import Foundation

/// How the scanner should treat a given path.
enum Classification: Equatable {
    /// Traverse normally, node is deletable.
    case scanned

    /// Traverse and measure, but the node (and descendants that don't override)
    /// must not be deletable from the UI.
    case readOnly

    /// Do not traverse at all. The scanner emits a placeholder directory node
    /// with `size == 0` so the user still sees that the path exists.
    case skipped(reason: String)
}

/// Stateless classifier that decides, for any URL, whether the scanner should
/// traverse it, traverse-but-mark-read-only, or skip it entirely.
///
/// All knowledge of "which system paths should be hidden from the cleaner" is
/// centralized here so the deletion gate and the traversal gate can never
/// diverge. The type is a pure function of its input: no filesystem access,
/// no mutable state.
enum ScanPolicy {
    /// Hard-skip list: these paths (and any descendants) are not traversed.
    /// Matches are applied after path normalization and lowercasing.
    private static let hardSkipPrefixes: [String] = [
        "/system",
        "/usr",
        "/bin",
        "/sbin",
        "/dev",
        "/cores",
        "/.vol",
        "/private/var/db",
        "/private/var/folders",
        "/.spotlight-v100",
        "/.fseventsd",
        "/.documentrevisions-v100",
        "/.temporaryitems",
        "/.trashes",
        "/volumes"
    ]

    /// Exceptions to `hardSkipPrefixes`. If a path matches both a hard-skip
    /// prefix and an exception prefix, the exception wins and the path is
    /// treated normally (`.scanned`).
    private static let hardSkipExceptions: [String] = [
        "/usr/local"
    ]

    /// Soft-skip prefixes outside of `~/Library`. Paths under these roots are
    /// traversed and measured, but the resulting nodes are marked `.readOnly`.
    private static let softSkipPrefixes: [String] = [
        "/library",
        "/applications",
        "/opt"
    ]

    /// Sub-paths of `~/Library` that should remain `.scanned` (deletable) even
    /// though `~/Library` itself is otherwise soft-skipped. These are the
    /// classic "safe to delete to free space" targets.
    ///
    /// Stored without the `~/Library/` prefix; the classifier prepends the
    /// actual home directory at match time.
    private static let libraryWhitelist: [String] = [
        "caches",
        "logs",
        "saved application state",
        "application support/crashreporter",
        "developer/xcode/deriveddata",
        "developer/xcode/ios devicesupport",
        "developer/xcode/watchos devicesupport",
        "developer/xcode/tvos devicesupport",
        "developer/coresimulator/caches"
    ]

    /// Returns `true` if `path` equals `prefix` or starts with `prefix + "/"`.
    /// Both inputs must already be lowercase and not have a trailing slash.
    private static func path(_ path: String, isUnderPrefix prefix: String) -> Bool {
        if path == prefix { return true }
        return path.hasPrefix(prefix + "/")
    }

    /// Classify a URL against the policy rules.
    ///
    /// - Parameters:
    ///   - url: The URL to classify. It is standardized internally.
    ///   - homeDirectory: The user's home directory (defaults to the current
    ///     user's home; overridable for future tests).
    ///   - bootVolumeName: The name of the boot volume under `/Volumes` that
    ///     should be allowed through `/Volumes`'s hard-skip. When `nil`, the
    ///     name is resolved lazily from the filesystem.
    /// - Returns: How the scanner should treat this path.
    static func classify(
        _ url: URL,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        bootVolumeName: String? = nil
    ) -> Classification {
        let normalized = url.standardizedFileURL.path
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let absolute = normalized.isEmpty ? "/" : "/" + normalized
        let lower = absolute.lowercased()

        // The root "/" itself is always scanned. Without this, the whole tree
        // starts as `.scanned` because "/" does not match any prefix anyway,
        // but being explicit protects against future rule additions.
        if lower == "/" { return .scanned }

        // Hard-skip exceptions win over hard-skip prefixes.
        for exception in hardSkipExceptions {
            if path(lower, isUnderPrefix: exception) { return .scanned }
        }

        // `/Volumes/<bootVolume>` is allowed through so the user's own disk,
        // which is firmlinked at `/Volumes/<name>` on modern macOS, remains
        // scannable when scanning from `/`.
        if lower.hasPrefix("/volumes/") {
            let resolvedBootName = (bootVolumeName ?? Self.bootVolumeName()).lowercased()
            if !resolvedBootName.isEmpty {
                let bootPrefix = "/volumes/" + resolvedBootName
                if path(lower, isUnderPrefix: bootPrefix) { return .scanned }
            }
        }

        for prefix in hardSkipPrefixes {
            if path(lower, isUnderPrefix: prefix) {
                return .skipped(reason: "System")
            }
        }

        // `~/Library` handling — whitelist first, then soft-skip fallback.
        let homeLower = homeDirectory.standardizedFileURL.path.lowercased()
        let libraryRoot = homeLower.hasSuffix("/")
            ? homeLower + "library"
            : homeLower + "/library"
        if path(lower, isUnderPrefix: libraryRoot) {
            let relative = String(lower.dropFirst(libraryRoot.count))
                .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            for entry in libraryWhitelist {
                if relative == entry || relative.hasPrefix(entry + "/") {
                    return .scanned
                }
            }
            return .readOnly
        }

        for prefix in softSkipPrefixes {
            if path(lower, isUnderPrefix: prefix) {
                return .readOnly
            }
        }

        return .scanned
    }

    /// Resolve the name of the boot volume (the one mounted at `/`). This is
    /// used exactly once per scan run from `DirectoryScanner`, so the cost of
    /// the filesystem call is negligible.
    private static func bootVolumeName() -> String {
        let rootURL = URL(fileURLWithPath: "/")
        let values = try? rootURL.resourceValues(forKeys: [.volumeNameKey])
        return values?.volumeName ?? ""
    }
}
