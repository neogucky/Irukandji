//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation

struct ServerAddress {

    let candidates: [URL]

    init(_ address: String) throws {
        let address = address.trimmingCharacters(in: .whitespacesAndNewlines.union(.objectReplacement))
        let prefixes = address.contains("://") ? [""] : ["https://", "http://"]
        let formattedAddress = address.trimmingCharacters(in: ["/"])

        guard formattedAddress.isNotEmpty else {
            throw ErrorMessage(L10n.invalidURL)
        }

        candidates = try prefixes.map { prefix in
            guard let components = URLComponents(string: prefix + formattedAddress),
                  let scheme = components.scheme?.lowercased(),
                  ["https", "http"].contains(scheme),
                  let host = components.host,
                  host.isNotEmpty,
                  host.rangeOfCharacter(from: .whitespacesAndNewlines) == nil,
                  components.port.map({ (1 ... 65535).contains($0) }) ?? true,
                  let url = components.url
            else {
                throw ErrorMessage(L10n.invalidURL)
            }

            return url.normalizedServerConnectionURL ?? url
        }
    }

    @MainActor
    func resolve<Value>(using request: (URL) async throws -> Value) async throws -> (url: URL, value: Value) {
        var lastError: any Error = ErrorMessage(L10n.invalidURL)

        for url in candidates {
            try Task.checkCancellation()

            do {
                let value = try await request(url)
                try Task.checkCancellation()
                return (url, value)
            } catch {
                try Task.checkCancellation()

                // Cancelling a connection must not start the next probe.
                if error is CancellationError || (error as? URLError)?.code == .cancelled {
                    throw error
                }

                lastError = error
            }
        }

        throw lastError
    }
}
