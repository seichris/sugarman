// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Sugarman contributors

import SugarmanDomain
import SwiftUI

struct FuelingView: View {
    @Environment(AppModel.self) private var model
    @State private var label = ""
    @State private var carbsText = ""
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
                Section {
                    ActiveSessionBanner()
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }
                Section("fueling.add") {
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
        }
    }

    private func fuelingRow(_ event: FuelingEvent) -> some View {
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

    private func fuelingAccessibilityLabel(_ event: FuelingEvent) -> String {
        var parts = [event.label]
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
            try await model.addFueling(label: trimmed, carbohydrateGrams: carbs, timestamp: timestamp)
            actionError = nil
            label = ""
            carbsText = ""
            timestamp = Date()
        } catch {
            actionError = error.localizedDescription
        }
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
