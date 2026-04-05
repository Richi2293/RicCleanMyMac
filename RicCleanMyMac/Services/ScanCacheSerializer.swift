import Foundation

enum ScanCacheError: Error {
    case invalidMagic
    case unsupportedVersion(UInt8)
    case truncatedData
}

enum ScanCacheSerializer {
    private static let magic: [UInt8] = [0x52, 0x43, 0x53, 0x4E] // "RCSN"
    private static let currentVersion: UInt8 = 1

    // MARK: - Write

    static func write(_ result: DirectoryScanResult) -> Data {
        let estimatedSize = (result.totalFiles + result.totalDirectories) * 36
        var data = Data(capacity: estimatedSize)

        // Header
        data.append(contentsOf: magic)
        data.appendUInt8(currentVersion)
        data.appendUInt32(UInt32(result.totalFiles))
        data.appendUInt32(UInt32(result.totalDirectories))
        data.appendInt64(result.totalSize)
        data.appendFloat64(result.scanDuration)
        data.appendFloat64(result.scanDate.timeIntervalSinceReferenceDate)

        // Tree (depth-first)
        writeNode(result.root, to: &data)

        return data
    }

    private static func writeNode(_ node: FileNode, to data: inout Data) {
        // Name
        let nameBytes = Array(node.name.utf8)
        data.appendUInt16(UInt16(nameBytes.count))
        data.append(contentsOf: nameBytes)

        // Size
        data.appendInt64(node.size)

        // Flags: bit 0 = isDirectory, bit 1 = accessDenied
        var flags: UInt8 = 0
        if node.isDirectory { flags |= 1 }
        if node.accessDenied { flags |= 2 }
        data.appendUInt8(flags)

        // Child count
        let childCount = UInt32(node.children?.count ?? 0)
        data.appendUInt32(childCount)

        // Children (depth-first recursion)
        if let children = node.children {
            for child in children {
                writeNode(child, to: &data)
            }
        }
    }

    // MARK: - Read

    static func read(from data: Data) throws -> DirectoryScanResult {
        var reader = BinaryReader(data: data)

        // Header
        let fileMagic = try reader.readBytes(4)
        guard fileMagic == magic else { throw ScanCacheError.invalidMagic }

        let version = try reader.readUInt8()
        guard version == currentVersion else { throw ScanCacheError.unsupportedVersion(version) }

        let totalFiles = try reader.readUInt32()
        let totalDirectories = try reader.readUInt32()
        let totalSize = try reader.readInt64()
        let scanDuration = try reader.readFloat64()
        let scanDate = Date(timeIntervalSinceReferenceDate: try reader.readFloat64())

        // Tree
        let root = try readNode(from: &reader, parent: nil)

        return DirectoryScanResult(
            root: root,
            totalSize: totalSize,
            totalFiles: Int(totalFiles),
            totalDirectories: Int(totalDirectories),
            scanDuration: scanDuration,
            scanDate: scanDate
        )
    }

    private static func readNode(from reader: inout BinaryReader, parent: FileNode?) throws -> FileNode {
        let nameLength = try reader.readUInt16()
        let nameBytes = try reader.readBytes(Int(nameLength))
        let name = String(bytes: nameBytes, encoding: .utf8) ?? ""

        let size = try reader.readInt64()
        let flags = try reader.readUInt8()
        let childCount = try reader.readUInt32()

        let node = FileNode(
            name: name,
            size: size,
            isDirectory: flags & 1 != 0,
            accessDenied: flags & 2 != 0
        )
        node.parent = parent

        if childCount > 0 {
            var children: [FileNode] = []
            children.reserveCapacity(Int(childCount))
            for _ in 0..<childCount {
                let child = try readNode(from: &reader, parent: node)
                children.append(child)
            }
            node.children = children
        }

        return node
    }
}

// MARK: - Binary Reader

private struct BinaryReader {
    let data: Data
    var offset: Int = 0

    mutating func readBytes(_ count: Int) throws -> [UInt8] {
        guard offset + count <= data.count else { throw ScanCacheError.truncatedData }
        let bytes = data.withUnsafeBytes { buffer in
            Array(buffer[offset..<offset + count])
        }
        offset += count
        return bytes
    }

    mutating func readUInt8() throws -> UInt8 {
        guard offset + 1 <= data.count else { throw ScanCacheError.truncatedData }
        let value = data[offset]
        offset += 1
        return value
    }

    mutating func readUInt16() throws -> UInt16 {
        guard offset + 2 <= data.count else { throw ScanCacheError.truncatedData }
        let value = data.withUnsafeBytes { buffer in
            buffer.load(fromByteOffset: offset, as: UInt16.self)
        }
        offset += 2
        return UInt16(littleEndian: value)
    }

    mutating func readUInt32() throws -> UInt32 {
        guard offset + 4 <= data.count else { throw ScanCacheError.truncatedData }
        let value = data.withUnsafeBytes { buffer in
            buffer.load(fromByteOffset: offset, as: UInt32.self)
        }
        offset += 4
        return UInt32(littleEndian: value)
    }

    mutating func readInt64() throws -> Int64 {
        guard offset + 8 <= data.count else { throw ScanCacheError.truncatedData }
        let value = data.withUnsafeBytes { buffer in
            buffer.load(fromByteOffset: offset, as: Int64.self)
        }
        offset += 8
        return Int64(littleEndian: value)
    }

    mutating func readFloat64() throws -> Float64 {
        guard offset + 8 <= data.count else { throw ScanCacheError.truncatedData }
        let bits = data.withUnsafeBytes { buffer in
            buffer.load(fromByteOffset: offset, as: UInt64.self)
        }
        offset += 8
        return Float64(bitPattern: UInt64(littleEndian: bits))
    }
}

// MARK: - Data Writing Helpers

private extension Data {
    mutating func appendUInt8(_ value: UInt8) {
        append(value)
    }

    mutating func appendUInt16(_ value: UInt16) {
        var v = value.littleEndian
        Swift.withUnsafeBytes(of: &v) { append(contentsOf: $0) }
    }

    mutating func appendUInt32(_ value: UInt32) {
        var v = value.littleEndian
        Swift.withUnsafeBytes(of: &v) { append(contentsOf: $0) }
    }

    mutating func appendInt64(_ value: Int64) {
        var v = value.littleEndian
        Swift.withUnsafeBytes(of: &v) { append(contentsOf: $0) }
    }

    mutating func appendFloat64(_ value: Float64) {
        var v = value.bitPattern.littleEndian
        Swift.withUnsafeBytes(of: &v) { append(contentsOf: $0) }
    }
}
