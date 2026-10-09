//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Defaults
import Foundation
import JellyfinAPI

struct NextUpLibrary: BaseItemKindLibrary {

    struct Environment: WithDefaultValue {
        var enableRewatching: Bool
        var maxNextUp: TimeInterval

        static let `default`: Self = .init(
            enableRewatching: Defaults[.Customization.Home.resumeNextUp],
            maxNextUp: Defaults[.Customization.Home.maxNextUp]
        )
    }

    let libraryItemTypes: [BaseItemKind] = [.episode]
    let parent: TitledLibraryParent = .init(displayTitle: L10n.nextUp, id: "next-up")

    func retrievePage(
        environment: Environment,
        pageState: LibraryPageState
    ) async throws -> [BaseItemDto] {
        var parameters = Paths.GetNextUpParameters()
        parameters.enableRewatching = environment.enableRewatching
        parameters.enableUserData = true
        parameters.fields = PosterSubtitleField.itemFields
        parameters.limit = pageState.pageSize
        parameters.startIndex = pageState.pageOffset

        if environment.maxNextUp > 0 {
            parameters.nextUpDateCutoff = Date.now.addingTimeInterval(-environment.maxNextUp)
        }

        let request = Paths.getNextUp(parameters: parameters)
        let response = try await pageState.userSession.client.send(request)

        let suggestions = response.value.items ?? []
        guard !environment.enableRewatching else { return suggestions }

        let client = pageState.userSession.client
        let userID = pageState.userSession.user.id

        return await withTaskGroup(of: (Int, BaseItemDto).self) { group in
            for (index, suggestion) in suggestions.enumerated() where suggestion.indexNumber == nil {
                group.addTask {
                    let continuation = try? await Self.resolveUnnumberedEpisode(
                        suggestion,
                        userID: userID,
                        client: client
                    )
                    return (index, continuation ?? suggestion)
                }
            }

            var items = suggestions
            for await (index, item) in group {
                items[index] = item
            }
            return items
        }
    }

    private static func resolveUnnumberedEpisode(
        _ suggestion: BaseItemDto,
        userID: String,
        client: JellyfinClient
    ) async throws -> BaseItemDto {
        guard let seriesID = suggestion.seriesID else { return suggestion }

        var parameters = Paths.GetItemsParameters()
        parameters.userID = userID
        parameters.parentID = seriesID
        parameters.includeItemTypes = [.episode]
        parameters.isRecursive = true
        parameters.isPlayed = true
        parameters.isMissing = false
        parameters.enableUserData = true
        parameters.limit = 1
        parameters.sortBy = [.datePlayed]
        parameters.sortOrder = [.descending]

        let playedResponse = try await client.send(Paths.getItems(parameters: parameters))
        guard let lastPlayedEpisode = playedResponse.value.items?.first,
              lastPlayedEpisode.id != nil
        else { return suggestion }

        let episodes = try await EpisodeContinuation.episodes(around: lastPlayedEpisode, userID: userID, client: client)

        return EpisodeContinuation.nextUpItem(
            serverSuggestion: suggestion,
            lastPlayedEpisode: lastPlayedEpisode,
            adjacentEpisodes: episodes
        )
    }

    func onItemUserDataChanged(
        viewModel: PagingLibraryViewModel<NextUpLibrary>,
        userData: UserItemDataDto
    ) {
        guard let itemID = userData.itemID else { return }

        if viewModel.elements.contains(where: { $0.id == itemID }) {
            viewModel.scheduleRefreshForItemUserData(minimumInterval: 3)
            return
        }

        let hasResumePosition = (userData.playbackPositionTicks ?? 0) > 0
        let canAffectMembership = hasResumePosition || userData.isPlayed != nil

        guard canAffectMembership else { return }

        viewModel.scheduleRefreshForItemUserData(minimumInterval: 30)
    }
}
