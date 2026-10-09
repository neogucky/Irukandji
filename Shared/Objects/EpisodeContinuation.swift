//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation
import JellyfinAPI

enum EpisodeContinuation {

    private static let episodeNumberPattern = try! NSRegularExpression(
        pattern: "^(?:S\\d{1,3}[ ._-]*E|Ep(?:isode)?[ ._-]*)(\\d{1,4})(?:\\D|$)",
        options: .caseInsensitive
    )

    /// Preserve the server's order unless a season has missing numbers and
    /// every episode has an unambiguous number in its metadata or filename.
    static func orderedEpisodes(_ episodes: [BaseItemDto]) -> [BaseItemDto] {
        var seasonOrder: [String] = []
        var seasons: [String: [BaseItemDto]] = [:]
        for episode in episodes {
            let season = episode.seasonID ?? episode.parentIndexNumber.map { "season-\($0)" } ?? "unknown"
            if seasons[season] == nil { seasonOrder.append(season) }
            seasons[season, default: []].append(episode)
        }

        return seasonOrder.flatMap { season in
            let items = seasons[season]!
            guard items.contains(where: { $0.indexNumber == nil }) else { return items }
            let positions = items.compactMap(episodeNumber)
            guard positions.count == items.count, Set(positions).count == items.count else { return items }
            return zip(items, positions).sorted { $0.1 < $1.1 }.map(\.0)
        }
    }

    private static func episodeNumber(_ episode: BaseItemDto) -> Int? {
        if let indexNumber = episode.indexNumber { return indexNumber }
        guard let name = episode.name,
              let match = episodeNumberPattern.firstMatch(in: name, range: NSRange(name.startIndex..., in: name)),
              let range = Range(match.range(at: 1), in: name)
        else { return nil }
        return Int(name[range])
    }

    static func episodes(
        around item: BaseItemDto,
        userID: String,
        client: JellyfinClient
    ) async throws -> [BaseItemDto] {
        guard let seriesID = item.seriesID else { return [] }
        var parameters = Paths.GetEpisodesParameters()
        parameters.userID = userID
        parameters.enableUserData = true
        parameters.fields = PosterSubtitleField.itemFields
        // An adjacent-only response has already discarded Ep10 when the
        // server alphabetically puts it before Ep9. Fetch the full list.
        if item.indexNumber != nil {
            parameters.adjacentTo = item.id
            parameters.limit = 3
        }
        let response = try await client.send(Paths.getEpisodes(seriesID: seriesID, parameters: parameters))
        return orderedEpisodes(response.value.items ?? [])
    }

    static func nextEpisode(after item: BaseItemDto, in episodes: [BaseItemDto]) -> BaseItemDto? {
        let episodes = orderedEpisodes(episodes)
        guard let itemID = item.id,
              let currentIndex = episodes.firstIndex(where: { $0.id == itemID }),
              episodes.indices.contains(currentIndex + 1)
        else { return nil }

        let nextEpisode = episodes[currentIndex + 1]
        return nextEpisode.type == .episode && nextEpisode.isPlayable ? nextEpisode : nil
    }

    /// Jellyfin's Next Up ordering can disagree with its episode-list ordering
    /// when episode numbers are missing. Prefer the unwatched episode directly
    /// after the latest watched episode, using numeric episode order.
    static func nextUpItem(
        serverSuggestion: BaseItemDto,
        lastPlayedEpisode: BaseItemDto,
        adjacentEpisodes: [BaseItemDto]
    ) -> BaseItemDto {
        guard serverSuggestion.type == .episode,
              serverSuggestion.indexNumber == nil,
              let seriesID = serverSuggestion.seriesID,
              lastPlayedEpisode.seriesID == seriesID,
              lastPlayedEpisode.userData?.isPlayed == true,
              let nextEpisode = nextEpisode(after: lastPlayedEpisode, in: adjacentEpisodes),
              nextEpisode.seriesID == seriesID,
              nextEpisode.userData?.isPlayed == false,
              (nextEpisode.userData?.playbackPositionTicks ?? 0) == 0
        else { return serverSuggestion }

        return nextEpisode.id == serverSuggestion.id ? serverSuggestion : nextEpisode
    }
}
