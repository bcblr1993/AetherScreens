import Foundation
import Testing
@testable import AetherScreensCore

/// Exercise the production URLSession client without a real API token or tailnet.
@Suite(.serialized)
struct TailscaleClientTests {
    @Test func authenticatedRequestDecodesDevices() async throws {
        let fixture = Fixture([.http(200, Self.devices)])
        defer { fixture.close() }
        let devices = try await fixture.client.fetchDevices()
        #expect(devices.count == 1)
        let device = try #require(devices.first)
        #expect(device.hostname == "QA Mac")
        #expect(device.tailscaleIPv4 == "100.64.1.2")
        #expect(device.isMac && device.isOnline)
        let request = try #require(fixture.state.requests.first)
        #expect(request.url?.absoluteString == "https://api.tailscale.com/api/v2/tailnet/-/devices")
        #expect(request.httpMethod == "GET")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer synthetic-api-test-only")
        #expect(request.value(forHTTPHeaderField: "Accept") == "application/json")
    }

    @Test func deniedAuthenticationCanRecover() async throws {
        let fixture = Fixture([.http(401, Data()), .http(403, Data()), .http(200, Self.devices)])
        defer { fixture.close() }
        for _ in 0..<2 {
            do {
                _ = try await fixture.client.fetchDevices()
                Issue.record("Denied API authentication must fail")
            } catch TailscaleClient.TailscaleError.unauthorized {
                // The same client must remain usable after a denied request.
            }
        }
        #expect(try await fixture.client.fetchDevices().count == 1)
        #expect(fixture.state.requests.count == 3)
    }

    @Test func serverFailureAndMalformedDataCanRecover() async throws {
        let fixture = Fixture([.http(503, Data("temporarily unavailable".utf8)),
                               .http(200, Data("not JSON".utf8)), .http(200, Self.devices)])
        defer { fixture.close() }
        do {
            _ = try await fixture.client.fetchDevices()
            Issue.record("An unsuccessful server response must fail")
        } catch TailscaleClient.TailscaleError.httpError(let code, let message) {
            #expect(code == 503)
            #expect(message == "temporarily unavailable")
        }
        do {
            _ = try await fixture.client.fetchDevices()
            Issue.record("Malformed device data must fail")
        } catch TailscaleClient.TailscaleError.decodingError {
        }
        #expect(try await fixture.client.fetchDevices().count == 1)
    }

    @Test func networkFailureIsPropagatedAndNextRequestWorks() async throws {
        let fixture = Fixture([.failure(.networkConnectionLost), .http(200, Self.devices)])
        defer { fixture.close() }
        do {
            _ = try await fixture.client.fetchDevices()
            Issue.record("Network interruption must not return an empty success")
        } catch let error as URLError {
            #expect(error.code == .networkConnectionLost)
        }
        #expect(try await fixture.client.fetchDevices().count == 1)
    }

    @Test func emptyTailnetDeviceListIsValid() async throws {
        let fixture = Fixture([.http(200, Data(#"{"devices":[]}"#.utf8))])
        defer { fixture.close() }
        #expect(try await fixture.client.fetchDevices().isEmpty)
    }

    private static let devices = Data(#"{"devices":[{"id":"qa-node","name":"qa.tailnet.invalid","hostname":"QA Mac","addresses":["100.64.1.2"],"os":"macOS","connectedToControl":true}]}"#.utf8)

    private struct Fixture {
        let state: TailscaleHTTPState
        let session: URLSession
        let client: TailscaleClient
        init(_ replies: [TailscaleHTTPState.Reply]) {
            state = TailscaleHTTPState(replies)
            TailscaleTestURLProtocol.install(state)
            let configuration = URLSessionConfiguration.ephemeral
            configuration.protocolClasses = [TailscaleTestURLProtocol.self]
            session = URLSession(configuration: configuration)
            client = TailscaleClient(apiKey: "synthetic-api-test-only", tailnet: "", session: session)
        }
        func close() {
            session.invalidateAndCancel()
            TailscaleTestURLProtocol.install(nil)
        }
    }
}

private final class TailscaleHTTPState: @unchecked Sendable {
    enum Reply: Sendable { case http(Int, Data), failure(URLError.Code) }
    private let lock = NSLock()
    private var replies: [Reply]
    private var received: [URLRequest] = []
    init(_ replies: [Reply]) { self.replies = replies }
    var requests: [URLRequest] { lock.lock(); defer { lock.unlock() }; return received }
    func next(_ request: URLRequest) -> Reply {
        lock.lock(); defer { lock.unlock() }
        received.append(request)
        return replies.isEmpty ? .failure(.badServerResponse) : replies.removeFirst()
    }
}

private final class TailscaleTestURLProtocol: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var state: TailscaleHTTPState?
    static func install(_ state: TailscaleHTTPState?) {
        lock.lock(); defer { lock.unlock() }; self.state = state
    }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.lock.lock(); let state = Self.state; Self.lock.unlock()
        guard let state, let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL)); return
        }
        switch state.next(request) {
        case .failure(let code): client?.urlProtocol(self, didFailWithError: URLError(code))
        case .http(let code, let body):
            guard let response = HTTPURLResponse(url: url, statusCode: code, httpVersion: "HTTP/1.1", headerFields: nil) else {
                client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse)); return
            }
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: body)
            client?.urlProtocolDidFinishLoading(self)
        }
    }
    override func stopLoading() {}
}
