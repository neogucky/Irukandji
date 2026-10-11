//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation
import JellyfinAPI

/// A row is a query recipe, rather than a preloaded library or artwork collection.
struct HomeDiscoveryRow: Identifiable, Equatable {
    enum Sort: Equatable {
        case random
        case newest
        case rating
    }

    static let minimumItemCount = 6
    static let itemLimit = 24

    let id: String
    let title: String
    let itemType: BaseItemKind
    var genres: [String] = []
    var years: [Int] = []
    var sort: Sort = .random
    var isPlayed: Bool?
    var minimumRating: Double?
    var similarItemID: String?

    static let newMovies = Self(id: "home-new-movies", title: "New movies", itemType: .movie, sort: .newest)
    static let newShows = Self(id: "home-new-shows", title: "New shows", itemType: .series, sort: .newest)

    static var catalog: [Self] {
        let movieGenres = [
            ("action", "Action movies", "Action"),
            ("adventure", "Adventure movies", "Adventure"),
            ("comedy", "Comedy movies", "Comedy"),
            ("crime", "Crime movies", "Crime"),
            ("drama", "Drama movies", "Drama"),
            ("family", "Family movies", "Family"),
            ("fantasy", "Fantasy movies", "Fantasy"),
            ("history", "History on screen", "History"),
            ("horror", "Horror movies", "Horror"),
            ("mystery", "Mystery movies", "Mystery"),
            ("romance", "Romantic movies", "Romance"),
            ("science-fiction", "Science fiction movies", "Science Fiction"),
            ("thriller", "Thrillers", "Thriller"),
            ("war", "War movies", "War"),
            ("western", "Westerns", "Western"),
            ("animation", "Animated movies", "Animation"),
            ("documentary", "Documentaries", "Documentary"),
            ("music", "Music on screen", "Music")
        ]
        let showGenres = [
            ("action", "Action series", "Action"),
            ("adventure", "Adventure series", "Adventure"),
            ("comedy", "Comedy series", "Comedy"),
            ("crime", "Crime series", "Crime"),
            ("drama", "Drama series", "Drama"),
            ("mystery", "Mystery series", "Mystery"),
            ("science-fiction", "Science fiction series", "Science Fiction"),
            ("animation", "Animated series", "Animation"),
            ("documentary", "Documentary series", "Documentary")
        ]
        var rows = movieGenres.map { Self(id: "movies-\($0.0)", title: $0.1, itemType: .movie, genres: [$0.2]) }
        rows += showGenres.map { Self(id: "shows-\($0.0)", title: $0.1, itemType: .series, genres: [$0.2]) }
        for decade in [1970, 1980, 1990, 2000, 2010, 2020] {
            rows.append(Self(
                id: "movies-\(decade)s",
                title: "Movies from the \(decade)s",
                itemType: .movie,
                years: Array(decade ..< decade + 10)
            ))
            rows.append(Self(
                id: "shows-\(decade)s",
                title: "Series from the \(decade)s",
                itemType: .series,
                years: Array(decade ..< decade + 10)
            ))
        }
        rows += [
            Self(id: "movies-top-rated", title: "Highest rated movies", itemType: .movie, sort: .rating, minimumRating: 0.1),
            Self(id: "shows-top-rated", title: "Highest rated series", itemType: .series, sort: .rating, minimumRating: 0.1),
            Self(id: "movies-unwatched", title: "Movies you haven't seen", itemType: .movie, isPlayed: false),
            Self(
                id: "movies-unwatched-rated",
                title: "Highly rated discoveries",
                itemType: .movie,
                sort: .rating,
                isPlayed: false,
                minimumRating: 7
            )
        ]
        return rows
    }

    /// Episodes seed a series recommendation; repeated episodes never create repeated rows.
    static func similarRows(recentlyPlayed: [BaseItemDto]) -> [Self] {
        var seen = Set<String>()
        return recentlyPlayed.compactMap { item -> Self? in
            let id = item.type == .episode ? item.seriesID : item.id
            let name = item.type == .episode ? item.seriesName : item.name
            guard [.movie, .series, .episode].contains(item.type),
                  item.userData?.isPlayed == true,
                  let id, !id.isEmpty,
                  let name, !name.isEmpty,
                  seen.insert(id).inserted
            else { return nil }

            return Self(
                id: "similar-\(id)",
                title: "Because you watched \(name)",
                itemType: item.type == .movie ? .movie : .series,
                similarItemID: id
            )
        }
        .prefix(3)
        .map(\.self)
    }

    func parameters(userID: String, parentID: String?, limit: Int) -> Paths.GetItemsParameters {
        var parameters = Paths.GetItemsParameters()
        parameters.userID = userID
        parameters.parentID = parentID
        parameters.includeItemTypes = [itemType]
        parameters.isRecursive = true
        parameters.isMissing = false
        parameters.isUnaired = false
        parameters.enableUserData = true
        parameters.enableTotalRecordCount = false
        parameters.fields = PosterSubtitleField.itemFields + [.dateCreated]
        parameters.limit = limit
        parameters.genres = genres.isEmpty ? nil : genres
        parameters.years = years.isEmpty ? nil : years
        parameters.isPlayed = isPlayed
        parameters.minCommunityRating = minimumRating
        switch sort {
        case .random:
            parameters.sortBy = [.random]

        case .newest:
            parameters.sortBy = [.dateCreated, .sortName]
            parameters.sortOrder = [.descending]

        case .rating:
            parameters.sortBy = [.communityRating, .sortName]
            parameters.sortOrder = [.descending]
        }
        return parameters
    }

    func normalized(_ items: [BaseItemDto], now: Date = .now) -> [BaseItemDto] {
        var seen = Set<String>()
        return items.filter { item in
            guard let id = item.id, !id.isEmpty,
                  id != similarItemID,
                  item.type == itemType,
                  item.locationType != .virtual,
                  (item.premiereDate ?? .distantPast) <= now,
                  isPlayed == nil || (item.userData?.isPlayed ?? false) == isPlayed
            else { return false }

            return seen.insert(id).inserted
        }
    }
}
