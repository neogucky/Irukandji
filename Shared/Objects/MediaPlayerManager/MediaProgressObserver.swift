//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Combine
import Defaults
import Foundation
import JellyfinAPI

// TODO: respond properly to end of playback
//       - when item changes
// TODO: only send stop on manager stop, not per-item

class MediaProgressObserver: ViewModel, MediaPlayerObserver {

    weak var manager: MediaPlayerManager? {
        didSet {
            if let manager {
                setup(with: manager)
            }
        }
    }

    private let timer = PokeIntervalTimer()
    private var hasSentStart = false
    private var reportTask: Task<Void, Error>?
    private var item: MediaPlayerItem?
    private var lastPlaybackRequestStatus: MediaPlayerManager.PlaybackRequestStatus = .playing

    init(item: MediaPlayerItem) {
        self.item = item
        super.init()
    }

    private func enqueueReport(_ operation: @escaping @MainActor () async throws -> Void) {
        let previous = reportTask
        reportTask = Task {
            // A progress request from before Stop must finish before Stop is
            // sent, otherwise it can overwrite the final position.
            _ = await previous?.result
            try await operation()
        }
    }

    private func sendReport() {
        guard let item else { return }

        switch lastPlaybackRequestStatus {
        case .playing:
            if hasSentStart {
                sendProgressReport(for: item, seconds: manager?.seconds)
            } else {
                sendStartReport(for: item, seconds: manager?.seconds)
            }

        case .paused:
            sendProgressReport(for: item, seconds: manager?.seconds, isPaused: true)
        }
    }

    private func setup(with manager: MediaPlayerManager) {
        cancellables = []

        timer.sink { [weak self] in
            self?.sendReport()
            self?.timer.poke()
        }
        .store(in: &cancellables)

        manager.actions
            .sink { [weak self] in self?.didReceive(action: $0) }
            .store(in: &cancellables)

        manager.$playbackItem
            .sink { [weak self] in self?.playbackItemDidChange($0) }
            .store(in: &cancellables)

        manager.$playbackRequestStatus
            .sink { [weak self] in self?.playbackRequestStatusDidChange($0) }
            .store(in: &cancellables)

        Notifications[.applicationWillTerminate]
            .publisher
            .sink { [weak self] _ in self?.endPlaybackSession() }
            .store(in: &cancellables)
    }

    private func endPlaybackSession() {
        guard let item else { return }

        sendStopReport(for: item, seconds: manager?.seconds)
    }

    private func playbackItemDidChange(_ newItem: MediaPlayerItem?) {
        timer.poke()

        if let item, newItem !== item {
            endPlaybackSession()
            self.item = newItem
            self.hasSentStart = false
            sendReport()
        }
    }

    private func playbackRequestStatusDidChange(_ newStatus: MediaPlayerManager.PlaybackRequestStatus) {
        timer.poke()
        lastPlaybackRequestStatus = newStatus
    }

    // TODO: respond to error
    // TODO: respond properly to ended
    private func didReceive(action: MediaPlayerManager._Action) {
        switch action {
        case .stop:
            endPlaybackSession()
            timer.stop()
            cancellables = []
            item = nil

        default: ()
        }
    }

    private func sendStartReport(for item: MediaPlayerItem, seconds: Duration?) {

        #if DEBUG
        guard Defaults[.sendProgressReports] else { return }

        #endif

        enqueueReport {
            var info = PlaybackStateInfo()
            info.audioStreamIndex = item.selectedAudioStreamIndex
            info.itemID = item.baseItem.id
            info.liveStreamID = item.mediaSource.liveStreamID
            info.mediaSourceID = item.mediaSource.id
            info.playSessionID = item.playSessionID
            info.positionTicks = seconds?.ticks
            info.sessionID = item.playSessionID
            info.subtitleStreamIndex = item.selectedSubtitleStreamIndex

            let request = Paths.reportPlaybackStart(info)
            try await self.send(request)

            self.hasSentStart = true
        }
    }

    private func sendStopReport(for item: MediaPlayerItem, seconds: Duration?) {

        #if DEBUG
        guard Defaults[.sendProgressReports] else { return }

        #endif

        enqueueReport {
            var info = PlaybackStopInfo()
            info.itemID = item.baseItem.id
            info.liveStreamID = item.mediaSource.liveStreamID
            info.mediaSourceID = item.mediaSource.id
            info.playSessionID = item.playSessionID
            info.positionTicks = seconds?.ticks
            info.sessionID = item.playSessionID

            let request = Paths.reportPlaybackStopped(info)
            try await self.send(request)

            await self.settlePlaybackState(for: item.baseItem, stoppedAt: info.positionTicks)
            Notifications[.didSendStopReport].post(info)
        }
    }

    func settlePlaybackState(for item: BaseItemDto, stoppedAt positionTicks: Int?) async {
        guard PlaybackCompletion.reachedEnd(of: item, at: positionTicks), let userSession else { return }
        do {
            _ = try await PlaybackCompletion.refreshedItem(stoppedAt: positionTicks) {
                try await userSession.getFullItem(item).snapshot
            }
        } catch {
            logger.debug("Unable to read final playback state: \(error.localizedDescription)")
        }
    }

    func sendProgressReport(for item: MediaPlayerItem, seconds: Duration?, isPaused: Bool = false) {

        #if DEBUG
        guard Defaults[.sendProgressReports] else { return }

        #endif

        enqueueReport {
            var info = PlaybackStateInfo()
            info.audioStreamIndex = item.selectedAudioStreamIndex
            info.isPaused = isPaused
            info.itemID = item.baseItem.id
            info.liveStreamID = item.mediaSource.liveStreamID
            info.mediaSourceID = item.mediaSource.id
            info.playSessionID = item.playSessionID
            info.positionTicks = seconds?.ticks
            info.sessionID = item.playSessionID
            info.subtitleStreamIndex = item.selectedSubtitleStreamIndex

            let request = Paths.reportPlaybackProgress(info)
            try await self.send(request)
        }
    }
}
