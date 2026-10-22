import Foundation
import zlib

@main
struct GzipDecompressorTests {
    static func main() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("kairos-gzip-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        let archive = directory.appendingPathComponent("kernel.gz")
        let payload = Data((0..<131_073).map { UInt8(truncatingIfNeeded: $0) })
        let valid = try gzip(payload, at: archive)

        try expect(try decompress(valid, at: archive) == payload, "ordinary archive")
        let empty = try gzip(Data(), at: archive)
        try expect(try decompress(empty, at: archive).isEmpty, "valid empty archive")
        try expectInvalid(Data(), at: archive, "empty input")
        try expectInvalid(payload, at: archive, "plain file")
        try expectInvalid(Data(valid.prefix(5)), at: archive, "truncated gzip header")
        try expectInvalid(Data(valid.prefix(valid.count / 2)), at: archive, "truncated DEFLATE stream")
        try expectInvalid(Data(valid.dropLast(8)), at: archive, "missing gzip trailer")
        try expectInvalid(Data(valid.dropLast(1)), at: archive, "partial gzip trailer")

        var badCRC = valid
        badCRC[badCRC.count - 8] ^= 1
        try expectInvalid(badCRC, at: archive, "incorrect CRC32")
        var badSize = valid
        badSize[badSize.count - 4] ^= 1
        try expectInvalid(badSize, at: archive, "incorrect ISIZE")

        var named = valid
        named[3] |= 0x08
        named.insert(contentsOf: Array("mihomo".utf8) + [0], at: 10)
        try expect(try decompress(named, at: archive) == payload, "optional filename")
        try expectInvalid(Data(named.prefix(13)), at: archive, "unterminated optional filename")
        try expect(try decompress(valid + valid, at: archive) == payload + payload, "concatenated gzip members")
        try expectInvalid(valid + badCRC, at: archive, "corrupt second member")

        // The old decoder silently returned only 50 MiB for this input.
        let large = Data(repeating: 0x41, count: 50 * 1024 * 1024 + 4097)
        let largeArchive = try gzip(large, at: archive)
        try expect(try decompress(largeArchive, at: archive) == large, "archive exceeding 50 MiB")
        print("GzipDecompressor: 15 checks passed")
    }

    private static func decompress(_ data: Data, at url: URL) throws -> Data {
        try data.write(to: url)
        return try GzipDecompressor.decompress(at: url)
    }

    private static func expectInvalid(_ data: Data, at url: URL, _ name: String) throws {
        do {
            _ = try decompress(data, at: url)
        } catch GzipDecompressor.DecompressionError.invalidArchive {
            return
        }
        throw Failure(message: "Accepted invalid archive: \(name)")
    }

    private static func expect(_ condition: Bool, _ name: String) throws {
        if !condition { throw Failure(message: name) }
    }

    private static func gzip(_ data: Data, at url: URL) throws -> Data {
        guard let archive = gzopen(url.path, "wb") else { throw Failure(message: "Cannot create fixture") }
        let written: Int32 = data.withUnsafeBytes { bytes in
            gzwrite(archive, bytes.baseAddress, UInt32(bytes.count))
        }
        let closed = gzclose(archive)
        try expect(written == data.count && closed == Z_OK, "gzip fixture creation")
        return try Data(contentsOf: url)
    }

    private struct Failure: Error {
        let message: String
    }
}
