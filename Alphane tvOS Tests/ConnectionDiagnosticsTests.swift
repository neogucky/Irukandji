//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

@testable import Alphane
import Defaults
import Foundation
import XCTest

@MainActor
final class ConnectionDiagnosticsTests: XCTestCase {
    private let failure = URLError(.cannotConnectToHost)

    func testMissingNetworkDoesNotRunInternetProbe() async {
        let issue = await ConnectionDiagnostics.diagnose(failure, networkAvailable: { false }, internetAvailable: {
            XCTFail("Internet probes are unnecessary without a network path")
            return true
        })
        XCTAssertEqual(issue, .network)
    }

    func testAvailableNetworkButFailedInternetProbeSuggestsRouter() async {
        let issue = await ConnectionDiagnostics.diagnose(failure, networkAvailable: { true }, internetAvailable: { false })
        XCTAssertEqual(issue, .internet)
    }

    func testReachableInternetWithFailedServerRequestSuggestsServer() async {
        let issue = await ConnectionDiagnostics.diagnose(failure, networkAvailable: { true }, internetAvailable: { true })
        XCTAssertEqual(issue, .server)
    }

    func testAnInconclusivePathIsNotReportedAsANetworkOutage() async {
        let issue = await ConnectionDiagnostics.diagnose(failure, networkAvailable: { nil }, internetAvailable: {
            XCTFail("An inconclusive path should leave the original error intact")
            return false
        })
        XCTAssertNil(issue)
    }

    func testContentAndAuthenticationErrorsDoNotTriggerConnectivityChecks() async {
        for error: Error in [ErrorMessage("Sign in again."), URLError(.cancelled), URLError(.userAuthenticationRequired)] {
            let issue = await ConnectionDiagnostics.diagnose(error, networkAvailable: {
                XCTFail("This isn't a connectivity error")
                return false
            }, internetAvailable: { false })
            XCTAssertNil(issue)
        }
    }

    func testWrappedConnectionErrorsAreDiagnosed() async {
        let error = NSError(domain: "Request", code: 1, userInfo: [NSUnderlyingErrorKey: failure])
        let issue = await ConnectionDiagnostics.diagnose(error, networkAvailable: { false }, internetAvailable: { false })
        XCTAssertEqual(issue, .network)
        XCTAssertEqual(ErrorView<NSError>.displayMessage(for: error), "Could not connect to the server.")
    }

    func testOneSuccessfulHTTPSProbeIsEnough() async {
        ProbeProtocol.stub.configure { request in
            if request.url?.host == "www.apple.com" {
                return .failure(URLError(.cannotConnectToHost))
            }
            return .success(HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
        let reachable = await ConnectionDiagnostics.probeInternet(configuration: configuration())
        XCTAssertTrue(reachable)
        for request in ProbeProtocol.stub.requests {
            XCTAssertEqual(request.httpMethod, "HEAD")
            XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
            XCTAssertNil(request.value(forHTTPHeaderField: "X-Emby-Token"))
            XCTAssertEqual(request.url?.scheme, "https")
        }
    }

    func testFailedProbesDoNotReportInternetAccess() async {
        ProbeProtocol.stub.configure { _ in .failure(URLError(.timedOut)) }
        let reachable = await ConnectionDiagnostics.probeInternet(configuration: configuration())
        XCTAssertFalse(reachable)
        XCTAssertEqual(ProbeProtocol.stub.requests.count, 2)
    }

    func testCaptivePortalResponseIsNotReportedAsInternetAccess() async {
        ProbeProtocol.stub.configure { _ in
            .success(HTTPURLResponse(
                url: URL(string: "https://router.example/login")!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!)
        }
        let reachable = await ConnectionDiagnostics.probeInternet(configuration: configuration())
        XCTAssertFalse(reachable)
    }

    func testSwitchServerShowsProfilesFromAllSavedServers() async {
        let previous = Defaults[.selectUserServerSelection]
        defer { Defaults[.selectUserServerSelection] = previous }
        Defaults[.selectUserServerSelection] = .server(id: "previous")
        let manager = UserSessionManager()
        await manager.switchServer()
        XCTAssertEqual(Defaults[.selectUserServerSelection], .all)
    }

    private func configuration() -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ProbeProtocol.self]
        return configuration
    }
}

private final class ProbeProtocol: URLProtocol, @unchecked Sendable {
    static let stub = Stub()

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        switch Self.stub.respond(to: request) {
        case let .success(response):
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocolDidFinishLoading(self)

        case let .failure(error):
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}

    final class Stub: @unchecked Sendable {
        private let lock = NSLock()
        private var recorded: [URLRequest] = []
        private var response: @Sendable (URLRequest) -> Result<HTTPURLResponse, URLError> = { _ in
            .failure(URLError(.cannotConnectToHost))
        }

        var requests: [URLRequest] {
            lock.lock()
            defer { lock.unlock() }
            return recorded
        }

        func configure(_ response: @escaping @Sendable (URLRequest) -> Result<HTTPURLResponse, URLError>) {
            lock.lock()
            defer { lock.unlock() }
            self.response = response
            recorded = []
        }

        func respond(to request: URLRequest) -> Result<HTTPURLResponse, URLError> {
            lock.lock()
            defer { lock.unlock() }
            recorded.append(request)
            return response(request)
        }
    }
}
