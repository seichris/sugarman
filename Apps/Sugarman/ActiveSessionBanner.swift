// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Sugarman contributors

import SugarmanDomain
import SwiftUI

struct ActiveSessionBanner: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("session.active_title")
                .font(.headline)
            if let id = model.activeSessionID {
                Text(sessionLine(id))
                    .font(.body.monospacedDigit())
                Text("session.active_used_for")
                    .font(.footnote)
                    .foregroundStyle(.primary)
            } else {
                Text("session.none")
                    .foregroundStyle(.primary)
            }
            if model.sessions.count > 1 {
                ForEach(model.sessions) { session in
                    Button {
                        Task { await model.chooseSession(session.id) }
                    } label: {
                        HStack {
                            Text(shortID(session.id))
                                .font(.body.monospacedDigit())
                            Spacer()
                            if model.activeSessionID == session.id {
                                Text("session.active_badge")
                                    .font(.footnote.weight(.semibold))
                            }
                        }
                    }
                    .accessibilityLabel(Text(sessionAccessibilityLabel(session.id)))
                    .accessibilityHint(Text("session.picker_hint"))
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.blue.opacity(0.16), in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .contain)
    }

    private func shortID(_ id: UUID) -> String {
        String(id.uuidString.prefix(8))
    }

    private func sessionLine(_ id: UUID) -> String {
        String(
            format: String(localized: "session.active_id_format"),
            locale: .current,
            shortID(id)
        )
    }

    private func sessionAccessibilityLabel(_ id: UUID) -> String {
        let active = model.activeSessionID == id ? String(localized: "session.active_badge") : ""
        return [shortID(id), active].filter { !$0.isEmpty }.joined(separator: ", ")
    }
}
