// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Sugarman contributors

import Charts
import SugarmanDomain
import SwiftUI

/// A compact glucose timeline. A selected workout target is rendered as a
/// translucent band so the athlete can compare their readings with their own
/// saved reference range.
struct WorkoutGlucoseChart: View {
    let samples: [GlucoseSample]
    let target: WorkoutPhaseTarget?
    let unit: GlucoseUnit

    private var sortedSamples: [GlucoseSample] {
        samples.sorted { lhs, rhs in
            if lhs.sensorTimestamp != rhs.sensorTimestamp {
                return lhs.sensorTimestamp < rhs.sensorTimestamp
            }
            return lhs.sensorIndex < rhs.sensorIndex
        }
    }

    private var dateDomain: ClosedRange<Date>? {
        guard let first = sortedSamples.first, let last = sortedSamples.last else {
            return nil
        }
        if first.sensorTimestamp == last.sensorTimestamp {
            let padding = 5 * 60.0
            return first.sensorTimestamp.addingTimeInterval(-padding)...last.sensorTimestamp.addingTimeInterval(padding)
        }
        return first.sensorTimestamp...last.sensorTimestamp
    }

    private var yDomain: ClosedRange<Double> {
        let values = sortedSamples.map { $0.value(in: unit) }
        var lower = values.min() ?? 0
        var upper = values.max() ?? 1
        if let target {
            lower = min(lower, target.lowerValue(in: unit))
            upper = max(upper, target.upperValue(in: unit))
            if let floor = target.floorValue(in: unit) {
                lower = min(lower, floor)
            }
        }
        let spread = max(upper - lower, unit == .milligramsPerDeciliter ? 10 : 1)
        let padding = spread * 0.15
        return max(0, lower - padding)...upper + padding
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if sortedSamples.isEmpty {
                Text("workout.chart_empty")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 24)
            } else if let dateDomain {
                Chart {
                    if let target {
                        RectangleMark(
                            xStart: .value("workout.chart_target_start", dateDomain.lowerBound),
                            xEnd: .value("workout.chart_target_end", dateDomain.upperBound),
                            yStart: .value("workout.chart_target_low", target.lowerValue(in: unit)),
                            yEnd: .value("workout.chart_target_high", target.upperValue(in: unit))
                        )
                        .foregroundStyle(.green.opacity(0.18))

                        RuleMark(y: .value("workout.chart_target_low", target.lowerValue(in: unit)))
                            .foregroundStyle(.green.opacity(0.75))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))

                        if let floor = target.floorValue(in: unit) {
                            RuleMark(y: .value("workout.chart_floor", floor))
                                .foregroundStyle(.orange.opacity(0.85))
                                .lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 2]))
                        }
                    }

                    ForEach(sortedSamples) { sample in
                        LineMark(
                            x: .value("workout.chart_time", sample.sensorTimestamp),
                            y: .value("workout.chart_glucose", sample.value(in: unit))
                        )
                        .foregroundStyle(.blue)
                        .interpolationMethod(.catmullRom)

                        PointMark(
                            x: .value("workout.chart_time", sample.sensorTimestamp),
                            y: .value("workout.chart_glucose", sample.value(in: unit))
                        )
                        .foregroundStyle(.blue)
                    }
                }
                .chartYScale(domain: yDomain)
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 4)) { value in
                        AxisGridLine()
                        AxisTick()
                        AxisValueLabel(format: .dateTime.hour().minute())
                    }
                }
                .chartYAxis {
                    AxisMarks { value in
                        AxisGridLine()
                        AxisTick()
                        AxisValueLabel {
                            if let number = value.as(Double.self) {
                                Text(number.formatted(.number.precision(.fractionLength(unit == .milligramsPerDeciliter ? 0 : 1))))
                            }
                        }
                    }
                }
                .frame(height: 220)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(accessibilityLabel))
            }

            chartLegend
        }
    }

    @ViewBuilder
    private var chartLegend: some View {
        HStack(spacing: 12) {
            Label("workout.chart_readings", systemImage: "circle.fill")
                .foregroundStyle(.blue)
            if let target {
                Label(
                    String(
                        format: String(localized: "workout.chart_target_legend"),
                        locale: .current,
                        target.lowerValue(in: unit),
                        target.upperValue(in: unit),
                        unit.displaySymbol
                    ),
                    systemImage: "rectangle.fill"
                )
                .foregroundStyle(.green)
            }
        }
        .font(.caption)
        .labelStyle(.titleAndIcon)
    }

    private var accessibilityLabel: String {
        let readingCount = String(
            format: String(localized: "workout.chart_accessibility_readings"),
            locale: .current,
            sortedSamples.count
        )
        guard let target else { return readingCount }
        return "\(readingCount), \(targetRangeText(target))"
    }

    private func targetRangeText(_ target: WorkoutPhaseTarget) -> String {
        let range = String(
            format: String(localized: "workout.range_mgdl"),
            locale: .current,
            target.lowerMgdl,
            target.upperMgdl
        )
        let converted = String(
            format: String(localized: "workout.range_mmol"),
            locale: .current,
            target.lowerValue(in: .millimolesPerLiter),
            target.upperValue(in: .millimolesPerLiter)
        )
        return "\(range), \(converted)"
    }
}
