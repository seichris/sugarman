// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Sugarman contributors

import AccountBinding
import SwiftUI

struct OnboardingPlaceholderView: View {
    @State private var ownerID = ""
    @State private var ownerStatus = String(localized: "onboarding.owner_idle")

    var body: some View {
        NavigationStack {
            Form {
                Section("onboarding.sensor") {
                    Text("onboarding.placeholder")
                    Text("onboarding.no_commands")
                        .foregroundStyle(.secondary)
                }
                Section("onboarding.owner") {
                    TextField("onboarding.owner_field", text: $ownerID)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button("onboarding.owner_save") {
                        do {
                            let id = try ManualOwnerBinding().validate(ownerID)
                            ownerStatus = String(
                                format: String(localized: "onboarding.owner_ok"),
                                locale: .current,
                                id.value
                            )
                        } catch {
                            ownerStatus = error.localizedDescription
                        }
                    }
                    Text(ownerStatus)
                        .font(.footnote)
                }
            }
            .navigationTitle("onboarding.title")
        }
    }
}
