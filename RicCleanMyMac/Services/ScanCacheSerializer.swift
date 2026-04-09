import Foundation

enum ScanCacheError: Error {
    case invalidMagic
    case unsupportedVersion(UInt8)
    case truncatedData
    case corruptedString
    case childCountTooLarge(UInt32)
    case trailingData
    case valueTooLarge(String)
    case corruptedFlags(UInt8)
}

/// Custom binary format for persisting directory scan results.
///
/// All integers are little-endian. The file is LZFSE-compressed externally by
/// `DirectoryScanner`, so this serializer works on raw (decompressed) bytes.
///
/// File layout:
///     magic           4 bytes    ASCII "RCSN"
///     version         1 byte     current = 1
///     totalFiles      4 bytes    UInt32 (header-only; authoritative size is derived from the tree)
///     totalDirs       4 bytes    UInt32
///     legacyTotalSize 8 bytes    Int64 (written for backward compatibility; ignored on read)
///     scanDuration    8 bytes    Float64 seconds
///     scanDate        8 bytes    Float64 secondsSinceReferenceDate
///     rootNode        variable   see node layout
///
/// Node layout (depth-first):
///     nameLen         2 bytes    UInt16 UTF-8 byte length (max 65_535)
///     nameBytes       nameLen    UTF-8
///     size            8 bytes    Int64
///     flags           1 byte     bit 0 = isDirectory
///                                bits 1-2 = status (00 = normal, 01 = readOnly,
///                                                   10 = skipped, 11 = inaccessible)
///     skipReasonLen   2 bytes    UInt16, present only when status == skipped
///     skipReasonBytes variable   UTF-8, present only when status == skipped
///     childCount      4 bytes    UInt32, capped at `maxChildCount` on read
///     children        variable   recursive node records
enum ScanCacheSerializer {
    private static let magic: [UInt8] = [0x52, 0x43, 0x53, 0x4E] // "RCSN"
    private static let currentVersion: UInt8 = 1

    /// Upper bound on children per directory when reading a cache file, to prevent
    /// OOM on a corrupted `childCount` field. Ten million is well above any sane
    /// filesystem directory cardinality.
    private static let maxChildCount: UInt32 = 10_000_000

    /// Rough per-node byte estimate used to pre-size the output buffer.
    /// Average: 2 (nameLen) + ~16 (name) + 8 (size) + 1 (flags) + 4 (childCount) + slack.
    private static let estimatedBytesPerNode = 36

    // MARK: - Write

    static func write(_ result: DirectoryScanResult) throws -> Data {
        guard result.totalFiles <= Int(UInt32.max) else {
            throw ScanCacheError.valueTooLarge("totalFiles exceeds UInt32 range")
        }
        guard result.totalDirectories <= Int(UInt32.max) else {
            throw ScanCacheError.valueTooLarge("totalDirectories exceeds UInt32 range")
        }

        let estimatedSize = (result.totalFiles + result.totalDirectories) * estimatedBytesPerNode
        var data = Data(capacity: estimatedSize)

        data.append(contentsOf: magic)
        data.appendUInt8(currentVersion)
        data.appendUInt32(UInt32(result.totalFiles))
        data.appendUInt32(UInt32(result.totalDirectories))
        data.appendInt64(result.totalSize)
        data.appendFloat64(result.scanDuration)
        data.appendFloat64(result.scanDate.timeIntervalSinceReferenceDate)

        try writeNode(result.root, to: &data)

        return data
    }

    private static func writeNode(_ node: FileNode, to data: inout Data) throws {
        let nameBytes = Array(node.name.utf8)
        guard nameBytes.count <= Int(UInt16.max) else {
            throw ScanCacheError.valueTooLarge("node name UTF-8 length \(nameBytes.count) exceeds UInt16 range")
        }
        data.appendUInt16(UInt16(nameBytes.count))
        data.append(contentsOf: nameBytes)

        data.appendInt64(node.size)

        var flags: UInt8 = 0
        if node.isDirectory { flags |= 1 }

        let statusBits: UInt8
        switch node.status {
        case .normal:       statusBits = 0b00
        case .readOnly:     statusBits = 0b01
        case .skipped:      statusBits = 0b10
        case .inaccessible: statusBits = 0b11
        }
        flags |= (statusBits << 1)
        data.appendUInt8(flags)

        if case .skipped(let reason) = node.status {
            let reasonBytes = Array(reason.utf8)
            guard reasonBytes.count <= Int(UInt16.max) else {
                throw ScanCacheError.valueTooLarge("skip reason UTF-8 length \(reasonBytes.count) exceeds UInt16 range")
            }
            data.appendUInt16(UInt16(reasonBytes.count))
            data.append(contentsOf: reasonBytes)
        }

        let children = node.children ?? []
        guard children.count <= Int(UInt32.max) else {
            throw ScanCacheError.valueTooLarge("child count \(children.count) exceeds UInt32 range")
        }
        data.appendUInt32(UInt32(children.count))

        for child in children {
            try writeNode(child, to: &data)
        }
    }

    // MARK: - Read

    static func read(from data: Data) throws -> DirectoryScanResult {
        var reader = BinaryReader(data: data)

        let fileMagic = try reader.readBytes(4)
        guard fileMagic == magic else { throw ScanCacheError.invalidMagic }

        let version = try reader.readUInt8()
        guard version == currentVersion else { throw ScanCacheError.unsupportedVersion(version) }

        let totalFiles = try reader.readUInt32()
        let totalDirectories = try reader.readUInt32()
        _ = try reader.readInt64() // legacy totalSize field; derived from root.size now
        let scanDuration = try reader.readFloat64()
        let scanDate = Date(timeIntervalSinceReferenceDate: try reader.readFloat64())

        let root = try readNode(from: &reader)

        guard reader.offset == reader.byteCount else {
            throw ScanCacheError.trailingData
        }

        return DirectoryScanResult(
            root: root,
            totalFiles: Int(totalFiles),
            totalDirectories: Int(totalDirectories),
            scanDuration: scanDuration,
            scanDate: scanDate
        )
    }

    private static func readNode(from reader: inout BinaryReader) throws -> FileNode {
        let nameLength = try reader.readUInt16()
        let nameBytes = try reader.readBytes(Int(nameLength))
        guard let name = String(bytes: nameBytes, encoding: .utf8) else {
            throw ScanCacheError.corruptedString
        }

        let size = try reader.readInt64()
        let flags = try reader.readUInt8()

        let isDirectory = flags & 1 != 0
        let statusBits = (flags >> 1) & 0b11
        let status: NodeStatus
        switch statusBits {
        case 0b00: status = .normal
        case 0b01: status = .readOnly
        case 0b10:
            let reasonLen = try reader.readUInt16()
            let reasonBytes = try reader.readBytes(Int(reasonLen))
            guard let reason = String(bytes: reasonBytes, encoding: .utf8) else {
                throw ScanCacheError.corruptedString
            }
            status = .skipped(reason: reason)
        case 0b11: status = .inaccessible
        default:
            // Unreachable from well-formed data since statusBits is masked to two
            // bits and all four values are handled above. If we ever reach this,
            // either the flags byte is corrupt or a future NodeStatus case was
            // added to the encoder without updating this decoder. Throwing here
            // lets DirectoryScanner.loadFromDisk discard the cache and fall back
            // to a fresh scan instead of silently producing a deletable node.
            throw ScanCacheError.corruptedFlags(flags)
        }

        let childCount = try reader.readUInt32()
        guard childCount <= maxChildCount else {
            throw ScanCacheError.childCountTooLarge(childCount)
        }

        if !isDirectory {
            // Ignore any child entries on a leaf (should be 0 in a valid file).
            return FileNode.file(name: name, size: size, status: status)
        }

        var children: [FileNode] = []
        if childCount > 0 {
            children.reserveCapacity(Int(childCount))
            for _ in 0..<childCount {
                children.append(try readNode(from: &reader))
            }
        }
        return FileNode.directory(
            name: name,
            children: children,
            size: size,
            status: status
        )
    }
}

// MARK: - Binary Reader

private struct BinaryReader {
    let data: Data
    var offset: Int = 0

    var byteCount: Int { data.count }

    init(data: Data) {
        // Force `startIndex == 0` so offset-based access is unambiguous. `Data`
        // slices inherit the parent's indices, and `loadUnaligned(fromByteOffset:)`
        // is 0-based on the underlying buffer — mixing the two would read the
        // wrong bytes on a sliced input.
        self.data = data.startIndex == 0 ? data : Data(data)
    }

    mutating func readBytes(_ count: Int) throws -> [UInt8] {
        guard count >= 0, offset + count <= data.count else {
            throw ScanCacheError.truncatedData
        }
        let bytes = data.withUnsafeBytes { buffer in
            Array(buffer[offset..<offset + count])
        }
        offset += count
        return bytes
    }

    mutating func readUInt8() throws -> UInt8 {
        guard offset + 1 <= data.count else { throw ScanCacheError.truncatedData }
        let value = data.withUnsafeBytes { buffer in
            buffer.load(fromByteOffset: offset, as: UInt8.self)
        }
        offset += 1
        return value
    }

    // Note: `loadUnaligned` is required because `Data.withUnsafeBytes` does not
    // guarantee natural alignment of the underlying storage — using `load` here
    // crashes on arm64 when the offset is not a multiple of the type's stride.
    // See commit 925e7d2. Do not "simplify" these to `load`.
    mutating func readUInt16() throws -> UInt16 {
        guard offset + 2 <= data.count else { throw ScanCacheError.truncatedData }
        let value = data.withUnsafeBytes { buffer in
            buffer.loadUnaligned(fromByteOffset: offset, as: UInt16.self)
        }
        offset += 2
        return UInt16(littleEndian: value)
    }

    mutating func readUInt32() throws -> UInt32 {
        guard offset + 4 <= data.count else { throw ScanCacheError.truncatedData }
        let value = data.withUnsafeBytes { buffer in
            buffer.loadUnaligned(fromByteOffset: offset, as: UInt32.self)
        }
        offset += 4
        return UInt32(littleEndian: value)
    }

    mutating func readInt64() throws -> Int64 {
        guard offset + 8 <= data.count else { throw ScanCacheError.truncatedData }
        let value = data.withUnsafeBytes { buffer in
            buffer.loadUnaligned(fromByteOffset: offset, as: Int64.self)
        }
        offset += 8
        return Int64(littleEndian: value)
    }

    mutating func readFloat64() throws -> Float64 {
        guard offset + 8 <= data.count else { throw ScanCacheError.truncatedData }
        let bits = data.withUnsafeBytes { buffer in
            buffer.loadUnaligned(fromByteOffset: offset, as: UInt64.self)
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
