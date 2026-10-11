//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation
import JellyfinAPI

struct DeepLink: Equatable {

    enum Destination: Equatable {
        case item(id: String)
        case play(id: String)

        // TODO: able to launch library by ID without item pre-retrieval?
//        case library(id: String)
    }

    let serverID: String
    let userID: String
    let destination: Destination

    init?(_ url: URL) {
        guard let match = url.absoluteString.wholeMatch(
            of: /^(?:alphane|swiftfin|jellyfin):\/\/(?<serverID>[A-Za-z0-9-]+)\/(?<userID>[A-Za-z0-9-]+)\/(?<destinationType>item|library|play)\/(?<destinationID>[A-Za-z0-9-]+)\/?$/
        ) else { return nil }

        self.serverID = String(match.output.serverID)
        self.userID = String(match.output.userID)

        let id = String(match.output.destinationID)
        self.destination = match.output.destinationType == "play" ? .play(id: id) : .item(id: id)
    }

    @MainActor
    func route(userSession: UserSession) async throws -> NavigationRoute {
        switch destination {
        case let .item(id):
            return .item(id: id)
        case let .play(id):
            let item = try await BaseItemDto(id: id).getFullItem(userSession: userSession)
            guard let provider = item.getPlaybackItemProvider(userSession: userSession) else {
                throw DeepLinkError.unplayableItem(id)
            }
            let queue: (any MediaPlayerQueue)? = item.type == .episode ? EpisodeMediaPlayerQueue(episode: item) : nil
            return .videoPlayer(provider: provider, queue: queue)
//        case let .library(id):
//            let library = try await getItem(id: id, userSession: session)
//            return .library(viewModel: ItemLibraryViewModel(parent: library))
        }
    }
}

enum DeepLinkError: Error {
    case missingServer(String)
    case missingUser(String)
    case unplayableItem(String)
}
