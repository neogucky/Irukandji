//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Combine
import CryptoKit
import Foundation
import JellyfinAPI
import Logging
import TVServices
import UIKit

@MainActor
final class TopShelfService: UserSessionService {
    struct Candidate {
        let item: BaseItemDto
        let contextTitle: String
    }

    private var session: UserSession?
    private var refreshTask: Task<Void, Never>?
    private var cancellables: Set<AnyCancellable> = []
    private let logger = Logger.swiftfin()

    func willStart(userSession: UserSession) async {
        session = userSession
        do {
            try TopShelfStorage.shared?.activate(serverID: userSession.server.id, userID: userSession.user.id)
            TVTopShelfContentProvider.topShelfContentDidChange()
        } catch { logger.error("Unable to prepare Top Shelf cache: \(error.localizedDescription)") }
    }

    func didStart(userSession: UserSession) {
        Publishers.Merge3(
            Notifications[.didSendStopReport].publisher.map { _ in () },
            Notifications[.itemUserDataDidChange].publisher.map { _ in () },
            Notifications[.didRequestGlobalRefresh].publisher
        )
        .merge(with: Notifications[.didChangeServerConnection].publisher.map { _ in () })
        .debounce(for: .milliseconds(750), scheduler: RunLoop.main)
        .sink { [weak self] in self?.scheduleRefresh() }
        .store(in: &cancellables)
        scheduleRefresh()
    }

    func willStop(userSession: UserSession) {
        refreshTask?.cancel()
        cancellables.removeAll()
        session = nil
    }

    private func scheduleRefresh() {
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in await self?.refresh() }
    }

    /// Resume entries win over Next Up, and one series occupies at most one slot.
    static func candidates(resume: [BaseItemDto], nextUp: [BaseItemDto], latest: [BaseItemDto]) -> [Candidate] {
        var seen: Set<String> = []
        var result: [Candidate] = []
        for (items, context) in [(resume, L10n.continue), (nextUp, L10n.nextUp), (latest, L10n.recentlyAdded)] {
            for item in items {
                guard let id = item.id, !id.isEmpty, !item.isMissing, !item.isUnaired,
                      [.movie, .episode, .video].contains(item.type), item.userData?.isPlayed != true else { continue }
                let key = item.type == .episode ? item.seriesID ?? id : id
                guard seen.insert(key).inserted else { continue }
                let contextTitle = item.type == .episode && item.seriesName != nil
                    ? "\(context) · \(item.seriesName!)" : context
                result.append(Candidate(item: item, contextTitle: contextTitle))
            }
        }
        return result
    }

    private func refresh() async {
        guard let session, let storage = TopShelfStorage.shared else { return }
        do {
            let page = LibraryPageState(pageOffset: 0, pageSize: 16, userSession: session)
            async let resume = ResumeItemsLibrary().retrievePage(environment: .default, pageState: page)
            async let next = NextUpLibrary().retrievePage(environment: .default, pageState: page)
            async let latest = latestItems(session: session)
            let candidates = try await Self.candidates(resume: resume, nextUp: next, latest: latest)
            try Task.checkCancellation()

            var entries: [TopShelfEntry] = []
            for candidate in candidates {
                try Task.checkCancellation()
                if let entry = await cachedEntry(candidate, session: session, storage: storage) { entries.append(entry) }
                if entries.count == 8 { break }
            }
            try Task.checkCancellation()
            try storage.write(TopShelfSnapshot(
                serverID: session.server.id, userID: session.user.id, updatedAt: .now, entries: entries
            ))
            TVTopShelfContentProvider.topShelfContentDidChange()
        } catch is CancellationError {
            return
        } catch {
            // Retain the last successful snapshot when the server is unreachable.
            logger.error("Unable to update Top Shelf: \(error.localizedDescription)")
        }
    }

    private func latestItems(session: UserSession) async throws -> [BaseItemDto] {
        var parameters = Paths.GetItemsParameters()
        parameters.userID = session.user.id
        parameters.includeItemTypes = [.movie, .episode]
        parameters.isRecursive = true
        parameters.isMissing = false
        parameters.isPlayed = false
        parameters.enableUserData = true
        parameters.fields = [.overview]
        parameters.sortBy = [.dateCreated]
        parameters.sortOrder = [.descending]
        parameters.limit = 24
        return try await session.client.send(Paths.getItems(parameters: parameters)).value.items ?? []
    }

    private func cachedEntry(_ candidate: Candidate, session: UserSession, storage: TopShelfStorage) async -> TopShelfEntry? {
        let item = candidate.item
        guard let id = item.id else { return nil }
        let sources = item.imageSources(for: .landscape, environment: .init(
            maxWidth: 1920, quality: 85, useParent: true, viewContext: [.isBackdrop]
        ))
        for source in sources {
            guard let sourceURL = source.url else { continue }
            let digest = SHA256.hash(data: Data("v2|\(session.server.id)|\(session.user.id)|\(sourceURL.absoluteString)|\(item.displayTitle)|\(candidate.contextTitle)".utf8))
            let fileName = digest.map { String(format: "%02x", $0) }.joined() + ".jpg"
            guard let file = storage.artworkURL(fileName: fileName) else { continue }
            if !FileManager.default.fileExists(atPath: file.path) {
                do {
                    var request = URLRequest(url: sourceURL, timeoutInterval: 8)
                    request.setValue(session.user.accessToken, forHTTPHeaderField: "X-Emby-Token")
                    let (data, response) = try await URLSession.shared.data(for: request)
                    try Task.checkCancellation()
                    guard (response as? HTTPURLResponse)?.statusCode == 200, let image = UIImage(data: data),
                          let jpeg = Self.backdropJPEG(image, title: item.displayTitle, contextTitle: candidate.contextTitle) else { continue }
                    try jpeg.write(to: file, options: .atomic)
                } catch is CancellationError { return nil }
                catch { continue }
            }
            return TopShelfEntry(
                itemID: id, title: item.displayTitle, contextTitle: candidate.contextTitle,
                summary: item.overview, duration: item.runtime?.seconds, artworkFileName: fileName
            )
        }
        return nil
    }

    private static func backdropJPEG(_ image: UIImage, title: String, contextTitle: String) -> Data? {
        guard image.size.width > 0, image.size.height > 0 else { return nil }
        let canvas = CGSize(width: 1920, height: 1080)
        let scale = max(canvas.width / image.size.width, canvas.height / image.size.height)
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let rendered = UIGraphicsImageRenderer(size: canvas, format: format).image { context in
            image.draw(in: CGRect(x: (canvas.width - size.width) / 2, y: (canvas.height - size.height) / 2, width: size.width, height: size.height))

            // Keep titles visible above the system's Play / More Info controls.
            // Some tvOS versions only display the summary and duration metadata.
            if let gradient = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: [UIColor.clear.cgColor, UIColor.black.withAlphaComponent(0.85).cgColor] as CFArray,
                locations: [0, 1]
            ) {
                context.cgContext.drawLinearGradient(
                    gradient, start: CGPoint(x: 0, y: 260), end: CGPoint(x: 0, y: 1080), options: []
                )
            }
            let paragraph = NSMutableParagraphStyle()
            paragraph.lineBreakMode = .byTruncatingTail
            (contextTitle as NSString).draw(in: CGRect(x: 88, y: 580, width: 1400, height: 40), withAttributes: [
                .font: UIFont.systemFont(ofSize: 28, weight: .medium),
                .foregroundColor: UIColor.white.withAlphaComponent(0.8),
                .paragraphStyle: paragraph
            ])
            (title as NSString).draw(in: CGRect(x: 88, y: 630, width: 1400, height: 156), withAttributes: [
                .font: UIFont.systemFont(ofSize: 64, weight: .semibold),
                .foregroundColor: UIColor.white,
                .paragraphStyle: paragraph
            ])
        }
        return rendered.jpegData(compressionQuality: 0.85)
    }
}
