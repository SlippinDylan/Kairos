import Foundation

enum AppLogger {
    nonisolated static func debug(_ message: String) {}
    nonisolated static func warning(_ message: String) {}
    nonisolated static func error(_ message: String) {}
}

private final class StreamingFixtureProtocol: URLProtocol {
    nonisolated(unsafe) static var reply: (URLRequest) throws -> (Int, Data) = { _ in fatalError("Missing fixture") }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let (status, data) = try Self.reply(request)
            guard let url = request.url,
                  let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil) else {
                fatalError("Invalid fixture response")
            }
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }
    override func stopLoading() {}
}

@main
@MainActor
struct StreamingDetectionTests {
    static func main() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StreamingFixtureProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let service = StreamingTestUseCase(session: session, userAgent: "fixture", dnsCheck: { _ in .native })

        StreamingFixtureProtocol.reply = { _ in (403, Data()) }
        let blocked = try await service.testNetflix(ip: "192.0.2.1")
        precondition(!blocked.available, "A genuine access restriction remains an unavailable result")
        StreamingFixtureProtocol.reply = { _ in (200, Data(#"{"country":"us"}"#.utf8)) }
        let available = try await service.testNetflix(ip: "192.0.2.1")
        precondition(available.available && available.region == "US")

        for status in [400, 404, 429, 503] {
            StreamingFixtureProtocol.reply = { _ in (status, Data()) }
            do {
                _ = try await service.testNetflix(ip: "192.0.2.1")
                preconditionFailure("Rate limits and provider outages cannot become an unavailable/unlocked result")
            } catch let error as URLError {
                precondition(error.code == .badServerResponse && error.localizedDescription.contains(String(status)))
            }
        }

        StreamingFixtureProtocol.reply = { _ in throw URLError(.timedOut) }
        do {
            _ = try await service.testNetflix(ip: "192.0.2.1")
            preconditionFailure("A transport timeout cannot become an unavailable or unlocked result")
        } catch let error as URLError {
            precondition(error.code == .timedOut)
        }
        let failedDNS = StreamingTestUseCase(session: session, userAgent: "fixture", dnsCheck: { _ in throw URLError(.cannotFindHost) })
        StreamingFixtureProtocol.reply = { _ in fatalError("A failed DNS check must not start an HTTP request") }
        do {
            _ = try await failedDNS.testNetflix(ip: "192.0.2.1")
            preconditionFailure("DNS errors must propagate")
        } catch let error as URLError {
            precondition(error.code == .cannotFindHost)
        }
        print("Streaming restriction and operational error checks passed (no network requests)")
    }
}
