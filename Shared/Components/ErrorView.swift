//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Defaults
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

    let error: ErrorType
    var isRetrying = false
    var didRetryFail = false
    var retryAction: (@MainActor () async -> Void)?

    @State
    private var isRetryingLocally = false
    @State
    private var didRetryLocally = false
    #if os(tvOS)
    @FocusState
    private var isRetryFocused: Bool
    #endif

    private var isBusy: Bool {
        isRetrying || isRetryingLocally
    }

    private var canRetry: Bool {
        retryAction != nil || refresh != nil
    }

    private var feedback: String {
        if isBusy {
            String(localized: "Trying again. Please wait…")
        } else if didRetryFail || didRetryLocally {
            if (error as NSError).domain == NSURLErrorDomain {
                String(localized: "Still unable to connect. Check the server or your network, then try again.")
            } else {
                String(localized: "The retry didn’t succeed. Please try again.")
            }
        } else {
            (error as? LocalizedError)?.recoverySuggestion ?? ""
        }
    }

    static func displayMessage(for error: Error) -> String {
        let failure = error as NSError
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
        guard !isBusy, canRetry else { return }

        isRetryingLocally = true
        Task { @MainActor in
            if let retryAction {
                await retryAction()
            } else if let refresh {
                await refresh()
            }
            isRetryingLocally = false
            didRetryLocally = true
        }
    }

    private var systemImage: String {
        if let error = error as? SystemImageable {
            error.systemImage
        } else if (error as NSError).domain == NSURLErrorDomain {
            "wifi.exclamationmark"
        } else {
            "xmark.circle"
        }
    }

    #if os(tvOS)
    private var tvBody: some View {
        VStack(spacing: 24) {
            Image(systemName: systemImage)
                .font(.system(size: 44, weight: .regular))
                .foregroundStyle(AlphaneTheme.secondaryText)
                .symbolRenderingMode(.monochrome)
                .frame(width: 96, height: 96)
                .background(AlphaneTheme.surface, in: RoundedRectangle(cornerRadius: 28))
                .accessibilityHidden(true)

            Text(Self.displayMessage(for: error))
                .font(.system(size: 30, weight: .medium))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .lineLimit(4)
                .frame(maxWidth: 800)

            if canRetry {
                Button(action: retry) {
                    HStack(spacing: 14) {
                        ZStack {
                            Image(systemName: "arrow.clockwise")
                                .opacity(isBusy ? 0 : 1)
                            if isBusy {
                                ProgressView()
                                    .tint(isRetryFocused ? .black : .white)
                            }
                        }
                        .frame(width: 24, height: 24)
                        Text(isBusy ? String(localized: "Retrying…") : L10n.retry)
                    }
                    .frame(width: 180)
                }
                .buttonStyle(TVSettingsButtonStyle())
                .focused($isRetryFocused)
                .accessibilityIdentifier("error-retry")
                .accessibilityValue(isBusy ? String(localized: "Retrying") : "")
                .defaultFocus($isRetryFocused, true)
                .padding(.top, 6)
            }

            Text(feedback)
                .font(.system(size: 20))
                .foregroundStyle(AlphaneTheme.secondaryText)
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .frame(maxWidth: 800, minHeight: 64, alignment: .top)
                .accessibilityIdentifier("error-status")
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
        #if os(tvOS)
        tvBody
        #else
        legacyBody
        #endif
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
                    isRetrying: recovery.isRetrying,
                    didRetryFail: recovery.failedAttempts > 0,
                    retryAction: {
                        await recovery.retry(error: presentedError, operation: retry)
                    }
                )
                .onAppear(perform: onErrorAppear)
            } else {
                content
            }
        }
    }
}
