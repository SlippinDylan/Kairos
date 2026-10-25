import Foundation

// A delegate belongs to one download attempt; closing it drains in-flight progress delivery.
nonisolated final class MihomoDownloadProgressDelegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let deliveryQueue = DispatchQueue(label: "Kairos.MihomoDownloadProgress")
    private let queueKey = DispatchSpecificKey<Bool>()
    private let handler: @Sendable (Double?) -> Void
    nonisolated(unsafe) private var isActive = true

    init(handler: @escaping @Sendable (Double?) -> Void) {
        self.handler = handler
        super.init()
        deliveryQueue.setSpecific(key: queueKey, value: true)
    }

    func start() {
        deliver(nil)
    }

    func finish() {
        onDeliveryQueue { isActive = false }
    }

    func complete() {
        onDeliveryQueue {
            guard isActive else { return }
            isActive = false
            handler(1)
        }
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        guard totalBytesExpectedToWrite > 0 else {
            deliver(nil)
            return
        }
        deliver(min(max(Double(totalBytesWritten) / Double(totalBytesExpectedToWrite), 0), 1))
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        // The async download API owns the temporary-file handoff.
    }

    private func deliver(_ progress: Double?) {
        onDeliveryQueue {
            guard isActive else { return }
            handler(progress)
        }
    }

    private func onDeliveryQueue(_ body: () -> Void) {
        if DispatchQueue.getSpecific(key: queueKey) == true {
            body()
        } else {
            deliveryQueue.sync(execute: body)
        }
    }
}
