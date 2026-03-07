import Foundation

/// Service for scanning directories for cleanup items (read-only operations)
class FileScanner {
    private let fileManager = FileManager.default

    /// Scan for cleanup items in standard system directories
    /// - Returns: Array of CleanupItem found during scan
    func scanForCleanupItems() async -> [CleanupItem] {
        var items: [CleanupItem] = []

        if let cacheItems = await scanCacheDirectory() {
            items.append(contentsOf: cacheItems)
        }

        if let logItems = await scanLogDirectory() {
            items.append(contentsOf: logItems)
        }

        if let tempItems = await scanTemporaryDirectory() {
            items.append(contentsOf: tempItems)
        }

        if let downloadItems = await scanDownloadsDirectory() {
            items.append(contentsOf: downloadItems)
        }

        if let trashItems = await scanTrashDirectory() {
            items.append(contentsOf: trashItems)
        }

        return items
    }

    // MARK: - Private scan methods

    private func scanCacheDirectory() async -> [CleanupItem]? {
        guard let cacheURL = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first else {
            return nil
        }
        return await scanSubitems(of: cacheURL, type: .cache, skipsHidden: true)
    }

    private func scanLogDirectory() async -> [CleanupItem]? {
        guard let libraryURL = fileManager.urls(for: .libraryDirectory, in: .userDomainMask).first else {
            return nil
        }
        let logsURL = libraryURL.appendingPathComponent("Logs")
        guard fileManager.fileExists(atPath: logsURL.path) else { return nil }
        return await scanSubitems(of: logsURL, type: .logs, skipsHidden: true)
    }

    private func scanTemporaryDirectory() async -> [CleanupItem]? {
        let tempURL = fileManager.temporaryDirectory
        guard fileManager.fileExists(atPath: tempURL.path) else { return nil }
        return await scanAggregated(url: tempURL, type: .temp, name: "Temporary Files")
    }

    private func scanDownloadsDirectory() async -> [CleanupItem]? {
        let downloadsURL = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Downloads")
        guard fileManager.fileExists(atPath: downloadsURL.path) else { return nil }
        return await scanSubitems(of: downloadsURL, type: .downloads, skipsHidden: false)
    }

    private func scanTrashDirectory() async -> [CleanupItem]? {
        let trashURL = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".Trash")
        guard fileManager.fileExists(atPath: trashURL.path) else { return nil }
        return await scanSubitems(of: trashURL, type: .trash, skipsHidden: false)
    }

    // MARK: - Helpers

    /// Enumerate first-level contents and return one CleanupItem per entry
    private func scanSubitems(of parentURL: URL, type: CleanupType, skipsHidden: Bool) async -> [CleanupItem]? {
        return await Task.detached(priority: .userInitiated) {
            let fm = FileManager.default
            let options: FileManager.DirectoryEnumerationOptions = skipsHidden ? [.skipsHiddenFiles] : []

            guard let contents = try? fm.contentsOfDirectory(
                at: parentURL,
                includingPropertiesForKeys: [.fileSizeKey, .isDirectoryKey],
                options: options
            ) else {
                return nil
            }

            var items: [CleanupItem] = []
            for url in contents {
                guard let size = Self.itemSize(at: url, fileManager: fm), size > 0 else { continue }
                items.append(CleanupItem(name: url.lastPathComponent, path: url.path, size: size, type: type))
            }
            return items.isEmpty ? nil : items
        }.value
    }

    /// Return a single aggregated CleanupItem for the whole directory
    private func scanAggregated(url: URL, type: CleanupType, name: String) async -> [CleanupItem]? {
        return await Task.detached(priority: .userInitiated) {
            guard let size = FileManager.default.directorySize(at: url) else { return nil }
            return [CleanupItem(name: name, path: url.path, size: size, type: type)]
        }.value
    }

    /// Return the size of a file or directory
    private static func itemSize(at url: URL, fileManager: FileManager) -> Int64? {
        let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
        if isDirectory {
            return fileManager.directorySize(at: url)
        } else {
            if let fileSize = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) {
                return fileSize > 0 ? Int64(fileSize) : nil
            }
            return nil
        }
    }
}
