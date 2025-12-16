import Foundation

extension FileManager {
    /// Calculate the total size of a directory recursively
    /// - Parameter url: The directory URL to calculate size for
    /// - Returns: Total size in bytes, or nil if calculation fails
    func directorySize(at url: URL) -> Int64? {
        guard fileExists(atPath: url.path) else {
            return nil
        }
        
        guard let enumerator = enumerator(
            at: url,
            includingPropertiesForKeys: [.fileSizeKey, .isDirectoryKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return nil
        }
        
        var totalSize: Int64 = 0
        
        for case let fileURL as URL in enumerator {
            // Skip if it's a directory
            if let isDirectory = try? fileURL.resourceValues(forKeys: [.isDirectoryKey]).isDirectory,
               isDirectory == true {
                continue
            }
            
            if let resourceValues = try? fileURL.resourceValues(forKeys: [.fileSizeKey]),
               let fileSize = resourceValues.fileSize {
                totalSize += Int64(fileSize)
            }
        }
        
        return totalSize > 0 ? totalSize : nil
    }
    
    /// Safely remove an item at the specified path
    /// - Parameter path: The path to remove
    /// - Returns: True if removal was successful, false otherwise
    @discardableResult
    func safeRemoveItem(atPath path: String) -> Bool {
        guard fileExists(atPath: path) else {
            return false
        }
        
        do {
            try removeItem(atPath: path)
            return true
        } catch {
            print("Error removing item at \(path): \(error.localizedDescription)")
            return false
        }
    }
    
    /// Validate that a path is within allowed safe directories
    /// - Parameters:
    ///   - path: The path to validate
    ///   - allowedDirectories: List of allowed directory paths
    /// - Returns: True if path is within allowed directories, false otherwise
    func isPathSafe(_ path: String, within allowedDirectories: [String]) -> Bool {
        let pathURL = URL(fileURLWithPath: path)
        
        for allowedDir in allowedDirectories {
            let allowedURL = URL(fileURLWithPath: allowedDir)
            if pathURL.path.hasPrefix(allowedURL.path) {
                return true
            }
        }
        
        return false
    }
}

