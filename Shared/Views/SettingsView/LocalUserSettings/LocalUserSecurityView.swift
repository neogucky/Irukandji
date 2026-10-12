//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import SwiftUI

// TODO: present toast when authentication successfully changed

struct LocalUserSecurityView: View {

    @Environment(\.localUserAuthenticationAction)
    private var authenticationAction

    @Router
    private var router

    @State
    private var error: Error? = nil

    @State
    private var pinHint: String = ""

    @State
    private var signInPolicy: LocalUserAccessPolicy = .none

    @StateObject
    private var viewModel = LocalUserSecurityViewModel()

    @MainActor
    private func performSaveSecurityPolicy() async {
        guard let authenticationAction else {
            return
        }

        do {
            let user = try viewModel.requireUserSession().user
            let oldPolicy = user.accessPolicy

            let oldEvaluatedPolicy = try await authenticationAction(
                policy: oldPolicy,
                reason: oldPolicy.authenticateReason(user: user)
            )

            if let oldPinPolicy = oldEvaluatedPolicy as? PinEvaluatedUserAccessPolicy {
                try viewModel.check(oldPin: oldPinPolicy.pin)
            }

            let newEvaluatedPolicy = try await authenticationAction(
                policy: signInPolicy,
                reason: signInPolicy.createReason(user: user)
            )

            try viewModel.set(
                newPolicy: signInPolicy,
                newPin: (newEvaluatedPolicy as? PinEvaluatedUserAccessPolicy)?.pin ?? "",
                newPinHint: signInPolicy == .requirePin ? pinHint : ""
            )
            router.dismiss()
        } catch is CancellationError {
            return
        } catch {
            UIDevice.feedback(.error)
            self.error = error
        }
    }

    var body: some View {
        Group {
            #if os(tvOS)
            TVSettingsPage(title: "Profile PIN") {
                VStack(alignment: .leading, spacing: 22) {
                    Button {
                        signInPolicy = signInPolicy == .requirePin ? .none : .requirePin
                    } label: {
                        TVSettingsRow(
                            title: "Require PIN",
                            value: signInPolicy == .requirePin ? TVSettingsText.on : TVSettingsText.off,
                            symbol: nil
                        )
                    }

                    if signInPolicy == .requirePin {
                        hintControl
                    }

                    Text(L10n.additionalSecurityAccessDescription)
                        .font(.system(size: 20))
                        .foregroundStyle(AlphaneTheme.secondaryText)
                        .padding(.horizontal, 22)
                        .padding(.vertical, 12)

                    HStack(spacing: 22) {
                        Button(L10n.cancel) { router.dismiss() }
                        if let user = viewModel.userSession?.user {
                            let isChangingPIN = signInPolicy == .requirePin && signInPolicy == user.accessPolicy
                            Button(isChangingPIN ? L10n.changePin : L10n.save) {
                                Task { @MainActor in
                                    await performSaveSecurityPolicy()
                                }
                            }
                        }
                        Spacer()
                    }
                }
                .frame(maxWidth: 700)
            }
            #else
            Form(systemImage: "lock.fill") {
                securitySection

                if signInPolicy == .requirePin {
                    Section {
                        hintControl
                    } header: {
                        Text(L10n.hint)
                    } footer: {
                        Text(L10n.setPinHintDescription)
                    }
                }
            }
            #endif
        }
        .animation(.linear, value: signInPolicy)
        .navigationTitle(L10n.security)
        .onFirstAppear {
            guard let user = viewModel.userSession?.user else { return }

            signInPolicy = user.accessPolicy
            pinHint = user.pinHint
        }
        #if os(iOS)
        .topBarTrailing {
            if let user = viewModel.userSession?.user {
                let isChangingPIN = signInPolicy == .requirePin && signInPolicy == user.accessPolicy
                let saveAction: () -> Void = {
                    Task { @MainActor in
                        await performSaveSecurityPolicy()
                    }
                }

                Group {
                    #if os(iOS)
                    if #available(iOS 26, *), !isChangingPIN {
                        Button(L10n.save, role: .confirm, action: saveAction)
                    } else {
                        Button(isChangingPIN ? L10n.changePin : L10n.save, action: saveAction)
                            .backport
                            .buttonStyle(.glassProminent)
                            .controlSize(.small)
                    }
                    #else
                    Button(isChangingPIN ? L10n.changePin : L10n.save, action: saveAction)
                    #endif
                }
            }
        }
        #endif
        .errorMessage($error)
    }

    @ViewBuilder
    private var hintControl: some View {
        #if os(iOS)
        TextField(L10n.hint, text: $pinHint)
        #else
        StateAdapter(initialValue: (isPresented: false, hint: pinHint)) { alert in
            ChevronButton(L10n.hint, content: pinHint) {
                alert.isPresented.wrappedValue = true
            }
            .alert(L10n.hint, isPresented: alert.isPresented) {
                TextField(L10n.hint, text: alert.hint)

                Button(L10n.save) {
                    pinHint = alert.hint.wrappedValue
                }
                Button(L10n.cancel, role: .cancel) {}
            } message: {
                Text(L10n.setPinHintDescription)
            }
        }
        #endif
    }

    @ViewBuilder
    private var securitySection: some View {
        Section(L10n.security) {
            #if os(iOS)
            Picker(L10n.security, selection: $signInPolicy)
            #else
            Toggle(
                L10n.pin,
                isOn: $signInPolicy.map(
                    getter: { $0 == .requirePin },
                    setter: { $0 ? .requirePin : .none }
                )
            )
            #endif
        } footer: {
            Text(L10n.additionalSecurityAccessDescription)
        } learnMore: {
            LabeledContent(
                LocalUserAccessPolicy.none.displayTitle,
                value: L10n.saveUserWithoutAuthDescription
            )
            #if os(iOS)
            LabeledContent(
                LocalUserAccessPolicy.requireDeviceAuthentication.displayTitle,
                value: L10n.requireDeviceAuthDescription
            )
            #endif
            LabeledContent(
                LocalUserAccessPolicy.requirePin.displayTitle,
                value: L10n.requirePinDescription
            )
        }
    }
}
