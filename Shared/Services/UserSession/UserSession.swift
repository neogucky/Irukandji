//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Combine
import Foundation
import JellyfinAPI
import Pulse

final class UserSession {

    let server: ServerState
    let user: UserState

    @MainActor
    private(set) lazy var items = ItemStore()

    @MainActor
    var itemActionErrors = PassthroughSubject<Error, Never>()

    @MainActor
    var itemChanges: AnyCancellable?

    lazy var client: JellyfinClient = JellyfinClient(
        configuration: .alphaneConfiguration(
            url: server.effectiveServerURL,
            accessToken: user.accessToken
        ),
        sessionConfiguration: .alphane,
        sessionDelegate: URLSessionProxyDelegate(logger: NetworkLogger.alphane())
    )

    @MainActor
    lazy var serverConnectionManager = ServerConnectionManager()

    lazy var serverSocketManager = ServerSocketManager()

    @MainActor
    private lazy var services: [any UserSessionService] = {
        var services: [any UserSessionService] = [serverConnectionManager, serverSocketManager]
        #if os(tvOS)
        services.append(TopShelfService())
        #endif
        return services
    }()

    init(
        server: ServerState,
        user: UserState
    ) {
        self.server = server
        self.user = user
    }

    /// Waking with the same authentication must not end the live session: its
    /// store and the collections retained by Home still belong to that session.
    @MainActor
    static func sessionForForeground(current: UserSession?, stored: UserSession?) -> UserSession? {
        guard let current, let stored,
              current.server.id == stored.server.id,
              current.user.id == stored.user.id,
              current.user.serverID == stored.user.serverID,
              current.client.configuration.url == stored.client.configuration.url,
              current.client.accessToken == stored.client.accessToken
        else { return stored }

        return current
    }

    @MainActor
    func willStart() async {
        observeItemChanges()
        for service in services {
            await service.willStart(userSession: self)
        }
    }

    @MainActor
    func didStart() {
        for service in services {
            service.didStart(userSession: self)
        }
    }

    @MainActor
    func willStop() {
        itemChanges = nil
        for service in services.reversed() {
            service.willStop(userSession: self)
        }

        items.invalidate()
        itemActionErrors.send(completion: .finished)
    }
}
