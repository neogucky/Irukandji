//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Combine
import JellyfinAPI
import SwiftUI

struct CinematicSelectionContentGroup: ContentGroup {

    let id = "cinematic-selection"
    let viewModel: CinematicSelectionContentGroupViewModel

    var _shouldBeResolved: Bool {
        viewModel.hasContent
    }

    init(
        resumeLibrary: ResumeItemsLibrary,
        recentlyAddedLibrary: RecentlyAddedLibrary
    ) {
        self.viewModel = CinematicSelectionContentGroupViewModel(
            resumeLibrary: resumeLibrary,
            recentlyAddedLibrary: recentlyAddedLibrary
        )
    }

    func body(with viewModel: CinematicSelectionContentGroupViewModel) -> some View {
        SelectionView(viewModel: viewModel)
    }

    private struct SelectionView: View {

        @ObservedObject
        var viewModel: CinematicSelectionContentGroupViewModel

        @Router
        private var router

        private func itemInformation(_ item: BaseItemDto) -> some View {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 12) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(AlphaneTheme.accent)
                        .frame(width: 3, height: 18)

                    Text(viewModel.hasResumeItems ? L10n.continue : L10n.recentlyAdded.localizedCapitalized)
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(AlphaneTheme.secondaryText)
                }

                Text(item.type == .episode ? item.seriesName ?? item.displayTitle : item.displayTitle)
                    .font(.system(size: 54, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(2, reservesSpace: true)

                DotHStack {
                    if item.type == .episode {
                        Text(item.displayTitle)
                    }
                    if let locator = item.seasonEpisodeLabel {
                        Text(locator)
                    }
                    if let year = item.productionYear, item.type != .episode {
                        Text(String(year))
                    }
                    if let runtime = item.runTimeLabel {
                        Text(runtime)
                    }
                }
                .font(.callout)
                .foregroundStyle(AlphaneTheme.secondaryText)
                .lineLimit(1)

                Text(item.overview ?? "")
                    .font(.footnote)
                    .foregroundStyle(AlphaneTheme.secondaryText)
                    .lineLimit(3, reservesSpace: true)
            }
            .frame(maxWidth: 900, alignment: .leading)
            .edgePadding(.horizontal)
        }

        var body: some View {
            let items = viewModel.hasResumeItems ? viewModel.resumeViewModel.elements.elements : viewModel.recentlyAddedViewModel.elements
                .elements

            CinematicItemSelector(
                items: items
            ) { item in
                router.route(to: .item(item: item))
            } topContent: { item in
                itemInformation(item)
            }
            .preference(
                key: ContentGroupCustomizationKey.self,
                value: .ignoreSafeAreaTop
            )
        }
    }
}

struct CinematicRecentlyAddedContentGroup: ContentGroup {

    let id = "cinematic-recently-added"
    let viewModel: CinematicSelectionContentGroupViewModel

    var _shouldBeResolved: Bool {
        viewModel.hasResumeItems && viewModel.recentlyAddedViewModel.elements.isNotEmpty
    }

    func body(with viewModel: CinematicSelectionContentGroupViewModel) -> some View {
        PosterHStackLibrarySection(
            viewModel: viewModel.recentlyAddedViewModel,
            group: viewModel.recentlyAddedGroup
        )
    }
}

final class CinematicSelectionContentGroupViewModel: ViewModel, WithRefresh {

    typealias Background = CinematicSelectionContentGroupViewModel

    let recentlyAddedGroup: PosterGroup<RecentlyAddedLibrary>
    let resumeViewModel: PagingLibraryViewModel<ResumeItemsLibrary>

    var recentlyAddedViewModel: PagingLibraryViewModel<RecentlyAddedLibrary> {
        recentlyAddedGroup.viewModel
    }

    var background: CinematicSelectionContentGroupViewModel {
        get { self }
        set {}
    }

    var hasResumeItems: Bool {
        resumeViewModel.elements.isNotEmpty
    }

    var hasContent: Bool {
        hasResumeItems || recentlyAddedViewModel.elements.isNotEmpty
    }

    init(
        resumeLibrary: ResumeItemsLibrary,
        recentlyAddedLibrary: RecentlyAddedLibrary
    ) {
        self.resumeViewModel = PagingLibraryViewModel(library: resumeLibrary, pageSize: 20)
        self.recentlyAddedGroup = PosterGroup(
            library: recentlyAddedLibrary,
            environment: .init(isHeaderButtonEnabled: false)
        )

        super.init()

        resumeViewModel.objectWillChange
            .merge(with: recentlyAddedViewModel.objectWillChange)
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
    }

    func refresh() {
        Task {
            await refresh()
        }
    }

    func refresh() async {
        async let resume: Void = resumeViewModel.refresh()
        async let recentlyAdded: Void = recentlyAddedViewModel.refresh()

        _ = await (resume, recentlyAdded)
    }
}
