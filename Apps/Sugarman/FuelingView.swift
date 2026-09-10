// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Sugarman contributors

import SugarmanDomain
import SwiftUI

struct FuelingView: View {
    @Environment(AppModel.self) private var model
    @State private var label = ""
    @State private var carbsText = ""
    @State private var emoji = FuelingEvent.defaultEmoji
    @State private var timestamp = Date()
    @State private var actionError: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(verbatim: ProductCopy.athleteInsightOnly)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Section("fueling.quick_add") {
                    quickAddGrid
                }
                Section("fueling.add") {
                    emojiChooser
                    TextField("fueling.label_field", text: $label)
                    TextField("fueling.carbs_field", text: $carbsText)
                        .keyboardType(.decimalPad)
                    DatePicker("fueling.timestamp", selection: $timestamp)
                    Button("fueling.save") {
                        Task { await save() }
                    }
                    .disabled(label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityHint(Text("fueling.save_hint"))
                }
                Section("fueling.list") {
                    if let actionError {
                        Text(actionError).foregroundStyle(.red)
                    }
                    if model.visibleFuelingEvents.isEmpty {
                        Text("fueling.empty")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(model.visibleFuelingEvents) { event in
                            fuelingRow(event)
                                .accessibilityElement(children: .combine)
                                .accessibilityLabel(Text(fuelingAccessibilityLabel(event)))
                                .accessibilityHint(Text("fueling.delete_hint"))
                                .accessibilityAction(named: Text("fueling.delete")) {
                                    Task { await delete(event.id) }
                                }
                        }
                        .onDelete { offsets in
                            let ids = offsets.map { model.visibleFuelingEvents[$0].id }
                            Task {
                                for id in ids {
                                    await delete(id)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("fueling.title")
            .scrollDismissesKeyboard(.interactively)
        }
    }

    private var quickAddGrid: some View {
        let columns = Array(
            repeating: GridItem(.flexible(), spacing: 10),
            count: 3
        )
        return LazyVGrid(columns: columns, spacing: 10) {
            ForEach(FuelingPreset.defaults) { preset in
                Button {
                    apply(preset)
                } label: {
                    VStack(spacing: 6) {
                        Text(preset.emoji)
                            .font(.title2)
                        Text(verbatim: preset.label)
                            .font(.caption)
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                            .frame(maxWidth: .infinity)
                    }
                    .frame(maxWidth: .infinity, minHeight: 72)
                    .padding(.vertical, 4)
                    .background(
                        Color.secondary.opacity(0.12),
                        in: RoundedRectangle(cornerRadius: 12)
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(verbatim: preset.emoji + ", " + preset.label))
                .accessibilityHint(Text("fueling.quick_add_hint"))
            }
        }
        .padding(.vertical, 4)
    }

    private var emojiChooser: some View {
        let columns = Array(
            repeating: GridItem(.flexible(), spacing: 8),
            count: 5
        )
        return VStack(alignment: .leading, spacing: 8) {
            Text("fueling.emoji")
                .font(.subheadline.weight(.medium))
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(FuelingPreset.emojiChoices, id: \.self) { choice in
                    Button {
                        emoji = choice
                    } label: {
                        Text(choice)
                            .font(.title2)
                            .frame(maxWidth: .infinity, minHeight: 38)
                            .background(
                                emoji == choice
                                    ? Color.accentColor.opacity(0.2)
                                    : Color.clear,
                                in: RoundedRectangle(cornerRadius: 8)
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text(verbatim: choice))
                    .accessibilityAddTraits(emoji == choice ? .isSelected : [])
                }
            }
        }
    }

    private func fuelingRow(_ event: FuelingEvent) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(event.emoji)
                .font(.title2)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(event.label)
                    .font(.headline)
                if let grams = event.carbohydrateGrams {
                    Text(
                        String(
                            format: String(localized: "fueling.carbs_format"),
                            locale: .current,
                            grams
                        )
                    )
                }
                Text(event.timestamp.formatted(date: .abbreviated, time: .shortened))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func fuelingAccessibilityLabel(_ event: FuelingEvent) -> String {
        var parts = [event.emoji, event.label]
        if let grams = event.carbohydrateGrams {
            parts.append(
                String(
                    format: String(localized: "fueling.carbs_format"),
                    locale: .current,
                    grams
                )
            )
        }
        parts.append(event.timestamp.formatted(date: .abbreviated, time: .shortened))
        parts.append(String(localized: "fueling.delete"))
        return parts.joined(separator: ", ")
    }

    private func save() async {
        let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let normalizedCarbs = carbsText.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: ".")
        let carbs: Double?
        if normalizedCarbs.isEmpty {
            carbs = nil
        } else if let parsed = Double(normalizedCarbs) {
            carbs = parsed
        } else {
            actionError = AppInputError.invalidCarbohydrateAmount.localizedDescription
            return
        }
        do {
            try await model.addFueling(
                label: trimmed,
                carbohydrateGrams: carbs,
                timestamp: timestamp,
                emoji: emoji
            )
            actionError = nil
            label = ""
            carbsText = ""
            emoji = FuelingEvent.defaultEmoji
            timestamp = Date()
        } catch {
            actionError = error.localizedDescription
        }
    }

    private func apply(_ preset: FuelingPreset) {
        label = preset.label
        emoji = preset.emoji
        if let grams = preset.carbohydrateGrams {
            carbsText = String(format: "%.0f", locale: .current, grams)
        } else {
            carbsText = ""
        }
        actionError = nil
    }

    private func delete(_ id: UUID) async {
        do {
            try await model.deleteFueling(id)
            actionError = nil
        } catch {
            actionError = error.localizedDescription
        }
    }
}
