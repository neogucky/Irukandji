//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation
import Network

enum ConnectionIssue: Equatable, Sendable {
    case network
    case internet
    case server

    var message: String {
        switch self {
        case .network:
            String(localized: "Your Apple TV has no network connection.")
        case .internet:
            String(localized: "Your Apple TV may not have internet access.")
        case .server:
            String(localized: "Could not connect to the server.")
        }
    }

    var suggestion: String {
        switch self {
        case .network:
            String(localized: "Check your Apple TV’s network settings.")
        case .internet:
            String(localized: "Check your router and internet connection.")
        case .server:
            String(localized: "Check that your Jellyfin server is available, or switch servers.")
        }
    }
}

/// Only explains failed requests; internet access is never a prerequisite for
/// loading Jellyfin, which may be available on the local network without it.
enum ConnectionDiagnostics {

    static func failureID(for error: Error) -> String {
        let failure = connectionError(in: error) ?? error as NSError
        return "\(failure.domain):\(failure.code):\(failure.localizedDescription)"
    }

    static func connectionError(in error: Error) -> NSError? {
        var current = error as NSError
        for _ in 0 ..< 8 {
            if current.domain == NSURLErrorDomain {
                switch URLError.Code(rawValue: current.code) {
                case .notConnectedToInternet, .networkConnectionLost, .timedOut,
                     .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed,
                     .secureConnectionFailed:
                    return current
                default:
                    return nil
                }
            }
            guard let underlying = current.userInfo[NSUnderlyingErrorKey] as? NSError else { return nil }

            current = underlying
        }
        return nil
    }

    static func diagnose(
        _ error: Error,
        networkAvailable: () async -> Bool? = { await NetworkPathProbe.current() },
        internetAvailable: () async -> Bool = { await probeInternet() }
    ) async -> ConnectionIssue? {
        guard connectionError(in: error) != nil, !Task.isCancelled else { return nil }

        let network = await networkAvailable()
        guard !Task.isCancelled else { return nil }

        // A missing path result is inconclusive, rather than proof of an outage.
        guard let network else { return nil }
        guard network else { return .network }

        let internet = await internetAvailable()
        guard !Task.isCancelled else { return nil }

        return internet ? .server : .internet
    }

    static func probeInternet(configuration: URLSessionConfiguration = .ephemeral) async -> Bool {
        let configuration = configuration.copy() as! URLSessionConfiguration
        configuration.timeoutIntervalForRequest = 3
        configuration.timeoutIntervalForResource = 4
        configuration.waitsForConnectivity = false
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCredentialStorage = nil
        configuration.httpAdditionalHeaders = nil
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }

        // Two small, unauthenticated HTTPS probes avoid relying on one page.
        // Never send Jellyfin credentials, identifiers or library information.
        return await withTaskGroup(of: Bool.self) { group in
            for address in ["https://www.apple.com/", "https://captive.apple.com/hotspot-detect.html"] {
                group.addTask {
                    var request = URLRequest(url: URL(string: address)!)
                    request.httpMethod = "HEAD"
                    request.cachePolicy = .reloadIgnoringLocalCacheData
                    do {
                        let (_, response) = try await session.data(for: request)
                        guard let response = response as? HTTPURLResponse,
                              let host = response.url?.host,
                              host == "apple.com" || host.hasSuffix(".apple.com") else { return false }

                        return (200 ..< 400).contains(response.statusCode)
                    } catch {
                        return false
                    }
                }
            }
            for await reachable in group where reachable {
                group.cancelAll()
                return true
            }
            return false
        }
    }
}

/// A one-shot network path check with a deadline and cancellation. A monitor
/// that hasn't reported yet must not leave the error screen checking forever.
private final class NetworkPathProbe: @unchecked Sendable {
    private let lock = NSLock()
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "Alphane.ConnectionDiagnostics")
    private var continuation: CheckedContinuation<Bool?, Never>?
    private var finished = false

    static func current() async -> Bool? {
        let probe = NetworkPathProbe()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { probe.start($0) }
        } onCancel: {
            probe.finish(nil)
        }
    }

    private func start(_ continuation: CheckedContinuation<Bool?, Never>) {
        lock.lock()
        guard !finished else {
            lock.unlock()
            continuation.resume(returning: nil)
            return
        }

        self.continuation = continuation
        monitor.pathUpdateHandler = { [weak self] path in
            self?.finish(path.status == .satisfied)
        }
        monitor.start(queue: queue)
        queue.asyncAfter(deadline: .now() + 1) { [weak self] in self?.finish(nil) }
        lock.unlock()
    }

    private func finish(_ available: Bool?) {
        lock.lock()
        guard !finished else {
            lock.unlock()
            return
        }

        finished = true
        let continuation = continuation
        self.continuation = nil
        lock.unlock()
        monitor.cancel()
        continuation?.resume(returning: available)
    }
}
