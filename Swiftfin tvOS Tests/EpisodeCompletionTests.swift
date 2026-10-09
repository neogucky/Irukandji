//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Combine
import Defaults
import Get
import JellyfinAPI
@testable import Swiftfin
import SwiftUI
import XCTest

@MainActor
final class EpisodeCompletionTests: XCTestCase {

    func testStopWaitsForAnOlderInFlightProgressReport() async {
        let previous = Defaults[.sendProgressReports]
        Defaults[.sendProgressReports] = true
        defer { Defaults[.sendProgressReports] = previous }
        let progressStarted = expectation(description: "Older progress in flight")
        let stopStarted = expectation(description: "Final stop follows progress")
        let (manager, observer) = makePlaybackSession()
        observer.onProgressRequest = { progressStarted.fulfill() }
        observer.onStopRequest = { stopStarted.fulfill() }
        observer.sendProgressReport(for: manager.playbackItem!, seconds: .seconds(90))
        await fulfillment(of: [progressStarted], timeout: 2)
        await manager.stop()
        await Task.yield()
        XCTAssertNil(observer.stopInfo, "Stop must not race an older progress request")
        observer.completeProgressReport()
        await fulfillment(of: [stopStarted], timeout: 2)
        XCTAssertEqual(observer.stopInfo?.positionTicks, Duration.seconds(120).ticks)
        observer.completeStopReport()
    }

    func testHomeRefreshWaitsForFinalWatchedStateAfterAcknowledgement() async {
        let previous = Defaults[.sendProgressReports]
        Defaults[.sendProgressReports] = true
        defer { Defaults[.sendProgressReports] = previous }
        let stopStarted = expectation(description: "Stop report in flight")
        let settling = expectation(description: "Waiting for watched state")
        let refreshed = expectation(description: "Home can now refresh")
        var refreshCount = 0
        let subscription = Notifications[.didSendStopReport].publisher.sink { _ in
            refreshCount += 1
            refreshed.fulfill()
        }
        defer { subscription.cancel() }
        let (manager, observer) = makePlaybackSession()
        observer.onStopRequest = { stopStarted.fulfill() }
        observer.onSettlementRequest = { settling.fulfill() }
        await manager.stop()
        await fulfillment(of: [stopStarted], timeout: 2)
        observer.completeStopReport()
        await fulfillment(of: [settling], timeout: 2)
        XCTAssertEqual(refreshCount, 0)
        observer.completeSettlement()
        await fulfillment(of: [refreshed], timeout: 2)
        XCTAssertEqual(refreshCount, 1)
    }

    func testStopReportRefreshWaitsForServerAcknowledgement() async {
        let previousSendProgressReports = Defaults[.sendProgressReports]
        Defaults[.sendProgressReports] = true
        defer { Defaults[.sendProgressReports] = previousSendProgressReports }

        let reportStarted = expectation(description: "Stop report sent")
        let refreshReceived = expectation(description: "Playback refresh received")
        var refreshCount = 0
        let subscription = Notifications[.didSendStopReport].publisher.sink { _ in
            refreshCount += 1
            refreshReceived.fulfill()
        }
        defer { subscription.cancel() }

        let (manager, observer) = makePlaybackSession()
        observer.onStopRequest = { reportStarted.fulfill() }
        await manager.stop()
        await fulfillment(of: [reportStarted], timeout: 2)

        XCTAssertEqual(refreshCount, 0, "Fetching Next Up before acknowledgement would return stale progress")
        XCTAssertEqual(observer.stopInfo?.itemID, "episode")
        XCTAssertEqual(observer.stopInfo?.positionTicks, Duration.seconds(120).ticks)
        XCTAssertEqual(observer.stopInfo?.playSessionID, "session")

        observer.completeStopReport()
        await fulfillment(of: [refreshReceived], timeout: 2)
        XCTAssertEqual(refreshCount, 1)
    }

    func testFailedStopReportDoesNotAnnounceSavedProgress() async {
        let previousSendProgressReports = Defaults[.sendProgressReports]
        Defaults[.sendProgressReports] = true
        defer { Defaults[.sendProgressReports] = previousSendProgressReports }

        let reportStarted = expectation(description: "Stop report sent")
        let refreshReceived = expectation(description: "No refresh for unsaved progress")
        refreshReceived.isInverted = true
        let subscription = Notifications[.didSendStopReport].publisher.sink { _ in
            refreshReceived.fulfill()
        }
        defer { subscription.cancel() }

        let (manager, observer) = makePlaybackSession()
        observer.onStopRequest = { reportStarted.fulfill() }
        await manager.stop()
        await fulfillment(of: [reportStarted], timeout: 2)

        observer.completeStopReport(throwing: URLError(.cannotConnectToHost))
        await fulfillment(of: [refreshReceived], timeout: 0.2)
    }

    func testPlaybackReportRefreshesGroupsEvenAfterAnImmediateReturn() async {
        let groupViewModel = RecordingRefreshViewModel()
        let viewModel = ContentGroupViewModel(provider: RecordingProvider(viewModel: groupViewModel))
        await viewModel.refresh()
        XCTAssertEqual(groupViewModel.refreshCount, 1)

        viewModel.refreshIfNeeded(sinceLastDisappear: 0)
        await Task.yield()
        XCTAssertEqual(groupViewModel.refreshCount, 1)

        let refreshed = expectation(description: "Content refreshed after playback")
        groupViewModel.onRefresh = { refreshed.fulfill() }
        var report = PlaybackStopInfo()
        report.itemID = "episode"
        Notifications[.didSendStopReport].post(report)
        viewModel.refreshIfNeeded(sinceLastDisappear: 0)
        await fulfillment(of: [refreshed], timeout: 2)
        XCTAssertEqual(groupViewModel.refreshCount, 2)
    }

    func testNextEpisodeAtStartAndMiddleOfSeries() {
        let first = episode("first")
        let current = episode("current")
        let next = episode("next")

        XCTAssertEqual(ItemContentGroupProvider.nextEpisode(after: first, in: [first, current])?.id, current.id)
        XCTAssertEqual(ItemContentGroupProvider.nextEpisode(after: current, in: [first, current, next])?.id, next.id)
    }

    func testFinalEpisodeDoesNotReplayOrWrapAround() {
        let previous = episode("previous")
        let final = episode("final")

        XCTAssertNil(ItemContentGroupProvider.nextEpisode(after: final, in: [previous, final]))
        XCTAssertNil(ItemContentGroupProvider.nextEpisode(after: final, in: [final]))
        XCTAssertNil(ItemContentGroupProvider.nextEpisode(after: final, in: []))
        XCTAssertNil(ItemContentGroupProvider.nextEpisode(after: final, in: [previous]))
    }

    func testNextEpisodeCanCrossSeasonBoundary() {
        var finale = episode("season-one-finale")
        finale.parentIndexNumber = 1
        var premiere = episode("season-two-premiere")
        premiere.parentIndexNumber = 2

        XCTAssertEqual(ItemContentGroupProvider.nextEpisode(after: finale, in: [finale, premiere])?.id, premiere.id)
    }

    func testMissingEpisodeDoesNotOfferUnplayableNextAction() {
        let current = episode("current")
        var missing = episode("missing")
        missing.locationType = .virtual

        XCTAssertNil(ItemContentGroupProvider.nextEpisode(after: current, in: [current, missing]))
        XCTAssertNil(ItemContentGroupProvider.nextEpisode(after: current, in: [current, BaseItemDto(id: "series", type: .series)]))
    }

    private func episode(_ id: String) -> BaseItemDto {
        BaseItemDto(id: id, seriesID: "series", type: .episode)
    }

    private func makePlaybackSession() -> (MediaPlayerManager, RecordingProgressObserver) {
        var item = episode("episode")
        item.runTimeTicks = Duration.seconds(120).ticks
        let playbackItem = MediaPlayerItem(
            baseItem: item,
            mediaSource: MediaSourceInfo(id: "source"),
            playSessionID: "session",
            url: URL(string: "http://localhost/video")!,
            deviceProfile: DeviceProfile()
        )
        let observer = RecordingProgressObserver(item: playbackItem)
        playbackItem.observers = [observer]
        let manager = MediaPlayerManager(playbackItem: playbackItem)
        observer.manager = manager
        manager.seconds = .seconds(120)
        return (manager, observer)
    }
}

@MainActor
private final class RecordingProgressObserver: MediaProgressObserver {

    var stopInfo: PlaybackStopInfo?
    var onStopRequest: (() -> Void)?
    var onProgressRequest: (() -> Void)?
    var onSettlementRequest: (() -> Void)?
    private var settlementContinuation: CheckedContinuation<Void, Never>?
    private var progressContinuation: CheckedContinuation<Void, Error>?
    private var continuation: CheckedContinuation<Void, Error>?

    override func send(_ request: Request<Void>) async throws {
        if request.body is PlaybackStateInfo, let onProgressRequest {
            try await withCheckedThrowingContinuation {
                progressContinuation = $0
                onProgressRequest()
            }
            return
        }
        guard let info = request.body as? PlaybackStopInfo else { return }

        stopInfo = info
        try await withCheckedThrowingContinuation {
            continuation = $0
            onStopRequest?()
        }
    }

    override func settlePlaybackState(for item: BaseItemDto, stoppedAt positionTicks: Int?) async {
        guard let onSettlementRequest else { return }
        await withCheckedContinuation {
            settlementContinuation = $0
            onSettlementRequest()
        }
    }

    func completeSettlement() {
        settlementContinuation?.resume()
        settlementContinuation = nil
    }

    func completeProgressReport() {
        progressContinuation?.resume()
        progressContinuation = nil
        onProgressRequest = nil
    }

    func completeStopReport(throwing error: Error? = nil) {
        if let error {
            continuation?.resume(throwing: error)
        } else {
            continuation?.resume()
        }
        continuation = nil
    }
}

@MainActor
private final class RecordingRefreshViewModel: WithRefresh {

    var refreshCount = 0
    var onRefresh: (() -> Void)?

    var background: RecordingRefreshViewModel {
        get { self }
        set {}
    }

    func refresh() {
        recordRefresh()
    }

    func refresh() async {
        recordRefresh()
    }

    private func recordRefresh() {
        refreshCount += 1
        onRefresh?()
    }
}

private struct RecordingGroup: ContentGroup {
    let id = "test"
    let viewModel: RecordingRefreshViewModel

    func body(with viewModel: RecordingRefreshViewModel) -> some View {
        EmptyView()
    }
}

private struct RecordingProvider: ContentGroupProvider {
    let id = "test"
    let displayTitle = "Test"
    let viewModel: RecordingRefreshViewModel

    func makeGroups(environment: Swiftfin.Empty) async throws -> [any ContentGroup] {
        [RecordingGroup(viewModel: viewModel)]
    }
}
