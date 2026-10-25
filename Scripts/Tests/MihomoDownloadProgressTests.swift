import Foundation

enum AppLogger {
    nonisolated static func debug(_ message: String) {}
    nonisolated static func info(_ message: String) {}
    nonisolated static func warning(_ message: String) {}
    nonisolated static func error(_ message: String) {}
}

private nonisolated final class ProgressRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [Double?] = []

    func record(_ progress: Double?) { lock.withLock { values.append(progress) } }
    var snapshot: [Double?] { lock.withLock { values } }
}

@main
struct MihomoDownloadProgressTests {
    static func main() throws {
        for releaseName in ["null", "\"Named release\""] {
            let json = "[{\"tag_name\":\"v0.9.0\",\"name\":\(releaseName),\"prerelease\":true,\"assets\":[]}]"
            let releases = try JSONDecoder().decode([MihomoDownloadService.GitHubRelease].self, from: Data(json.utf8))
            precondition(releases.count == 1 && releases[0].tagName == "v0.9.0",
                "Optional, unused release titles cannot block valid GitHub releases")
        }
        let session = URLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }
        guard let url = URL(string: "https://fixture.invalid/kernel.gz") else { fatalError("Invalid fixture URL") }
        // The task remains suspended; only native delegate events are injected below.
        let task = session.downloadTask(with: url)

        let recorder = ProgressRecorder()
        let delegate = MihomoDownloadProgressDelegate { recorder.record($0) }
        delegate.start()
        delegate.urlSession(session, downloadTask: task, didWriteData: 25, totalBytesWritten: 25, totalBytesExpectedToWrite: 100)
        delegate.urlSession(session, downloadTask: task, didWriteData: 25, totalBytesWritten: 50, totalBytesExpectedToWrite: 100)
        delegate.urlSession(session, downloadTask: task, didWriteData: 10, totalBytesWritten: 60, totalBytesExpectedToWrite: NSURLSessionTransferSizeUnknown)
        delegate.urlSession(session, downloadTask: task, didWriteData: 10, totalBytesWritten: 70, totalBytesExpectedToWrite: 0)
        delegate.complete()
        delegate.urlSession(session, downloadTask: task, didWriteData: 5, totalBytesWritten: 75, totalBytesExpectedToWrite: 100)
        delegate.complete()
        precondition(recorder.snapshot == [nil, 0.25, 0.5, nil, nil, 1], "Use cumulative bytes; unknown size stays indeterminate, and completion closes progress")

        let retryRecorder = ProgressRecorder()
        let firstAttempt = MihomoDownloadProgressDelegate { retryRecorder.record($0) }
        firstAttempt.start()
        firstAttempt.urlSession(session, downloadTask: task, didWriteData: 80, totalBytesWritten: 80, totalBytesExpectedToWrite: 100)
        firstAttempt.finish()
        let retry = MihomoDownloadProgressDelegate { retryRecorder.record($0) }
        retry.start()
        firstAttempt.urlSession(session, downloadTask: task, didWriteData: 10, totalBytesWritten: 90, totalBytesExpectedToWrite: 100)
        retry.urlSession(session, downloadTask: task, didWriteData: 20, totalBytesWritten: 20, totalBytesExpectedToWrite: 100)
        retry.finish()
        precondition(retryRecorder.snapshot == [nil, 0.8, nil, 0.2], "A retry resets progress and cannot receive late events from the failed attempt")

        let concurrentRecorder = ProgressRecorder()
        let concurrent = MihomoDownloadProgressDelegate { concurrentRecorder.record($0) }
        concurrent.start()
        let workers = DispatchGroup()
        for _ in 0..<8 {
            workers.enter()
            DispatchQueue.global().async {
                for written in 1...200 {
                    concurrent.urlSession(session, downloadTask: task, didWriteData: 1, totalBytesWritten: Int64(written), totalBytesExpectedToWrite: 200)
                }
                workers.leave()
            }
        }
        concurrent.finish()
        let countAfterFinish = concurrentRecorder.snapshot.count
        workers.wait()
        precondition(concurrentRecorder.snapshot.count == countAfterFinish, "Closing drains in-flight delivery and excludes subsequent callbacks")
        print("Mihomo download progress, unknown lengths, retry reset and late callback checks passed (no downloads)")
    }
}
