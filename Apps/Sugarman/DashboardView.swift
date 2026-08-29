// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Sugarman contributors

import SafetyEngine
import SugarmanDomain
import SwiftUI

struct DashboardView: View {
    @Environment(AppModel.self) private var model
    @ScaledMetric(relativeTo: .largeTitle) private var glucoseSize: CGFloat = 48

    var body: some View {
        NavigationStack {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                dashboardBody(now: context.date)
            }
            .navigationTitle("dashboard.title")
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Picker("dashboard.unit", selection: Bindable(model).preferredUnit) {
                        Text("dashboard.unit.mgdl").tag(GlucoseUnit.milligramsPerDeciliter)
                        Text("dashboard.unit.mmol").tag(GlucoseUnit.millimolesPerLiter)
                    }
                    .pickerStyle(.segmented)
                    .accessibilityLabel(Text("dashboard.unit"))
                    .frame(maxWidth: 220)
                }
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Section("demo.replaces_data") {
                            ForEach(SyntheticDemoScenario.allCases) { scenario in
                                Button(demoTitle(scenario)) {
                                    Task {
                                        do {
                                            try await model.loadDemo(scenario)
                                        } catch {
                                            // loadDemo already sets demoLoadError
                                        }
                                    }
                                }
                            }
                        }
                    } label: {
                        Label("demo.menu", systemImage: "sparkles")
                    }
                    .accessibilityLabel(Text("demo.menu"))
                    .accessibilityHint(Text("demo.hint"))
                }
            }
        }
    }

    private func dashboardBody(now: Date) -> some View {
        let assessment = model.assessment(at: now)
        return ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                NoDosingBanner()
                ActiveSessionBanner()
                if model.isSyntheticDemo {
                    SyntheticDemoBanner()
                }
                if let demoLoadError = model.demoLoadError {
                    Text(demoLoadError)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
                statusCard(assessment)
                readingCard(assessment)
                Text("dashboard.athlete_purpose")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding()
        }
    }

    private func statusCard(_ assessment: SafetyAssessment) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("dashboard.connection")
                .font(.headline)
            Text(connectionLabel)
            Text(readingAgeLabel(assessment))
                .font(.title3.monospacedDigit())
            if assessment.isStale {
                Text("dashboard.stale")
                    .font(.headline)
                    .foregroundStyle(.orange)
            }
            if assessment.isDisconnected {
                Text("dashboard.disconnected")
                    .font(.headline)
                    .foregroundStyle(.red)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
        .accessibilityElement(children: .combine)
    }

    private func readingCard(_ assessment: SafetyAssessment) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("dashboard.glucose")
                .font(.headline)
            switch assessment.presentation {
            case .current(let mgdl, _):
                Text(currentGlucoseText(mgdl: mgdl))
                    .font(.system(size: glucoseSize, weight: .semibold, design: .rounded))
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                    .accessibilityLabel(Text(currentGlucoseText(mgdl: mgdl)))
            case .empty:
                Text("dashboard.empty")
                    .font(.title3)
            case .connectedNoData:
                Text(verbatim: ProductCopy.connectedNoData)
                    .font(.title3)
            case .disconnected:
                Text("dashboard.disconnected")
                    .font(.title3)
            case .stale:
                Text("dashboard.stale")
                    .font(.title3)
            case .warmUp:
                Text("dashboard.warmup")
                    .font(.title3)
            case .sensorError:
                Text("dashboard.error")
                    .font(.title3)
            case .expired:
                Text("dashboard.expired")
                    .font(.title3)
            case .questionable:
                Text("dashboard.questionable")
                    .font(.title3)
            }
            if let notice = assessment.notCurrentNotice, !assessment.showsValueAsCurrent {
                Text(notice)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
        .accessibilityElement(children: .combine)
    }

    private var connectionLabel: String {
        switch model.connection {
        case .disconnected, .idle:
            String(localized: "dashboard.disconnected")
        case .scanning:
            String(localized: "dashboard.scanning")
        case .connecting:
            String(localized: "dashboard.connecting")
        case .connected, .subscribed:
            String(localized: "dashboard.connected")
        case .bluetoothUnavailable:
            String(localized: "dashboard.bt_unavailable")
        case .unauthorized:
            String(localized: "dashboard.bt_unauthorized")
        }
    }

    private func readingAgeLabel(_ assessment: SafetyAssessment) -> String {
        if let age = assessment.readingAgeSeconds {
            let minutes = Int(age / 60)
            let seconds = Int(age.truncatingRemainder(dividingBy: 60))
            return String(
                format: String(localized: "dashboard.reading_age_format"),
                locale: .current,
                minutes,
                seconds
            )
        }
        return String(localized: "dashboard.reading_age_unknown")
    }

    private func currentGlucoseText(mgdl: Int) -> String {
        switch model.preferredUnit {
        case .milligramsPerDeciliter:
            return String(
                format: String(localized: "dashboard.glucose_mgdl_format"),
                locale: .current,
                mgdl
            )
        case .millimolesPerLiter:
            let mmol: Double
            if let sample = model.latestSample {
                mmol = sample.millimolesPerLiter()
            } else {
                mmol = Double(mgdl) / 18.0
            }
            return String(
                format: String(localized: "dashboard.glucose_mmol_format"),
                locale: .current,
                mmol
            )
        }
    }

    private func demoTitle(_ scenario: SyntheticDemoScenario) -> LocalizedStringKey {
        switch scenario {
        case .current: "demo.current"
        case .stale: "demo.stale"
        case .disconnected: "demo.disconnected"
        case .warmUp: "demo.warmup"
        case .sensorError: "demo.error"
        case .expired: "demo.expired"
        case .connectedNoData: "demo.connected_no_data"
        case .questionableSample: "demo.questionable"
        }
    }
}
