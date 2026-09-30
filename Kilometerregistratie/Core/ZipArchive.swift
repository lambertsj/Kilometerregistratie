import Foundation

/// Minimale ZIP-writer (alleen 'stored', geen compressie) — genoeg om een
/// geldig .xlsx-bestand te bouwen zonder externe dependencies. Een xlsx is
/// immers niets meer dan een zip met XML-bestanden; de bestanden zijn klein,
/// dus het ontbreken van compressie is geen bezwaar.
enum ZipArchive {
    struct Entry {
        var path: String
        var data: Data

        init(path: String, data: Data) {
            self.path = path
            self.data = data
        }
    }

    static func archive(entries: [Entry]) -> Data {
        var output = Data()
        var centralDirectory = Data()
        var offsets: [UInt32] = []

        for entry in entries {
            offsets.append(UInt32(output.count))
            let nameBytes = Array(entry.path.utf8)
            let crc = crc32(entry.data)
            let size = UInt32(entry.data.count)

            // Local file header.
            output.append(le32(0x04034b50))
            output.append(le16(20))         // version needed
            output.append(le16(0))          // flags
            output.append(le16(0))          // method: stored
            output.append(le16(0))          // mod time
            output.append(le16(0))          // mod date
            output.append(le32(crc))
            output.append(le32(size))       // compressed
            output.append(le32(size))       // uncompressed
            output.append(le16(UInt16(nameBytes.count)))
            output.append(le16(0))          // extra length
            output.append(contentsOf: nameBytes)
            output.append(entry.data)
        }

        for (index, entry) in entries.enumerated() {
            let nameBytes = Array(entry.path.utf8)
            let crc = crc32(entry.data)
            let size = UInt32(entry.data.count)

            centralDirectory.append(le32(0x02014b50))
            centralDirectory.append(le16(20))   // version made by
            centralDirectory.append(le16(20))   // version needed
            centralDirectory.append(le16(0))
            centralDirectory.append(le16(0))    // method
            centralDirectory.append(le16(0))
            centralDirectory.append(le16(0))
            centralDirectory.append(le32(crc))
            centralDirectory.append(le32(size))
            centralDirectory.append(le32(size))
            centralDirectory.append(le16(UInt16(nameBytes.count)))
            centralDirectory.append(le16(0))    // extra
            centralDirectory.append(le16(0))    // comment
            centralDirectory.append(le16(0))    // disk
            centralDirectory.append(le16(0))    // internal attrs
            centralDirectory.append(le32(0))    // external attrs
            centralDirectory.append(le32(offsets[index]))
            centralDirectory.append(contentsOf: nameBytes)
        }

        let centralOffset = UInt32(output.count)
        output.append(centralDirectory)

        // End of central directory.
        output.append(le32(0x06054b50))
        output.append(le16(0))
        output.append(le16(0))
        output.append(le16(UInt16(entries.count)))
        output.append(le16(UInt16(entries.count)))
        output.append(le32(UInt32(centralDirectory.count)))
        output.append(le32(centralOffset))
        output.append(le16(0))
        return output
    }

    // MARK: - Helpers

    private static func le16(_ value: UInt16) -> Data {
        withUnsafeBytes(of: value.littleEndian) { Data($0) }
    }

    private static func le32(_ value: UInt32) -> Data {
        withUnsafeBytes(of: value.littleEndian) { Data($0) }
    }

    private static let crcTable: [UInt32] = (0..<256).map { index in
        var crc = UInt32(index)
        for _ in 0..<8 {
            crc = (crc & 1) == 1 ? (crc >> 1) ^ 0xEDB88320 : crc >> 1
        }
        return crc
    }

    static func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFFFFFF
        for byte in data {
            crc = crcTable[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8)
        }
        return crc ^ 0xFFFFFFFF
    }
}
