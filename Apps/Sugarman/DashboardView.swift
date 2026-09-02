// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Sugarman contributors

import Charts
import SafetyEngine
import SugarmanDomain
import SwiftUI

struct DashboardView: View {
    @Environment(AppModel.self) private var model
    @State private var selectedRange = GlucoseHistoryRange.threeHours
    @State private var selectedChartTimestamp: Date?
    @State private var interactionChartTimestamp: Date?
    @State private var chartFrame = CGRect.null
    @ScaledMetric(relativeTo: .largeTitle) private var glucoseSize: CGFloat = 96

    var body: some View {
        NavigationStack {
            TimelineView(.periodic(from: .now, by: 30)) { context in
                dashboardBody(now: context.date)
            }
            .background(LivePalette.background.ignoresSafeArea())
            .foregroundStyle(LivePalette.primaryText)
            .toolbarBackground(LivePalette.background, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
        .preferredColorScheme(.dark)
    }

    private func dashboardBody(now: Date) -> some View {
        let assessment = model.assessment(at: now)
        let timeline = GlucoseTimeline(
            samples: model.activeSamples,
            endingAt: now,
            range: selectedRange
        )
        return ScrollView {
            VStack(spacing: 24) {
                if model.isSyntheticDemo {
                    SyntheticDemoBanner()
                }
                if let demoLoadError = model.demoLoadError {
                    errorText(demoLoadError)
                }
                if let storeErrorMessage = model.storeErrorMessage {
                    errorText(storeErrorMessage)
                }

                if contentMode == .sensorOnboarding {
                    sensorOnboardingPrompt(assessment: assessment)
                } else {
                    readingHero(assessment)
                    rangePicker
                    glucoseChart(
                        timeline: timeline,
                        target: model.selectedWorkoutPhaseTarget
                    )

                    if let plan = model.selectedWorkoutPlan,
                       let target = model.selectedWorkoutPhaseTarget {
                        liveWorkoutContext(plan: plan, target: target)
                    }

                    if !assessment.showsValueAsCurrent, !timeline.samples.isEmpty {
                        Label(
                            chartNotCurrentKey,
                            systemImage: "exclamationmark.triangle"
                        )
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(LivePalette.warning)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
        .refreshable {
            await model.refresh()
        }
        .coordinateSpace(name: "dashboard")
        .simultaneousGesture(
            SpatialTapGesture(coordinateSpace: .named("dashboard"))
                .onEnded { event in
                    if !chartFrame.contains(event.location) {
                        selectedChartTimestamp = nil
                    }
                }
        )
    }

    private var contentMode: LiveDashboardContentMode {
        LiveDashboardContentMode.resolve(
            sampleCount: model.activeSamples.count,
            isSyntheticDemo: model.isSyntheticDemo
        )
    }

    private func sensorOnboardingPrompt(
        assessment: SafetyAssessment
    ) -> some View {
        VStack(spacing: 20) {
            readingHero(assessment)

#if !SUGARMAN_DEVICE_TEST
            if model.hasSensorProvisioning,
               model.sensorConnectionActivity == .connecting
                || model.sensorConnectionActivity == .synchronizing
                || model.sensorConnectionActivity == .reconnecting {
                ProgressView()
                    .tint(.white)
                sensorActivityText
                    .font(.headline)
                    .multilineTextAlignment(.center)
                Text("live.connection_background_hint")
                    .font(.footnote)
                    .foregroundStyle(LivePalette.secondaryText)
                    .multilineTextAlignment(.center)
            } else {
                sensorSetupContent
            }
#else
            sensorSetupContent
#endif
        }
        .frame(maxWidth: 560)
        .frame(maxWidth: .infinity)
        .padding(.top, 28)
    }

    @ViewBuilder
    private func readingHero(_ assessment: SafetyAssessment) -> some View {
        if model.latestSample == nil {
            missingReadingHero
        } else {
#if !SUGARMAN_DEVICE_TEST
            if model.isSensorConnectionEnabled,
               model.sensorConnectionActivity != .live {
                unavailableReadingHero(sensorActivityText, assessment: assessment)
            } else {
                assessmentReadingHero(assessment)
            }
#else
            assessmentReadingHero(assessment)
#endif
        }
    }

    @ViewBuilder
    private func assessmentReadingHero(_ assessment: SafetyAssessment) -> some View {
        switch assessment.presentation {
            case .current(let mgdl, _):
                glucoseReadingHero(mgdl: mgdl, assessment: assessment)
            case .empty:
                unavailableReadingHero(Text("dashboard.empty"), assessment: assessment)
            case .connectedNoData:
                unavailableReadingHero(
                    Text("dashboard.connected_no_data"),
                    assessment: assessment
                )
            case .disconnected:
                unavailableReadingHero(Text("dashboard.disconnected"), assessment: assessment)
            case .stale:
                unavailableReadingHero(Text("dashboard.stale"), assessment: assessment)
            case .warmUp:
                unavailableReadingHero(Text("dashboard.warmup"), assessment: assessment)
            case .sensorError:
                unavailableReadingHero(Text("dashboard.error"), assessment: assessment)
            case .expired:
                unavailableReadingHero(Text("dashboard.expired"), assessment: assessment)
            case .questionable:
                if let mgdl = assessment.unvalidatedGlucoseMgdl {
                    glucoseReadingHero(mgdl: mgdl, assessment: assessment)
                } else {
                    unavailableReadingHero(
                        Text("dashboard.native_state_unvalidated"),
                        assessment: assessment
                    )
                }
        }
    }

    @ViewBuilder
    private var sensorSetupContent: some View {
        Image(systemName: "sensor.tag.radiowaves.forward")
            .font(.system(size: 52, weight: .light))
            .foregroundStyle(LivePalette.secondaryText)
            .accessibilityHidden(true)

        VStack(spacing: 8) {
            Text("live.sensor_setup_title")
                .font(.title2.weight(.semibold))
            Text("live.sensor_setup_body")
                .font(.body)
                .foregroundStyle(LivePalette.secondaryText)
                .multilineTextAlignment(.center)
        }

        NavigationLink {
            SensorOnboardingView(embeddedInNavigationStack: true)
        } label: {
            Label("live.sensor_setup_action", systemImage: "arrow.right.circle.fill")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
        }
        .buttonStyle(.borderedProminent)
        .tint(.white)
        .foregroundStyle(.black)
        .accessibilityHint(Text("live.sensor_setup_hint"))
    }

    private var chartNotCurrentKey: LocalizedStringKey {
#if !SUGARMAN_DEVICE_TEST
        if model.sensorConnectionActivity == .live {
            return "live.chart_native_state_unvalidated"
        }
#endif
        return "live.chart_not_current"
    }

#if !SUGARMAN_DEVICE_TEST
    private var sensorActivityText: Text {
        switch model.sensorConnectionActivity {
        case .notConfigured:
            return Text("live.connection.not_configured")
        case .stopped:
            return Text("live.connection.stopped")
        case .connecting:
            return Text("live.connection.connecting")
        case .synchronizing:
            return Text("live.connection.synchronizing")
        case .live:
            return Text("live.connection.live")
        case .reconnecting:
            return Text("live.connection.reconnecting")
        case .failed:
            return Text("live.connection.failed")
        }
    }
#endif

    private var missingReadingHero: some View {
        HStack(alignment: .lastTextBaseline, spacing: 12) {
            Text(verbatim: "-")
                .font(.system(size: glucoseSize, weight: .light, design: .rounded))
                .accessibilityLabel(Text("live.no_reading_accessibility"))
            unitToggleButton
        }
        .frame(maxWidth: .infinity, minHeight: 150)
        .accessibilityElement(children: .contain)
    }

    private func glucoseReadingHero(
        mgdl: Int,
        assessment: SafetyAssessment
    ) -> some View {
        HStack(alignment: .center, spacing: 8) {
            Text(compactAgeLabel(assessment.readingAgeSeconds))
                .font(.title3.monospacedDigit())
                .foregroundStyle(LivePalette.secondaryText)
                .frame(minWidth: 70, alignment: .trailing)

            Text(currentGlucoseValue(mgdl: mgdl))
                .font(.system(size: glucoseSize, weight: .light, design: .rounded))
                .monospacedDigit()
                .minimumScaleFactor(0.55)
                .lineLimit(1)
                .layoutPriority(2)
                .accessibilityLabel(Text("dashboard.glucose"))
                .accessibilityValue(
                    Text(currentReadingAccessibilityValue(mgdl: mgdl, assessment: assessment))
                )

            VStack(alignment: .leading, spacing: 4) {
                Image(systemName: trendSymbol(model.latestSample?.trend ?? .unknown))
                    .font(.system(size: 48, weight: .light))
                    .accessibilityHidden(true)
                unitToggleButton
            }
            .frame(minWidth: 78, alignment: .leading)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
    }

    private func unavailableReadingHero(
        _ message: Text,
        assessment: SafetyAssessment
    ) -> some View {
        VStack(spacing: 10) {
            message
                .font(.largeTitle.weight(.light))
                .multilineTextAlignment(.center)
            Text(compactAgeLabel(assessment.readingAgeSeconds))
                .font(.title3.monospacedDigit())
                .foregroundStyle(LivePalette.secondaryText)
            unitToggleButton
        }
        .frame(maxWidth: .infinity, minHeight: 150)
        .accessibilityElement(children: .contain)
    }

    private var rangePicker: some View {
        HStack(spacing: 4) {
            ForEach(GlucoseHistoryRange.allCases) { range in
                Button {
                    selectedRange = range
                    selectedChartTimestamp = nil
                    interactionChartTimestamp = nil
                } label: {
                    Text(rangeTitle(range))
                        .font(.subheadline.weight(.medium))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .padding(.vertical, 6)
                        .padding(.horizontal, 2)
                        .frame(maxWidth: .infinity)
                        .background {
                            if selectedRange == range {
                                Capsule()
                                    .strokeBorder(LivePalette.primaryText, lineWidth: 1.5)
                            }
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(rangeAccessibilityLabel(range)))
                .accessibilityValue(Text(rangeSelectionAccessibilityValue(range)))
                .accessibilityAddTraits(selectedRange == range ? .isSelected : [])
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("live.range.label"))
    }

    private func liveWorkoutContext(
        plan: WorkoutPlan,
        target: WorkoutPhaseTarget
    ) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            if plan.phases.count > 1 {
                Picker(
                    "workout.phase",
                    selection: Binding<UUID>(
                        get: { model.selectedWorkoutPhaseID ?? target.id },
                        set: { model.selectWorkoutPhase($0) }
                    )
                ) {
                    ForEach(plan.phases) { phaseTarget in
                        Text(phaseLabel(phaseTarget.phase))
                            .tag(phaseTarget.id)
                    }
                }
                .pickerStyle(.segmented)
            }

            WorkoutPhaseTargetCard(target: target)

            if let notes = target.notes, !notes.isEmpty {
                Text(notes)
                    .font(.footnote)
                    .foregroundStyle(LivePalette.secondaryText)
            }

            if let notes = plan.notes, !notes.isEmpty {
                Text(notes)
                    .font(.footnote)
                    .foregroundStyle(LivePalette.secondaryText)
            }

            Text(verbatim: ProductCopy.athleteInsightOnly)
                .font(.footnote)
                .foregroundStyle(LivePalette.secondaryText)
        }
        .frame(maxWidth: 560, alignment: .leading)
    }

    private func glucoseChart(
        timeline: GlucoseTimeline,
        target: WorkoutPhaseTarget?
    ) -> some View {
        let scale = GlucoseChartScale(unit: model.preferredUnit)
        let selectedSample = nearestSample(
            to: selectedChartTimestamp,
            in: timeline.samples
        )
        return VStack(alignment: .leading, spacing: 8) {
            Text(model.preferredUnit.displaySymbol)
                .font(.caption)
                .foregroundStyle(LivePalette.secondaryText)

            Chart {
                if let target {
                    RectangleMark(
                        xStart: .value("workout.chart_target_start", timeline.start),
                        xEnd: .value("workout.chart_target_end", timeline.end),
                        yStart: .value(
                            "workout.chart_target_low",
                            target.lowerValue(in: model.preferredUnit)
                        ),
                        yEnd: .value(
                            "workout.chart_target_high",
                            target.upperValue(in: model.preferredUnit)
                        )
                    )
                    .foregroundStyle(.green.opacity(0.18))

                    RuleMark(
                        y: .value(
                            "workout.chart_target_low",
                            target.lowerValue(in: model.preferredUnit)
                        )
                    )
                    .foregroundStyle(.green.opacity(0.75))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))

                    if let floor = target.floorValue(in: model.preferredUnit) {
                        RuleMark(y: .value("workout.chart_floor", floor))
                            .foregroundStyle(.orange.opacity(0.85))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 2]))
                    }
                }

                ForEach(scale.gridValues, id: \.self) { gridValue in
                    RuleMark(y: .value("mmol/L guide", gridValue))
                        .foregroundStyle(LivePalette.grid)
                        .lineStyle(
                            StrokeStyle(
                                lineWidth: 0.5,
                                lineCap: .round,
                                dash: [1, 3]
                            )
                        )
                }

                ForEach(timeline.samples) { sample in
                    PointMark(
                        x: .value("Time", sample.sensorTimestamp),
                        y: .value("Glucose", sample.value(in: model.preferredUnit))
                    )
                    .foregroundStyle(LivePalette.readingPoint)
                    .symbol {
                        Circle()
                            .frame(width: 2, height: 2)
                    }
                }

                if let selectedSample {
                    RuleMark(
                        x: .value("Selected time", selectedSample.sensorTimestamp)
                    )
                    .foregroundStyle(LivePalette.selection)
                    .lineStyle(StrokeStyle(lineWidth: 1))
                    .annotation(position: .top, alignment: .center, spacing: 6) {
                        VStack(spacing: 2) {
                            Text(
                                selectedSample.sensorTimestamp,
                                format: .dateTime.hour().minute()
                            )
                            Text(selectedGlucoseValue(selectedSample))
                        }
                        .font(.caption.monospacedDigit().weight(.semibold))
                        .foregroundStyle(LivePalette.primaryText)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(
                            LivePalette.selectionLabelBackground,
                            in: RoundedRectangle(cornerRadius: 6)
                        )
                    }

                    PointMark(
                        x: .value("Selected time", selectedSample.sensorTimestamp),
                        y: .value(
                            "Selected glucose",
                            selectedSample.value(in: model.preferredUnit)
                        )
                    )
                    .foregroundStyle(LivePalette.selection)
                    .symbol {
                        Circle()
                            .frame(width: 10, height: 10)
                    }
                }
            }
            .chartXScale(domain: timeline.start...timeline.end)
            .chartYScale(domain: scale.domain)
            .chartXSelection(value: $interactionChartTimestamp)
            .onChange(of: interactionChartTimestamp) { _, timestamp in
                if let timestamp {
                    selectedChartTimestamp = timestamp
                }
            }
            .onGeometryChange(for: CGRect.self) { proxy in
                proxy.frame(in: .named("dashboard"))
            } action: { frame in
                chartFrame = frame
            }
            .chartLegend(.hidden)
            .chartYAxis {
                AxisMarks(position: .leading, values: scale.tickValues) { value in
                    AxisValueLabel {
                        if let number = value.as(Double.self) {
                            Text(axisValueLabel(number))
                                .foregroundStyle(LivePalette.primaryText)
                        }
                    }
                }
            }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 8)) { _ in
                    AxisGridLine().foregroundStyle(.clear)
                    AxisTick(stroke: StrokeStyle(lineWidth: 0.75))
                        .foregroundStyle(LivePalette.grid)
                    AxisValueLabel(format: .dateTime.hour().minute())
                        .foregroundStyle(LivePalette.primaryText)
                }
            }
            .chartPlotStyle { plotArea in
                plotArea.background(LivePalette.background)
            }
            .frame(minHeight: 390)
            .overlay {
                if timeline.samples.isEmpty {
                    Text("live.chart_empty")
                        .font(.headline)
                        .foregroundStyle(LivePalette.secondaryText)
                }
            }
            .accessibilityLabel(Text("live.chart_accessibility_label"))
            .accessibilityValue(Text(chartAccessibilityValue(timeline.samples.count)))
        }
    }

    private func phaseLabel(_ phase: WorkoutPhase) -> String {
        switch phase {
        case .preWorkout:
            String(localized: "workout.phase.pre")
        case .duringWorkout:
            String(localized: "workout.phase.during")
        case .postWorkout:
            String(localized: "workout.phase.post")
        case .overnight:
            String(localized: "workout.phase.overnight")
        }
    }

    private var unitToggleButton: some View {
        Button {
            model.preferredUnit = model.preferredUnit.alternate
        } label: {
            Text(model.preferredUnit.displaySymbol)
                .font(.title3)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .padding(.horizontal, 4)
                .padding(.vertical, 10)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("dashboard.unit"))
        .accessibilityValue(Text(model.preferredUnit.displaySymbol))
        .accessibilityHint(Text(unitToggleAccessibilityHint))
    }

    private func errorText(_ message: String) -> some View {
        Text(verbatim: message)
            .font(.footnote)
            .foregroundStyle(.red)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func currentGlucoseValue(mgdl: Int) -> String {
        switch model.preferredUnit {
        case .milligramsPerDeciliter:
            return String(format: "%d", locale: .current, mgdl)
        case .millimolesPerLiter:
            let mmol = model.latestSample?.millimolesPerLiter() ?? Double(mgdl) / 18.0
            return String(format: "%.1f", locale: .current, mmol)
        }
    }

    private func selectedGlucoseValue(_ sample: GlucoseSample) -> String {
        switch model.preferredUnit {
        case .milligramsPerDeciliter:
            return String(
                format: "%d mg/dL",
                locale: .current,
                sample.milligramsPerDeciliter
            )
        case .millimolesPerLiter:
            return String(
                format: "%.1f mmol/L",
                locale: .current,
                sample.millimolesPerLiter()
            )
        }
    }

    private func nearestSample(
        to timestamp: Date?,
        in samples: [GlucoseSample]
    ) -> GlucoseSample? {
        guard let timestamp else { return nil }
        return samples.min { left, right in
            abs(left.sensorTimestamp.timeIntervalSince(timestamp))
                < abs(right.sensorTimestamp.timeIntervalSince(timestamp))
        }
    }

    private func compactAgeLabel(_ seconds: TimeInterval?) -> String {
        guard let seconds else { return String(localized: "live.age_unknown") }
        let minutes = max(0, Int(seconds / 60))
        if minutes == 0 {
            return String(localized: "live.age_now")
        }
        if minutes < 60 {
            return String(
                format: String(localized: "live.age_minutes_format"),
                locale: .current,
                minutes
            )
        }
        return String(
            format: String(localized: "live.age_hours_format"),
            locale: .current,
            minutes / 60
        )
    }

    private func trendSymbol(_ trend: GlucoseTrend) -> String {
        switch trend {
        case .unknown: "minus"
        case .fallingQuickly: "arrow.down"
        case .falling: "arrow.down.right"
        case .stable: "arrow.right"
        case .rising: "arrow.up.right"
        case .risingQuickly: "arrow.up"
        }
    }

    private func trendLabel(_ trend: GlucoseTrend) -> String {
        let key = LocalizedStringResource(stringLiteral: "history.trend.\(trend.rawValue)")
        return String(localized: key)
    }

    private func rangeTitle(_ range: GlucoseHistoryRange) -> LocalizedStringKey {
        switch range {
        case .threeHours: "live.range.three_hours"
        case .sixHours: "live.range.six_hours"
        case .twelveHours: "live.range.twelve_hours"
        case .twentyFourHours: "live.range.twenty_four_hours"
        }
    }

    private func rangeAccessibilityLabel(_ range: GlucoseHistoryRange) -> String {
        String(
            format: String(localized: "live.range.hours_accessibility_format"),
            locale: .current,
            range.rawValue
        )
    }

    private func rangeSelectionAccessibilityValue(_ range: GlucoseHistoryRange) -> String {
        if selectedRange == range {
            return String(localized: "live.range.selected")
        }
        return String(localized: "live.range.not_selected")
    }

    private func axisValueLabel(_ value: Double) -> String {
        String(format: "%.0f", locale: .current, value)
    }

    private func currentReadingAccessibilityValue(
        mgdl: Int,
        assessment: SafetyAssessment
    ) -> String {
        [
            currentGlucoseValue(mgdl: mgdl),
            model.preferredUnit.displaySymbol,
            trendLabel(model.latestSample?.trend ?? .unknown),
            compactAgeLabel(assessment.readingAgeSeconds),
        ].joined(separator: ", ")
    }

    private var unitToggleAccessibilityHint: String {
        String(
            format: String(localized: "live.unit_toggle_hint_format"),
            locale: .current,
            model.preferredUnit.alternate.displaySymbol
        )
    }

    private func chartAccessibilityValue(_ count: Int) -> String {
        String(
            format: String(localized: "live.chart_accessibility_value_format"),
            locale: .current,
            count,
            selectedRange.rawValue
        )
    }

}

private enum LivePalette {
    static let background = Color.black
    static let primaryText = Color.white
    static let secondaryText = Color.white.opacity(0.78)
    static let readingPoint = Color.white
    static let grid = Color.gray.opacity(0.65)
    static let selection = Color.yellow
    static let selectionLabelBackground = Color.black.opacity(0.88)
    static let warning = Color.orange
}

#Preview("Live — Current") {
    DashboardView()
        .environment(dashboardPreviewModel(.current))
}

#Preview("Live — Questionable") {
    DashboardView()
        .environment(dashboardPreviewModel(.questionableSample))
}

#Preview("Live — Sensor setup") {
    DashboardView()
        .environment(AppModel(preferredUnit: .millimolesPerLiter))
}

@MainActor
private func dashboardPreviewModel(_ scenario: SyntheticDemoScenario) -> AppModel {
    let fixture = SyntheticDemoCatalog.make(scenario, now: Date())
    let model = AppModel(
        connection: fixture.connection,
        lifecycle: fixture.lifecycle,
        latestSample: fixture.samples.last,
        preferredUnit: .millimolesPerLiter
    )
    model.isSyntheticDemo = true
    model.demoScenario = scenario
    model.demoSessionID = fixture.session.id
    model.selectedSessionID = fixture.session.id
    model.samples = fixture.samples
    model.sessions = [fixture.session]
    model.workouts = fixture.workouts
    model.identities = [fixture.identity]
    return model
}
