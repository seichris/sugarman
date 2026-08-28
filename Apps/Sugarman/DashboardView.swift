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
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    NoDosingBanner()
                    if model.isSyntheticDemo {
                        SyntheticDemoBanner()
                    }
                    statusCard
                    readingCard
                    Text("dashboard.athlete_purpose")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding()
            }
            .navigationTitle("dashboard.title")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Section("demo.replaces_data") {
                            ForEach(SyntheticDemoScenario.allCases) { scenario in
                                Button(demoTitle(scenario)) {
                                    Task { await model.loadDemo(scenario) }
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

    private var assessment: SafetyAssessment { model.assessment }

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("dashboard.connection")
                .font(.headline)
            Text(connectionLabel)
            Text(readingAgeLabel)
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

    private var readingCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("dashboard.glucose")
                .font(.headline)
            switch assessment.presentation {
            case .current(let mgdl, _):
                Text("\(mgdl) mg/dL")
                    .font(.system(size: glucoseSize, weight: .semibold, design: .rounded))
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
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

    private var readingAgeLabel: String {
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

    private func demoTitle(_ scenario: SyntheticDemoScenario) -> LocalizedStringKey {
        switch scenario {
        case .current: "demo.current"
        case .stale: "demo.stale"
        case .disconnected: "demo.disconnected"
        case .warmUp: "demo.warmup"
        case .sensorError: "demo.error"
        case .expired: "demo.expired"
        case .connectedNoData: "demo.connected_no_data"
        }
    }
}
