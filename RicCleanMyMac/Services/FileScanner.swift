import Foundation

/// Service for scanning directories for cleanup items (read-only operations)
class FileScanner {
    private let fileManager = FileManager.default
    
    /// Scan for cleanup items in standard system directories
    /// - Returns: Array of CleanupItem found during scan
    func scanForCleanupItems() async -> [CleanupItem] {
        var items: [CleanupItem] = []
        
        // Scan user cache directory
        if let cacheItems = await scanCacheDirectory() {
            items.append(contentsOf: cacheItems)
        }
        
        // Scan log directory
        if let logItems = await scanLogDirectory() {
            items.append(contentsOf: logItems)
        }
        
        // Scan temporary files
        if let tempItems = await scanTemporaryDirectory() {
            items.append(contentsOf: tempItems)
        }
        
        return items
    }
    
    /// Scan user cache directory
    private func scanCacheDirectory() async -> [CleanupItem]? {
        guard let cacheURL = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first else {
            return nil
        }
        
        return await scanDirectory(url: cacheURL, type: .cache, name: "User Caches")
    }
    
    /// Scan log directory
    private func scanLogDirectory() async -> [CleanupItem]? {
        guard let libraryURL = fileManager.urls(for: .libraryDirectory, in: .userDomainMask).first else {
            return nil
        }
        
        let logsURL = libraryURL.appendingPathComponent("Logs")
        
        guard fileManager.fileExists(atPath: logsURL.path) else {
            return nil
        }
        
        return await scanDirectory(url: logsURL, type: .logs, name: "Log Files")
    }
    
    /// Scan temporary directory
    private func scanTemporaryDirectory() async -> [CleanupItem]? {
        let tempURL = fileManager.temporaryDirectory
        
        guard fileManager.fileExists(atPath: tempURL.path) else {
            return nil
        }
        
        return await scanDirectory(url: tempURL, type: .temp, name: "Temporary Files")
    }
    
    /// Scan a specific directory and return cleanup items
    /// - Parameters:
    ///   - url: The directory URL to scan
    ///   - type: The type of cleanup item
    ///   - name: Display name for the item
    /// - Returns: Array of CleanupItem, or nil if scan fails
    private func scanDirectory(url: URL, type: CleanupType, name: String) async -> [CleanupItem]? {
        return await Task.detached(priority: .userInitiated) {
            guard let size = FileManager.default.directorySize(at: url) else {
                return nil
            }
            
            return [CleanupItem(
                name: name,
                path: url.path,
                size: size,
                type: type
            )]
        }.value
    }
}

