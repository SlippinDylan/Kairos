import Foundation
import dnssd

// Unlike getaddrinfo, each DNS-SD query has an explicit cancellation handle.
nonisolated enum SystemDNSResolver {
    typealias Lookup = @Sendable (String, DNSServiceProtocol) async throws -> Bool

    static func hasAddress(
        for hostname: String,
        timeout: TimeInterval = 5,
        lookup: @escaping Lookup = { try await lookupAddress(hostname: $0, addressProtocol: $1) }
    ) async throws -> Bool {
        try await withTimeout(seconds: timeout) {
            try await withThrowingTaskGroup(of: Result<Bool, Error>.self) { group in
                defer { group.cancelAll() }
                // Keep family results separate: an absent AAAA record must not hide an A record.
                for addressProtocol in [kDNSServiceProtocol_IPv4, kDNSServiceProtocol_IPv6] {
                    group.addTask {
                        do {
                            return .success(try await lookup(hostname, DNSServiceProtocol(addressProtocol)))
                        } catch {
                            return .failure(error)
                        }
                    }
                }
                var failure: Error?
                for try await result in group {
                    try Task.checkCancellation()
                    switch result {
                    case .success(true): return true
                    case .success(false): break
                    case .failure(let error): failure = error
                    }
                }
                try Task.checkCancellation()
                if let failure { throw failure }
                return false
            }
        }
    }

    private static func lookupAddress(hostname: String, addressProtocol: DNSServiceProtocol) async throws -> Bool {
        let stream = AsyncThrowingStream<Bool, Error> { continuation in
            let query = AddressQuery(hostname: hostname, addressProtocol: addressProtocol, continuation: continuation)
            continuation.onTermination = { _ in query.cancel() }
            query.start()
        }
        for try await exists in stream { return exists }
        try Task.checkCancellation()
        throw URLError(.cannotFindHost)
    }

    private final class AddressQuery: @unchecked Sendable {
        private let queue = DispatchQueue(label: "Kairos.SystemDNSResolver")
        private let queueKey = DispatchSpecificKey<Bool>()
        private let hostname: String
        private let addressProtocol: DNSServiceProtocol
        // These properties are confined to queue, including cancellation and deallocation.
        nonisolated(unsafe) private var service: DNSServiceRef?
        nonisolated(unsafe) private var continuation: AsyncThrowingStream<Bool, Error>.Continuation?

        init(hostname: String, addressProtocol: DNSServiceProtocol, continuation: AsyncThrowingStream<Bool, Error>.Continuation) {
            self.hostname = hostname
            self.addressProtocol = addressProtocol
            self.continuation = continuation
            queue.setSpecific(key: queueKey, value: true)
        }

        func start() {
            queue.async { self.startOnQueue() }
        }

        func cancel() {
            // The consumer cannot finish cancellation before its native query has been released.
            if DispatchQueue.getSpecific(key: queueKey) == true {
                finish(.failure(CancellationError()))
            } else {
                queue.sync { self.finish(.failure(CancellationError())) }
            }
        }

        private func startOnQueue() {
            // Cancellation can be enqueued before registration.
            guard continuation != nil else { return }
            // NXDOMAIN is delivered only with ReturnIntermediates; CNAME referrals remain internal.
            let code = DNSServiceGetAddrInfo(
                &service, DNSServiceFlags(kDNSServiceFlagsReturnIntermediates), 0, addressProtocol, hostname,
                { _, flags, _, error, _, _, _, context in
                    guard let context else { return }
                    let query = Unmanaged<AddressQuery>.fromOpaque(context).takeUnretainedValue()
                    if error == kDNSServiceErr_NoSuchRecord {
                        query.finish(.success(false))
                    } else if error != kDNSServiceErr_NoError {
                        query.finish(.failure(NSError(domain: "DNSServiceError", code: Int(error), userInfo: [NSLocalizedDescriptionKey: "\(query.hostname): DNS error \(error)"])))
                    } else if flags & DNSServiceFlags(kDNSServiceFlagsAdd) != 0 {
                        query.finish(.success(true))
                    }
                },
                Unmanaged.passUnretained(self).toOpaque()
            )
            guard code == kDNSServiceErr_NoError else {
                finish(.failure(NSError(domain: "DNSServiceError", code: Int(code))))
                return
            }
            guard let service else {
                finish(.failure(URLError(.cannotFindHost)))
                return
            }
            let queueCode = DNSServiceSetDispatchQueue(service, queue)
            if queueCode != kDNSServiceErr_NoError {
                finish(.failure(NSError(domain: "DNSServiceError", code: Int(queueCode))))
            }
        }

        private func finish(_ result: Result<Bool, Error>) {
            guard let continuation else { return }
            self.continuation = nil
            if let service {
                DNSServiceRefDeallocate(service)
                self.service = nil
            }
            switch result {
            case .success(let exists):
                continuation.yield(exists)
                continuation.finish()
            case .failure(let error):
                continuation.finish(throwing: error)
            }
        }
    }
}
