//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import SwiftUI

extension ConnectToServerView {

    struct TVSetupContent: View {

        @Binding
        var url: String
        let isURLFocused: FocusState<Bool>.Binding
        @ObservedObject
        var viewModel: ConnectToServerViewModel

        private func connect() {
            isURLFocused.wrappedValue = false
            viewModel.connect(url: url)
        }

        private var addressField: some View {
            TextField(L10n.serverAddress, text: $url)
                .textFieldStyle(.plain)
                .font(.system(size: 28))
                .disableAutocorrection(true)
                .textInputAutocapitalization(.never)
                .keyboardType(.URL)
                .focused(isURLFocused)
                .frame(height: 76)
                .disabled(viewModel.state == .connecting)
        }

        private var connectAction: some View {
            HStack(spacing: 20) {
                if viewModel.state == .connecting {
                    ProgressView()
                    Button(L10n.cancel, action: viewModel.cancel)
                } else {
                    Button(L10n.connect, systemImage: "arrow.right", action: connect)
                        .disabled(url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .buttonStyle(.capsule)
            .controlSize(.extraLarge)
            .frame(height: 64)
            .focusSection()
        }

        var body: some View {
            GeometryReader { proxy in
                ScrollView {
                    VStack(spacing: 36) {
                        Image(.alphaneMark)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 96, height: 96)
                            .accessibilityHidden(true)

                        Text(L10n.connectToServer)
                            .font(.system(size: 44, weight: .medium))
                            .foregroundStyle(.white)

                        VStack(spacing: 22) {
                            addressField
                            Text(L10n.serverAddressHint)
                                .font(.system(size: 20))
                                .foregroundStyle(IrukandjiTheme.secondaryText)
                                .multilineTextAlignment(.center)
                            connectAction
                        }
                        .frame(maxWidth: 720)

                        if !viewModel.localServers.isEmpty {
                            Rectangle()
                                .fill(.white.opacity(0.15))
                                .frame(maxWidth: 720)
                                .frame(height: 1)

                            VStack(spacing: 18) {
                                Text(L10n.localServers)
                                    .font(.system(size: 22))
                                    .foregroundStyle(IrukandjiTheme.secondaryText)
                                ForEach(viewModel.localServers) { server in
                                    LocalServerButton(server: server) {
                                        url = server.currentURL.absoluteString
                                        connect()
                                    }
                                }
                            }
                            .frame(maxWidth: 720)
                            .disabled(viewModel.state == .connecting)
                            .focusSection()
                        }
                    }
                    .frame(minHeight: max(proxy.size.height - 120, 0))
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 96)
                    .padding(.vertical, 60)
                }
                .scrollIndicators(.hidden)
                .scrollClipDisabled()
            }
            .background {
                IrukandjiTheme.background
                    .overlay {
                        RadialGradient(
                            colors: [.white.opacity(0.04), .clear],
                            center: .center,
                            startRadius: 0,
                            endRadius: 700
                        )
                    }
                    .ignoresSafeArea()
            }
            .defaultFocus(isURLFocused, true, priority: .userInitiated)
        }
    }
}
