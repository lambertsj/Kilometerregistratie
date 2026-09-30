import Foundation

/// Leest de 'stored'-zips die `ZipArchive` schrijft, zodat de harness de
/// losse XML-onderdelen van een .xlsx als leesbare golden file kan
/// vergelijken in plaats van alleen de ruwe bytes.
enum ZipReader {
    static func entries(in data: Data) -> [(path: String, data: Data)] {
        var result: [(String, Data)] = []
        var index = data.startIndex

        while index + 30 <= data.endIndex {
            guard le32(data, at: index) == 0x04034b50 else { break }
            let compressedSize = Int(le32(data, at: index + 18))
            let nameLength = Int(le16(data, at: index + 26))
            let extraLength = Int(le16(data, at: index + 28))
            let nameStart = index + 30
            let dataStart = nameStart + nameLength + extraLength
            guard dataStart + compressedSize <= data.endIndex else { break }

            let path = String(decoding: data[nameStart..<(nameStart + nameLength)], as: UTF8.self)
            result.append((path, Data(data[dataStart..<(dataStart + compressedSize)])))
            index = dataStart + compressedSize
        }
        return result
    }

    static func entry(_ path: String, in data: Data) -> Data? {
        entries(in: data).first { $0.path == path }?.data
    }

    private static func le16(_ data: Data, at offset: Int) -> UInt16 {
        UInt16(data[offset]) | (UInt16(data[offset + 1]) << 8)
    }

    private static func le32(_ data: Data, at offset: Int) -> UInt32 {
        UInt32(data[offset]) | (UInt32(data[offset + 1]) << 8)
            | (UInt32(data[offset + 2]) << 16) | (UInt32(data[offset + 3]) << 24)
    }
}
