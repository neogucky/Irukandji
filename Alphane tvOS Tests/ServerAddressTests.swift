//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation
import JellyfinAPI
@testable import Alphane
import XCTest

@MainActor
final class ServerAddressTests: XCTestCase {

    func testBareAddressesPreservePortsAndServerPaths() throws {
        let cases = [
            ("192.168.1.20:8096", "192.168.1.20:8096"),
            ("jellyfin.local", "jellyfin.local"),
            ("localhost:8096", "localhost:8096"),
            (" \u{FFFC}MEDIA.example:8096/jellyfin/\u{FFFC}\n", "media.example:8096/jellyfin"),
            ("[2001:db8::1]:8096/jellyfin", "[2001:db8::1]:8096/jellyfin"),
        ]

        for (input, expected) in cases {
            let address = try ServerAddress(input)
            XCTAssertEqual(address.candidates.map(\.absoluteString), ["https://" + expected, "http://" + expected])
        }
    }

    func testExplicitSchemesAreRespected() throws {
        for scheme in ["http", "https"] {
            let address = try ServerAddress(" \(scheme.uppercased())://MEDIA.example:8443/jellyfin/ ")
            XCTAssertEqual(address.candidates.map(\.absoluteString), ["\(scheme)://media.example:8443/jellyfin"])
        }
    }

    func testInvalidAddressesAreRejectedBeforeProbing() {
        for input in ["", " \n", "http://", "https:///", "ftp://media.example", "bad host:8096", "media.example:65536"] {
            XCTAssertThrowsError(try ServerAddress(input), input)
        }
    }

    func testHTTPSIsPreferredWhenBothSchemesCouldWork() async throws {
        let address = try ServerAddress("media.example/jellyfin")
        var attempts: [URL] = []
        let result = try await address.resolve { url in
            attempts.append(url)
            return "Jellyfin"
        }

        XCTAssertEqual(attempts.map(\.scheme), ["https"])
        XCTAssertEqual(result.url.absoluteString, "https://media.example/jellyfin")
        XCTAssertEqual(result.value, "Jellyfin")
    }

    func testHTTPOnlyServerFallsBackAndKeepsTheSuccessfulURL() async throws {
        let address = try ServerAddress("192.168.1.20:8096/jellyfin")
        var attempts: [URL] = []
        let result = try await address.resolve { url in
            attempts.append(url)
            if url.scheme == "https" {
                throw URLError(.secureConnectionFailed)
            }
            return "Jellyfin"
        }

        XCTAssertEqual(attempts, address.candidates)
        XCTAssertEqual(result.url.absoluteString, "http://192.168.1.20:8096/jellyfin")
        XCTAssertEqual(result.value, "Jellyfin")
    }

    func testInvalidHTTPSResponseCanFallBackToValidJellyfinAPI() async throws {
        let address = try ServerAddress("media.example")
        let result = try await address.resolve { url in
            let data = url.scheme == "https"
                ? Data("<html>Landing page</html>".utf8)
                : Data(#"{"ServerName":"Test server","Id":"test-server"}"#.utf8)
            return try JSONDecoder().decode(PublicSystemInfo.self, from: data)
        }

        XCTAssertEqual(result.url.scheme, "http")
        XCTAssertEqual(result.value.serverName, "Test server")
        XCTAssertEqual(result.value.id, "test-server")
    }

    func testExplicitHTTPSFailureDoesNotFallBackToHTTP() async throws {
        let address = try ServerAddress("https://media.example")
        var attempts: [URL] = []

        do {
            _ = try await address.resolve { url in
                attempts.append(url)
                throw URLError(.serverCertificateUntrusted)
            }
            XCTFail("An explicit HTTPS failure should be reported")
        } catch {
            XCTAssertEqual((error as? URLError)?.code, .serverCertificateUntrusted)
        }

        XCTAssertEqual(attempts.map(\.scheme), ["https"])
    }

    func testAllFailedProbesReportTheLastError() async throws {
        let address = try ServerAddress("media.example")
        var attempts: [URL] = []

        do {
            _ = try await address.resolve { url in
                attempts.append(url)
                throw URLError(url.scheme == "https" ? .secureConnectionFailed : .cannotConnectToHost)
            }
            XCTFail("Connection failures should be reported")
        } catch {
            XCTAssertEqual((error as? URLError)?.code, .cannotConnectToHost)
        }

        XCTAssertEqual(attempts, address.candidates)
    }

    func testCancellationErrorsDoNotStartHTTPProbe() async throws {
        for cancellation in [CancellationError() as any Error, URLError(.cancelled)] {
            let address = try ServerAddress("media.example")
            var attempts: [URL] = []

            do {
                _ = try await address.resolve { url in
                    attempts.append(url)
                    throw cancellation
                }
                XCTFail("Cancelled connections should stop")
            } catch {
                XCTAssertTrue(error is CancellationError || (error as? URLError)?.code == .cancelled)
            }

            XCTAssertEqual(attempts.map(\.scheme), ["https"])
        }
    }

    func testCancellingAnActiveProbeDoesNotStartAnotherOrReturnSuccess() async throws {
        let address = try ServerAddress("media.example")
        let started = expectation(description: "HTTPS probe started")
        var attempts: [URL] = []
        var continuation: CheckedContinuation<String, Never>?
        let task = Task {
            try await address.resolve { url in
                attempts.append(url)
                return await withCheckedContinuation {
                    continuation = $0
                    started.fulfill()
                }
            }
        }
        await fulfillment(of: [started], timeout: 2)
        task.cancel()
        continuation?.resume(returning: "Jellyfin")

        do {
            _ = try await task.value
            XCTFail("Cancellation should prevent saving even a successful response")
        } catch {
            XCTAssertTrue(error is CancellationError)
        }

        XCTAssertEqual(attempts.map(\.scheme), ["https"])
    }
}
