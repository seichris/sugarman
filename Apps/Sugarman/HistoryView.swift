// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Sugarman contributors

import SugarmanDomain
import SwiftUI

struct HistoryView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        NavigationStack {
            List {
                if model.isSyntheticDemo {
                    Section {
                        SyntheticDemoBanner()
                            .listRowInsets(EdgeInsets())
                            .listRowBackground(Color.clear)
                    }
                }
                Section("history.samples") {
                    if model.samples.isEmpty {
                        Text("history.empty")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(model.samples) { sample in
                            sampleRow(sample)
                        }
                    }
                }
            }
            .navigationTitle("history.title")
            .overlay(alignment: .bottom) {
                Text("history.overlay_later")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding()
            }
        }
    }

    private func sampleRow(_ sample: GlucoseSample) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(sample.decoderRevision == SyntheticDemoCatalog.decoderRevision
                 ? String(localized: "history.synthetic_row")
                 : String(localized: "history.sample_row"))
                .font(.headline)
            Text(indexLabel(sample))
            Text(ageLabel(sample))
            Text(trendLabel(sample))
            Text(sourceLabel(sample))
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel(sample))
    }

    private func indexLabel(_ sample: GlucoseSample) -> String {
        String(
            format: String(localized: "history.index_format"),
            locale: .current,
            Int(sample.sensorIndex)
        )
    }

    private func ageLabel(_ sample: GlucoseSample) -> String {
        let age = Date().timeIntervalSince(sample.receiptTimestamp)
        let minutes = max(0, Int(age / 60))
        let seconds = max(0, Int(age.truncatingRemainder(dividingBy: 60)))
        return String(
            format: String(localized: "history.age_format"),
            locale: .current,
            minutes,
            seconds
        )
    }

    private func trendLabel(_ sample: GlucoseSample) -> String {
        let key = LocalizedStringResource(stringLiteral: "history.trend.\(sample.trend.rawValue)")
        return String(localized: key)
    }

    private func sourceLabel(_ sample: GlucoseSample) -> String {
        switch sample.source {
        case .live:
            String(localized: "history.source.live")
        case .backfill:
            String(localized: "history.source.backfill")
        }
    }

    private func accessibilityLabel(_ sample: GlucoseSample) -> Text {
        Text("\(indexLabel(sample)), \(ageLabel(sample)), \(trendLabel(sample)), \(sourceLabel(sample))")
    }
}
