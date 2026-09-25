import Foundation
import CryptoKit
import ImageIO

struct RicePack {
    let manifest: RiceManifest
    let files: [String: Data]

    static let licenseText = "MIT License\n\nCopyright (c) 2026 Marginally Better Apps\n\nPermission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the Software), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, subject to inclusion of this notice. THE SOFTWARE IS PROVIDED AS IS, WITHOUT WARRANTY OF ANY KIND.\n"

    static func read(_ archive: Data) throws -> RicePack {
        guard archive.count <= RiceLimits.archiveBytes else { throw RiceValidationError.invalid("Archive is too large") }
        let entries = try StoredZIP.read(archive)
        guard let manifestData = entries["manifest.json"], manifestData.count <= RiceLimits.manifestBytes else { throw RiceValidationError.invalid("Manifest missing or too large") }
        try StrictJSON.checkDuplicateKeys(manifestData)
        let manifest = try JSONDecoder().decode(RiceManifest.self, from: manifestData)
        try RiceValidator.validate(manifest)
        guard RiceValidator.safePath(manifest.license), manifest.license.hasPrefix("LICENSES/"), entries[manifest.license] != nil else { throw RiceValidationError.invalid("License file missing") }
        let expected = Set(["manifest.json", manifest.license] + manifest.assets.map(\.path) + manifest.assets.map(\.license))
        guard Set(entries.keys) == expected else { throw RiceValidationError.invalid("Archive contains undeclared files") }
        for asset in manifest.assets {
            guard let data = entries[asset.path], data.count == asset.length,
                  SHA256.hash(data: data).map({ String(format: "%02x", $0) }).joined() == asset.sha256.lowercased()
            else { throw RiceValidationError.invalid("Asset hash or length mismatch") }
            try checkImage(data, mime: asset.mimeType)
        }
        return RicePack(manifest: manifest, files: entries)
    }

    func archive() throws -> Data {
        try RiceValidator.validate(manifest)
        var content = files
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        content["manifest.json"] = try encoder.encode(manifest)
        let archive = try StoredZIP.write(content)
        _ = try Self.read(archive)
        return archive
    }

    static func builtIn(_ theme: RiceManifest) -> RicePack {
        RicePack(manifest: theme, files: [theme.license: Data(licenseText.utf8)])
    }

    private static func checkImage(_ data: Data, mime: String) throws {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil), CGImageSourceGetCount(source) == 1,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0, width <= 8192, height <= 8192,
              width * height <= 16_000_000,
              CGImageSourceCreateImageAtIndex(source, 0, nil) != nil
        else { throw RiceValidationError.invalid("Unsupported or oversized image") }
        let type = CGImageSourceGetType(source) as String?
        let allowed = ["image/png": "public.png", "image/jpeg": "public.jpeg", "image/webp": "org.webmproject.webp"]
        guard type == allowed[mime] else { throw RiceValidationError.invalid("Image type does not match declaration") }
    }
}

private enum StoredZIP {
    static func read(_ data: Data) throws -> [String: Data] {
        let bytes = [UInt8](data)
        guard bytes.count >= 22 else { throw RiceValidationError.invalid("Invalid ZIP") }
        let searchStart = max(0, bytes.count - 65_557)
        guard let end = stride(from: bytes.count - 22, through: searchStart, by: -1).first(where: { u32(bytes, $0) == 0x06054b50 }) else { throw RiceValidationError.invalid("ZIP directory missing") }
        let count = Int(u16(bytes, end + 10))
        let directoryLength = Int(u32(bytes, end + 12))
        let directoryOffset = Int(u32(bytes, end + 16))
        guard count <= RiceLimits.entries, u16(bytes, end + 4) == 0, u16(bytes, end + 6) == 0,
              u16(bytes, end + 8) == UInt16(count), u16(bytes, end + 20) == 0,
              directoryOffset <= end, directoryLength <= end - directoryOffset,
              directoryOffset + directoryLength == end else { throw RiceValidationError.invalid("Unsupported ZIP structure") }
        var cursor = directoryOffset
        var result: [String: Data] = [:]
        var normalized: Set<String> = []
        var expanded = 0
        for _ in 0..<count {
            guard cursor + 46 <= end, u32(bytes, cursor) == 0x02014b50 else { throw RiceValidationError.invalid("Invalid ZIP entry") }
            let flags = u16(bytes, cursor + 8)
            let method = u16(bytes, cursor + 10)
            let crc = u32(bytes, cursor + 16)
            let compressed = Int(u32(bytes, cursor + 20))
            let length = Int(u32(bytes, cursor + 24))
            let nameLength = Int(u16(bytes, cursor + 28))
            let extraLength = Int(u16(bytes, cursor + 30))
            let commentLength = Int(u16(bytes, cursor + 32))
            let externalAttributes = u32(bytes, cursor + 38)
            let localOffset = Int(u32(bytes, cursor + 42))
            let next = cursor + 46 + nameLength + extraLength + commentLength
            guard next <= end, [UInt16(0), UInt16(0x0800)].contains(flags), method == 0, compressed == length,
                  length <= RiceLimits.entryBytes, nameLength > 0,
                  [UInt32(0), UInt32(0x8000)].contains((externalAttributes >> 16) & 0xF000),
                  let name = String(bytes: bytes[(cursor + 46)..<(cursor + 46 + nameLength)], encoding: .utf8),
                  RiceValidator.safePath(name), !name.lowercased().hasSuffix(".zip"),
                  !name.lowercased().hasSuffix(".ricepack") else { throw RiceValidationError.invalid("Unsupported ZIP member") }
            let key = name.precomposedStringWithCanonicalMapping.lowercased()
            guard normalized.insert(key).inserted else { throw RiceValidationError.invalid("Duplicate archive path") }
            guard localOffset + 30 <= directoryOffset, u32(bytes, localOffset) == 0x04034b50,
                  u16(bytes, localOffset + 6) == flags, u16(bytes, localOffset + 8) == method,
                  u32(bytes, localOffset + 14) == crc,
                  u32(bytes, localOffset + 18) == UInt32(compressed),
                  u32(bytes, localOffset + 22) == UInt32(length) else { throw RiceValidationError.invalid("Inconsistent ZIP metadata") }
            let localNameLength = Int(u16(bytes, localOffset + 26))
            let localExtraLength = Int(u16(bytes, localOffset + 28))
            let contentStart = localOffset + 30 + localNameLength + localExtraLength
            guard contentStart <= directoryOffset, length <= directoryOffset - contentStart,
                  bytes[(localOffset + 30)..<(localOffset + 30 + localNameLength)].elementsEqual(bytes[(cursor + 46)..<(cursor + 46 + nameLength)]) else { throw RiceValidationError.invalid("Inconsistent ZIP path") }
            let content = Data(bytes[contentStart..<(contentStart + length)])
            guard CRC32.hash(content) == crc else { throw RiceValidationError.invalid("ZIP checksum mismatch") }
            expanded += length
            guard expanded <= RiceLimits.expandedBytes else { throw RiceValidationError.invalid("Archive expands beyond limit") }
            result[name] = content
            cursor = next
        }
        guard cursor == end else { throw RiceValidationError.invalid("Unexpected ZIP directory data") }
        return result
    }

    static func write(_ entries: [String: Data]) throws -> Data {
        var result = Data()
        var directory = Data()
        for name in entries.keys.sorted() {
            guard RiceValidator.safePath(name), let value = entries[name], value.count <= RiceLimits.entryBytes else { throw RiceValidationError.invalid("Invalid export member") }
            let nameBytes = Data(name.utf8)
            let crc = CRC32.hash(value)
            let offset = result.count
            result.appendLE(UInt32(0x04034b50)); result.appendLE(UInt16(20)); result.appendLE(UInt16(0x0800)); result.appendLE(UInt16(0))
            result.appendLE(UInt16(0)); result.appendLE(UInt16(0)); result.appendLE(crc)
            result.appendLE(UInt32(value.count)); result.appendLE(UInt32(value.count)); result.appendLE(UInt16(nameBytes.count)); result.appendLE(UInt16(0))
            result.append(nameBytes); result.append(value)
            directory.appendLE(UInt32(0x02014b50)); directory.appendLE(UInt16(20)); directory.appendLE(UInt16(20)); directory.appendLE(UInt16(0x0800)); directory.appendLE(UInt16(0))
            directory.appendLE(UInt16(0)); directory.appendLE(UInt16(0)); directory.appendLE(crc)
            directory.appendLE(UInt32(value.count)); directory.appendLE(UInt32(value.count)); directory.appendLE(UInt16(nameBytes.count))
            directory.appendLE(UInt16(0)); directory.appendLE(UInt16(0)); directory.appendLE(UInt16(0)); directory.appendLE(UInt16(0))
            directory.appendLE(UInt32(0)); directory.appendLE(UInt32(offset)); directory.append(nameBytes)
        }
        let directoryOffset = result.count
        result.append(directory)
        result.appendLE(UInt32(0x06054b50)); result.appendLE(UInt16(0)); result.appendLE(UInt16(0))
        result.appendLE(UInt16(entries.count)); result.appendLE(UInt16(entries.count)); result.appendLE(UInt32(directory.count))
        result.appendLE(UInt32(directoryOffset)); result.appendLE(UInt16(0))
        return result
    }

    private static func u16(_ b: [UInt8], _ p: Int) -> UInt16 { UInt16(b[p]) | UInt16(b[p + 1]) << 8 }
    private static func u32(_ b: [UInt8], _ p: Int) -> UInt32 { UInt32(b[p]) | UInt32(b[p + 1]) << 8 | UInt32(b[p + 2]) << 16 | UInt32(b[p + 3]) << 24 }
}

private enum CRC32 {
    static func hash(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFFFFFF
        for byte in data {
            crc ^= UInt32(byte)
            for _ in 0..<8 { crc = (crc >> 1) ^ ((crc & 1) == 1 ? 0xEDB88320 : 0) }
        }
        return ~crc
    }
}

private extension Data {
    mutating func appendLE(_ value: UInt16) { append(UInt8(value & 255)); append(UInt8(value >> 8)) }
    mutating func appendLE(_ value: UInt32) { append(UInt8(value & 255)); append(UInt8((value >> 8) & 255)); append(UInt8((value >> 16) & 255)); append(UInt8(value >> 24)) }
}
