//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Defaults
import SwiftUI

// TODO: Add scrollTargetLayout and scrollTargetBehavior to the scroll views.
// TODO: isCompact determination by available width

struct ItemView: View {

    enum Component {

        static let header = "itemView-header"
        static let menu = "itemView-menu"
        static let play = "itemView-play"
        static let nextEpisode = "itemView-next-episode"
        static let description = "itemView-description"
        static let parent = "itemView-parent"
        static let seasons = "itemView-seasons"
    }

    @Default(.Customization.itemViewType)
    private var itemViewType

    @Router
    private var router

    private var buttonConfiguration = ItemActionButtons.Configuration()

    @State
    private var contentSize: CGSize = .zero

    @State
    private var shouldStartPlayback: Bool

    #if os(tvOS)
    @FocusState
    private var initialFocusSelection: String?
    @State
    private var shouldRestorePlaybackFocus = false

    private var preferredPlaybackFocus: String {
        provider.shouldFocusNextEpisode ? Component.nextEpisode : Component.play
    }
    #endif

    @StateObject
    private var focusCoordinator = FocusCoordinator(initial: Component.play)
    @StateObject
    private var provider: ItemContentGroupProvider
    @StateObject
    private var viewModel: ContentGroupViewModel<ItemContentGroupProvider>
    @StateObject
    private var deleteViewModel: ItemEditorViewModel

    init(provider: ItemContentGroupProvider, startPlayback: Bool = false) {
        self._shouldStartPlayback = State(initialValue: startPlayback)
        self._provider = StateObject(wrappedValue: provider)
        self._viewModel = StateObject(wrappedValue: ContentGroupViewModel(provider: provider))
        self._deleteViewModel = StateObject(wrappedValue: ItemEditorViewModel(item: provider.item))
    }

    private func contentDidLoad() {
        #if os(tvOS)
        if shouldRestorePlaybackFocus {
            shouldRestorePlaybackFocus = false
            initialFocusSelection = preferredPlaybackFocus
        }
        #endif

        guard shouldStartPlayback, let playbackProvider = provider.mediaPlayerItemProvider else { return }
        // Keep the following episode's details beneath its player, so finishing
        // it returns to the correct episode and offers its own Next action.
        shouldStartPlayback = false
        let queue: (any MediaPlayerQueue)? = playbackProvider.item.type == .episode
            ? EpisodeMediaPlayerQueue(episode: playbackProvider.item) : nil
        router.route(to: .videoPlayer(provider: playbackProvider, queue: queue))
    }

    private var isCompact: Bool {
        #if os(tvOS)
        false
        #else
        contentSize.width < 600
        #endif
    }

    private var isEnhanced: Bool {
        switch itemViewType {
        case .enhanced:
            guard provider.item.backdropImageTags?.isNotEmpty == true else {
                return false
            }

            if isCompact {
                return provider.item.type == .movie
                    || provider.item.type == .series
                    || provider.item.type == .program
                    || provider.item.type == .liveTvProgram
            }

            return provider.item.type != .person && provider.item.type != .season

        case .simple:
            return false
        }
    }

    private var contentGroups: [any ContentGroup] {
        #if os(tvOS)
        let header: any ContentGroup = TVDetailHeaderContentGroup(provider: provider)
        #else
        let header: any ContentGroup = switch (isEnhanced, isCompact) {
        case (true, true):
            CompactEnhancedHeaderContentGroup(provider: provider)
        case (true, false):
            RegularEnhancedHeaderContentGroup(provider: provider)
        case (false, true):
            CompactSimpleHeaderContentGroup(provider: provider)
        case (false, false):
            RegularSimpleHeaderContentGroup(provider: provider)
        }

        #endif
        return [header] + viewModel.groups
    }

    @ViewBuilder
    private func contentGroupScrollView(
        isEnhanced: Bool = false
    ) -> some View {
        ContentGroupScrollView(
            provider: provider,
            groups: contentGroups,
            isEnhanced: isEnhanced
        )
    }

    @ViewBuilder
    private var blurredNavigationBarScrollView: some View {
        BlurredNavigationBarScrollView(groups: contentGroups)
    }

    @ViewBuilder
    private var content: some View {
        Group {
            #if os(tvOS)
            // Panorama owns the full viewport even when an episode inherits its
            // series backdrop instead of having its own backdrop image tags.
            if provider.item.type == .person || provider.item.type == .season {
                contentGroupScrollView()
            } else {
                TVDetailPage(provider: provider, groups: viewModel.groups, preferredPlaybackFocus: preferredPlaybackFocus)
            }
            #else
            switch (isEnhanced, isCompact) {
            case (true, true):
                blurredNavigationBarScrollView

            case (true, false):
                InlinePlatformView {
                    blurredNavigationBarScrollView
                } tvOSView: {
                    contentGroupScrollView(isEnhanced: true)
                }

            default:
                contentGroupScrollView()
            }
            #endif
        }
        .navigationTitle(provider.item.displayTitle)
    }

    var body: some View {
        let (_, overflow, menu) = buttonConfiguration.resolvedButtons(for: provider)

        ZStack {
            switch viewModel.state {
            case .content:
                content
            case .error:
                viewModel.error.map(ErrorView.init)
            case .initial, .refreshing:
                ProgressView()
            }
        }
        .trackingSize($contentSize)
        .animation(.linear(duration: 0.2), value: viewModel.state)
        .animation(.linear(duration: 0.2), value: viewModel.background.states)
        .toolbarTitleDisplayMode(.inline)
        .refreshable {
            viewModel.background.refresh()
        }
        .onFirstAppear {
            viewModel.refresh()
        }
        .sinceLastDisappear { _ in
            viewModel.refreshIfPendingChanges()
        }
        .environmentObject(focusCoordinator)
        #if os(tvOS)
        .defaultFocus($initialFocusSelection, preferredPlaybackFocus, priority: .userInitiated)
        .environment(\.initialFocusSelection, $initialFocusSelection)
        #endif
        .confirmationDialog(
            L10n.deleteItemConfirmationMessage,
            isPresented: $provider.isPresentingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button(
                L10n.confirm,
                role: .destructive,
                action: deleteViewModel.delete
            )

            Button(L10n.cancel, role: .cancel) {}
        }
        .onChange(of: provider.$item.value == nil) { _, isUnavailable in
            if isUnavailable {
                router.dismiss()
            }
        }
        .onNotification(.didSendStopReport) { report in
            guard provider.prepareForPlaybackStop(report) else { return }
            // Rebuild the header and navigation after final progress settles.
            #if os(tvOS)
            shouldRestorePlaybackFocus = true
            #endif
            viewModel.refresh()
        }
        .onChange(of: viewModel.state) { _, state in
            if state == .content {
                contentDidLoad()
            }
        }
        .errorMessage($deleteViewModel.error)
        .errorMessage($provider.actionError)
        #if os(tvOS)
        .toolbarVisibility(.hidden, for: .navigationBar)
        #else
        .navigationBarMenuButton(
            isLoading: viewModel.background.is(.refreshing),
            isHidden: overflow.isEmpty && menu.isEmpty
        ) {
            ItemActionButtons.MenuContent(
                provider: provider,
                buttons: overflow,
                menuButtons: menu
            )
        }
        #endif
    }
}
