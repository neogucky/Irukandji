//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import JellyfinAPI
import OrderedCollections
import SwiftUI

extension SelectUserView {

    struct TVProfilePicker: View {

        struct PublicProfile: Identifiable {
            let user: UserDto
            let server: ServerState
            let id: String
        }

        @Router
        private var router

        @FocusState
        private var focusedProfileID: String?

        @State
        private var publicProfiles: [PublicProfile] = []
        @State
        private var isLoadingPublicUsers = true

        let userItems: [UserItem]
        let servers: OrderedSet<ServerState>
        let serverSelection: SelectUserServerSelection
        let action: (UserState) -> Void
        let onDelete: (UserState) -> Void

        private var visibleServers: [ServerState] {
            switch serverSelection {
            case .all:
                Array(servers)
            case let .server(id):
                Array(servers).filter { $0.id == id }
            }
        }

        private var requestKey: String {
            visibleServers.map { "\($0.id):\($0.effectiveServerURL.absoluteString)" }.joined(separator: "|")
                + userItems.map { Self.profileID(userID: $0.user.id, serverID: $0.server.id) }.joined(separator: "|")
        }

        private var preferredProfileID: String {
            guard let item = userItems.first else { return "add-user" }

            return Self.profileID(userID: item.user.id, serverID: item.server.id)
        }

        static func profileID(userID: String, serverID: String) -> String {
            "\(serverID):\(userID)"
        }

        static func unsavedProfiles(users: [UserDto], server: ServerState, savedUsers: [UserState]) -> [PublicProfile] {
            let savedIDs = Set(savedUsers.filter { $0.serverID == server.id }.map(\.id))
            var seenIDs = Set<String>()
            return users.compactMap { user in
                guard let id = user.id, !id.isEmpty, !savedIDs.contains(id), seenIDs.insert(id).inserted else { return nil }

                return PublicProfile(user: user, server: server, id: profileID(userID: id, serverID: server.id))
            }
            .sorted { ($0.user.name ?? "").localizedStandardCompare($1.user.name ?? "") == .orderedAscending }
        }

        private func loadPublicUsers() async {
            publicProfiles = []
            isLoadingPublicUsers = true
            var profiles: [PublicProfile] = []
            for server in visibleServers {
                do {
                    let response = try await server.client.send(Paths.getPublicUsers)
                    guard !Task.isCancelled else { return }

                    profiles += Self.unsavedProfiles(users: response.value, server: server, savedUsers: userItems.map(\.user))
                } catch {
                    guard !Task.isCancelled else { return }

                    // Saved profiles and manual sign-in remain available when a server is offline.
                }
            }
            publicProfiles = profiles
            isLoadingPublicUsers = false
        }

        private var cornerControls: some View {
            HStack(spacing: 16) {
                Image(.alphaneMark)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 42, height: 42)
                // swiftlint:disable:next hard_coded_display_string
                Text("ALPHANE")
                    .font(.system(size: 22, weight: .semibold))
                    .tracking(4)
                    .foregroundStyle(.white.opacity(0.8))

                Spacer()

                ServerMenu(servers: servers, compact: true)
                    .font(.system(size: 20))
                    .buttonStyle(.capsule)
                    .controlSize(.small)
                    .frame(maxWidth: 300)

                Menu {
                    Button(L10n.advanced, systemImage: "gearshape") {
                        router.route(to: .appSettings)
                    }
                } label: {
                    Image(systemName: "gearshape")
                }
                .buttonStyle(.capsule)
                .controlSize(.small)
                .accessibilityLabel(L10n.settings)
            }
            .frame(height: 48)
            .focusSection()
        }

        private func savedProfile(_ item: UserItem) -> some View {
            let id = Self.profileID(userID: item.user.id, serverID: item.server.id)
            return Button {
                action(item.user)
            } label: {
                profileLabel(
                    userID: item.user.id,
                    source: item.user.profileImageSource(client: item.server.client),
                    name: item.user.username,
                    subtitle: item.user.requiresServerSignIn ? L10n.signIn : (visibleServers.count > 1 ? item.server.name : nil),
                    id: id,
                    saved: true
                )
            }
            .buttonStyle(ArtworkButtonStyle())
            .focused($focusedProfileID, equals: id)
            .accessibilityHint(item.user.requiresServerSignIn ? String(localized: "Enter your server password to sign in again.") : "")
            .contextMenu {
                Button(L10n.delete, role: .destructive) { onDelete(item.user) }
            }
        }

        private func publicProfile(_ profile: PublicProfile) -> some View {
            Button {
                router.route(to: .userSignIn(server: profile.server, username: profile.user.name))
            } label: {
                profileLabel(
                    userID: profile.user.id,
                    source: profile.user.profileImageSource(client: profile.server.client, maxWidth: 240),
                    name: profile.user.name ?? .emptyDash,
                    subtitle: visibleServers.count > 1 ? profile.server.name : L10n.signIn,
                    id: profile.id,
                    saved: false
                )
            }
            .buttonStyle(ArtworkButtonStyle())
            .focused($focusedProfileID, equals: profile.id)
            .accessibilityHint(L10n.profileSignInRequired)
        }

        private func profileLabel(
            userID: String?,
            source: ImageSource,
            name: String,
            subtitle: String?,
            id: String,
            saved: Bool
        ) -> some View {
            let isFocused = focusedProfileID == id
            return VStack(spacing: 18) {
                UserProfileImage(userID: userID, source: source, pipeline: .Alphane.local)
                    .frame(width: saved ? 180 : 112, height: saved ? 180 : 112)
                    .saturation(saved || isFocused ? 1 : 0.2)
                    .opacity(saved || isFocused ? 1 : 0.6)
                    .tvFocusBorder(isFocused: isFocused, shape: Circle())

                VStack(spacing: 6) {
                    Text(name)
                        .font(.system(size: saved ? 26 : 22, weight: .semibold))
                        .foregroundStyle(.white.opacity(isFocused ? 1 : 0.8))
                        .lineLimit(1)
                    Text(subtitle ?? "")
                        .font(.system(size: 18))
                        .frame(height: 22)
                        .foregroundStyle(.white.opacity(0.8))
                        .lineLimit(1)
                }
            }
            .frame(width: saved ? 220 : 180)
        }

        @ViewBuilder
        private var addUser: some View {
            if visibleServers.count == 1, let server = visibleServers.first {
                Button { router.route(to: .userSignIn(server: server)) } label: { addUserLabel }
                    .buttonStyle(ArtworkButtonStyle())
                    .focused($focusedProfileID, equals: "add-user")
            } else {
                Menu {
                    ForEach(visibleServers) { server in
                        Button(server.name) { router.route(to: .userSignIn(server: server)) }
                    }
                } label: { addUserLabel }
                    .buttonStyle(ArtworkButtonStyle())
                    .focused($focusedProfileID, equals: "add-user")
            }
        }

        private var addUserLabel: some View {
            VStack(spacing: 18) {
                Circle()
                    .fill(AlphaneTheme.surface)
                    .overlay {
                        Image(systemName: "plus")
                            .font(.system(size: 32, weight: .light))
                            .foregroundStyle(.white.opacity(focusedProfileID == "add-user" ? 1 : 0.8))
                    }
                    .frame(width: 112, height: 112)
                    .tvFocusBorder(isFocused: focusedProfileID == "add-user", shape: Circle())
                VStack(spacing: 6) {
                    Text(L10n.addUser)
                        .font(.system(size: 22, weight: .semibold))
                    Color.clear.frame(height: 22)
                }
                .foregroundStyle(.white.opacity(focusedProfileID == "add-user" ? 1 : 0.8))
            }
            .frame(width: 180)
        }

        var body: some View {
            GeometryReader { proxy in
                VStack(spacing: 0) {
                    cornerControls
                        .padding(.horizontal, 72)
                        .padding(.top, 40)

                    ScrollView(.vertical) {
                        VStack(spacing: 32) {
                            Text(L10n.profilePickerTitle)
                                .font(.system(size: 44, weight: .medium))
                                .foregroundStyle(.white)

                            if !userItems.isEmpty {
                                VStack(spacing: 24) {
                                    ScrollView(.horizontal) {
                                        HStack(spacing: 32) {
                                            ForEach(userItems, id: \.user) { item in savedProfile(item) }
                                        }
                                        .frame(minWidth: proxy.size.width - 144)
                                        .padding(.vertical, 12)
                                        .padding(.horizontal, 72)
                                    }
                                    .scrollIndicators(.hidden)
                                    .scrollClipDisabled()
                                    .focusSection()
                                }
                                Rectangle()
                                    .fill(.white.opacity(0.15))
                                    .frame(maxWidth: 900)
                                    .frame(height: 1)
                                    .padding(.vertical, 4)
                            }

                            VStack(spacing: 24) {
                                ScrollView(.horizontal) {
                                    HStack(spacing: 24) {
                                        ForEach(publicProfiles) { profile in publicProfile(profile) }
                                        addUser
                                    }
                                    .frame(minWidth: proxy.size.width - 144)
                                    .padding(.vertical, 12)
                                    .padding(.horizontal, 72)
                                }
                                .scrollIndicators(.hidden)
                                .scrollClipDisabled()
                                .focusSection()
                            }
                        }
                        .frame(minHeight: max(proxy.size.height - 136, 0))
                        .padding(.vertical, 24)
                    }
                    .scrollIndicators(.hidden)
                    .scrollClipDisabled()
                }
            }
            .defaultFocus($focusedProfileID, preferredProfileID, priority: .userInitiated)
            .onAppear { focusedProfileID = preferredProfileID }
            .task(id: requestKey) { await loadPublicUsers() }
        }

    }
}
