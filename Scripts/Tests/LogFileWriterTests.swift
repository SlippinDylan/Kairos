import Foundation

@main
struct LogFileWriterTests {
    static func main() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("Kairos-LogRotation-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let url = directory.appendingPathComponent("rotation.log")
        let limit = 128
        let writer = LogFileWriter(
            fileURL: url,
            queue: DispatchQueue(label: "Kairos.LogRotationTests"),
            maxFileSize: limit
        )
        let lines = (0..<40).map { "entry-\($0)-abcdefghij\n" }
        for line in lines {
            writer.write(line, synchronize: true)
        }
        writer.close()

        let data = try Data(contentsOf: url)
        let output = String(decoding: data, as: UTF8.self)
        let retainedLines = output.split(separator: "\n").map(String.init)
        let expectedLines = lines.map { String($0.dropLast()) }
        precondition(data.count <= limit, "Repeated rotations must respect the size limit")
        precondition(!retainedLines.isEmpty, "Rotation must retain recent entries")
        precondition(retainedLines == Array(expectedLines.suffix(retainedLines.count)),
                     "Entries after rotation must be a complete suffix without duplicates or omissions")

        let oversizedURL = directory.appendingPathComponent("oversized.log")
        let oversizedWriter = LogFileWriter(
            fileURL: oversizedURL,
            queue: DispatchQueue(label: "Kairos.LogOversizedTests"),
            maxFileSize: limit
        )
        oversizedWriter.write(String(repeating: "x", count: limit * 2) + "\n", synchronize: true)
        oversizedWriter.write("after-rotation\n", synchronize: true)
        oversizedWriter.close()
        let oversizedOutput = try Data(contentsOf: oversizedURL)
        precondition(oversizedOutput.count <= limit, "Oversized entries must remain bounded")
        precondition(String(decoding: oversizedOutput, as: UTF8.self).hasSuffix("after-rotation\n"),
                     "The replacement handle must accept later entries")
        print("Log file rotation checks passed")
    }
}
