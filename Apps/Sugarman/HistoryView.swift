// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Sugarman contributors

import SugarmanDomain
import SwiftUI

struct HistoryView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ActiveSessionBanner()
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }
                if model.isSyntheticDemo {
                    Section {
                        SyntheticDemoBanner()
                            .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                    }
                }
                if !model.samples.isEmpty {
                    Section("history.chart") {
                        if let plan = model.selectedWorkoutPlan,
                           let target = model.selectedWorkoutPhaseTarget {
                            Text("\(plan.name) · \(target.label)")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        } else {
                            Text("history.chart_choose_workout")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        WorkoutGlucoseChart(
                            samples: chartSamples,
                            target: model.selectedWorkoutPhaseTarget,
                            unit: model.preferredUnit
                        )
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
        }
    }

    private var chartSamples: [GlucoseSample] {
        if let activeSessionID = model.activeSessionID {
            let active = model.samples.filter { $0.sessionID == activeSessionID }
            if !active.isEmpty {
                return active
            }
        }
        return model.samples
    }

    private func sampleRow(_ sample: GlucoseSample) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(sample.decoderRevision == SyntheticDemoCatalog.decoderRevision
                 ? String(localized: "history.synthetic_row")
                 : String(localized: "history.sample_row"))
                .font(.headline)
            Text(glucoseLabel(sample))
                .font(.body.monospacedDigit())
            Text("history.not_current")
                .font(.footnote)
                .foregroundStyle(.secondary)
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

    private func glucoseLabel(_ sample: GlucoseSample) -> String {
        switch model.preferredUnit {
        case .milligramsPerDeciliter:
            return String(
                format: String(localized: "history.glucose_mgdl_format"),
                locale: .current,
                sample.milligramsPerDeciliter
            )
        case .millimolesPerLiter:
            return String(
                format: String(localized: "history.glucose_mmol_format"),
                locale: .current,
                sample.millimolesPerLiter()
            )
        }
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
        let historical = String(localized: "history.accessibility_historical")
        return Text(
            "\(historical), \(glucoseLabel(sample)), \(indexLabel(sample)), \(ageLabel(sample)), \(trendLabel(sample)), \(sourceLabel(sample))"
        )
    }
}
