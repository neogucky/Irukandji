//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Defaults
import FactoryKit
import Foundation
import SwiftUI

#if os(iOS)
private let buttonHeight: CGFloat = 44
private let buttonMaxSize: CGFloat = 300
private let iconSize: CGFloat = 72
#else
private let buttonHeight: CGFloat = 75
private let buttonMaxSize: CGFloat = 600
private let iconSize: CGFloat = 144
#endif

struct ErrorView<ErrorType: Error>: View {

    @Default(.accentColor)
    private var accentColor

    @Environment(\.refresh)
    private var refresh

    @Environment(\.accessibilityReduceMotion)
    private var reduceMotion
    @InjectedObject(\.userSessionManager)
    private var userSessionManager

    let error: ErrorType
    private let retryAction: (@MainActor () async -> Error?)?

    @StateObject
    private var recovery: ErrorRecoveryState
    @State
    private var retryTask: Task<Void, Never>?
    @State
    private var isSwitchingServer = false
    #if os(tvOS)
    @FocusState
    private var focusedButton: String?
    #endif

    @MainActor
    init(
        error: ErrorType,
        recovery: ErrorRecoveryState? = nil,
        retryAction: (@MainActor () async -> Error?)? = nil
    ) {
        self.error = error
        _recovery = StateObject(wrappedValue: recovery ?? ErrorRecoveryState())
        self.retryAction = retryAction
    }

    private var isBusy: Bool {
        recovery.isRetrying
    }

    private var isChecking: Bool {
        isBusy || recovery.isDiagnosing
    }

    private var canRetry: Bool {
        retryAction != nil || refresh != nil
    }

    private var diagnosticKey: String {
        ConnectionDiagnostics.failureID(for: error)
    }

    static func displayMessage(for error: Error) -> String {
        let failure = ConnectionDiagnostics.connectionError(in: error) ?? error as NSError
        guard failure.domain == NSURLErrorDomain else { return error.localizedDescription }

        switch URLError.Code(rawValue: failure.code) {
        case .cannotConnectToHost:
            return String(localized: "Could not connect to the server.")
        case .notConnectedToInternet:
            return String(localized: "No network connection. Check your connection and try again.")
        case .networkConnectionLost:
            return String(localized: "The connection to the server was interrupted.")
        case .timedOut:
            return String(localized: "The server took too long to respond.")
        case .cannotFindHost, .dnsLookupFailed:
            return String(localized: "The server address could not be found.")
        default:
            return error.localizedDescription
        }
    }

    private func retry() {
        guard !isBusy, !isSwitchingServer, canRetry else { return }

        retryTask = Task { @MainActor in
            await recovery.retry(error: error) {
                if let retryAction {
                    return await retryAction()
                }
                await refresh?()
                // Legacy consumers replace this view when their reload succeeds.
                return error
            }
        }
    }

    private func switchServer() {
        guard !isBusy, !isSwitchingServer else { return }

        isSwitchingServer = true
        Task { @MainActor in
            await userSessionManager.switchServer()
            isSwitchingServer = false
        }
    }

    private var systemImage: String {
        if isChecking, ConnectionDiagnostics.connectionError(in: error) != nil {
            "wifi"
        } else if let error = error as? SystemImageable {
            error.systemImage
        } else if ConnectionDiagnostics.connectionError(in: error) != nil {
            "wifi.exclamationmark"
        } else {
            "xmark.circle"
        }
    }

    #if os(tvOS)
    private var tvBody: some View {
        VStack(spacing: 24) {
            Image(systemName: systemImage)
                .symbolEffect(
                    .variableColor.cumulative.hideInactiveLayers,
                    options: .repeating,
                    isActive: isChecking && !reduceMotion
                )
                .contentTransition(reduceMotion ? .identity : .symbolEffect(.replace))
                .font(.system(size: 44, weight: .regular))
                .foregroundStyle(AlphaneTheme.secondaryText)
                .symbolRenderingMode(.monochrome)
                .frame(width: 96, height: 96)
                .background(AlphaneTheme.surface, in: RoundedRectangle(cornerRadius: 28))
                .accessibilityHidden(true)

            Text(recovery.connectionIssue?.message ?? Self.displayMessage(for: error))
                .font(.system(size: 30, weight: .medium))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .lineLimit(4)
                .frame(maxWidth: 800)

            Text(recovery.connectionIssue?.suggestion ?? "")
                .font(.system(size: 20))
                .foregroundStyle(AlphaneTheme.secondaryText)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .frame(maxWidth: 800, minHeight: 48, alignment: .top)

            HStack(spacing: 24) {
                if canRetry {
                    Button(action: retry) {
                        HStack(spacing: 14) {
                            ZStack {
                                Image(systemName: "arrow.clockwise")
                                    .opacity(isBusy ? 0 : 1)
                                if isBusy {
                                    ProgressView()
                                        .scaleEffect(0.65)
                                        .tint(focusedButton == "retry" ? .black : .white)
                                }
                            }
                            .frame(width: 24, height: 24)
                            Text(isBusy ? String(localized: "Retrying…") : L10n.retry)
                        }
                        .frame(width: 180)
                    }
                    .buttonStyle(TVSettingsButtonStyle())
                    .focused($focusedButton, equals: "retry")
                    .accessibilityIdentifier("error-retry")
                    .accessibilityValue(isBusy ? String(localized: "Retrying") : "")
                }

                if recovery.connectionIssue == .server, userSessionManager.currentSession != nil {
                    Button(action: switchServer) {
                        Label(String(localized: "Switch server"), systemImage: "server.rack")
                    }
                    .buttonStyle(TVSettingsButtonStyle())
                    .focused($focusedButton, equals: "server")
                    .accessibilityIdentifier("error-switch-server")
                }
            }
            .defaultFocus($focusedButton, "retry")
            .padding(.top, 6)
        }
        .padding(60)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AlphaneTheme.background.ignoresSafeArea())
        .focusSection()
    }
    #endif

    private var legacyBody: some View {
        VStack {
            Image(systemName: systemImage)
                .font(.system(size: iconSize, weight: .regular))
                .foregroundStyle(Color.red)
                .symbolRenderingMode(.monochrome)

            Text(error.localizedDescription)
                .font(.headline)
                .fontWeight(.semibold)
                .foregroundStyle(.primary)
                .lineLimit(2)
                .multilineTextAlignment(.center)

            if canRetry {
                Button(action: retry) {
                    Text(L10n.retry)
                        .frame(maxWidth: .infinity)
                }
                .fontWeight(.semibold)
                .backport
                .buttonStyle(.glassProminent.shadow(false))
                .tint(accentColor)
                #if os(iOS)
                    .controlSize(.large)
                #endif
                    .frame(height: buttonHeight)
                    .frame(maxWidth: buttonMaxSize)
            }

            if let localizedError = error as? LocalizedError,
               let recoverySuggestion = localizedError.recoverySuggestion
            {
                Text(recoverySuggestion)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: 600, maxHeight: .infinity)
        .frame(maxWidth: .infinity)
        .focusSection()
        .edgePadding()
    }

    var body: some View {
        Group {
            #if os(tvOS)
            tvBody
            #else
            legacyBody
            #endif
        }
        #if os(tvOS)
        .task(id: diagnosticKey) {
            await recovery.diagnose(error: error)
        }
        #endif
        .onDisappear {
            retryTask?.cancel()
        }
    }
}

/// Retains the same error screen and focus throughout an awaited retry.
struct RetryableContentView<Content: View>: View {

    let error: Error?
    let retry: @MainActor () async -> Error?
    var onErrorAppear: () -> Void = {}
    @ViewBuilder
    var content: Content

    @StateObject
    private var recovery = ErrorRecoveryState()

    var body: some View {
        ZStack {
            if let presentedError = recovery.isRetrying ? recovery.error : error {
                ErrorView(
                    error: presentedError,
                    recovery: recovery,
                    retryAction: retry
                )
                .onAppear(perform: onErrorAppear)
            } else {
                content
            }
        }
    }
}
