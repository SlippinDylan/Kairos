import Darwin
import Foundation
import zlib

nonisolated enum GzipDecompressor {
    enum DecompressionError: Error {
        case invalidArchive
    }

    static func decompress(at url: URL) throws -> Data {
        guard let archive = gzopen(url.path, "rb") else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
        }
        defer { gzclose(archive) }

        // gzread also accepts plain files; only gzip archives are valid here.
        guard gzdirect(archive) == 0 else { throw DecompressionError.invalidArchive }

        var output = Data()
        var buffer = [UInt8](repeating: 0, count: 64 * 1024)
        while true {
            let count = buffer.withUnsafeMutableBytes { bytes in
                gzread(archive, bytes.baseAddress, UInt32(bytes.count))
            }
            guard count >= 0 else { throw DecompressionError.invalidArchive }
            if count == 0 { break }
            output.append(contentsOf: buffer.prefix(Int(count)))
        }

        // A truncated stream may return bytes and EOF rather than -1.
        // zlib checks each gzip member's CRC32 and uncompressed length.
        var status = Z_OK
        _ = gzerror(archive, &status)
        guard status == Z_OK else { throw DecompressionError.invalidArchive }
        return output
    }
}
