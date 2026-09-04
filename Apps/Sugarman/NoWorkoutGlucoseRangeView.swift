// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Sugarman contributors

import Foundation
import SugarmanDomain
import SwiftUI

struct NoWorkoutGlucoseRangeView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var lowerValue = 70.0
    @State private var upperValue = 140.0
    @State private var didLoad = false

    private var valueFormat: FloatingPointFormatStyle<Double> {
        .number.precision(
            .fractionLength(model.preferredUnit == .milligramsPerDeciliter ? 0 : 1)
        )
    }

    private var editedRange: GlucoseReferenceRange? {
        guard lowerValue.isFinite,
              upperValue.isFinite,
              lowerValue > 0,
              upperValue > lowerValue,
              lowerValue <= 500,
              upperValue <= 500 else { return nil }
        let conversion = model.preferredUnit == .milligramsPerDeciliter ? 1.0 : 18.0
        let range = GlucoseReferenceRange(
            lowerMgdl: Int((lowerValue * conversion).rounded()),
            upperMgdl: Int((upperValue * conversion).rounded())
        )
        return range.isValid && range.upperMgdl <= 500 ? range : nil
    }

    var body: some View {
        Form {
            Section {
                rangeField("workout.no_workout_range.lower", value: $lowerValue)
                rangeField("workout.no_workout_range.upper", value: $upperValue)
            } header: {
                Text("workout.no_workout_range.section")
            } footer: {
                Text("workout.no_workout_range.footer")
            }

            Section("workout.no_workout_range.default_section") {
                LabeledContent("workout.no_workout_range.default_label") {
                    Text(defaultRangeText)
                        .monospacedDigit()
                }
                Button("workout.no_workout_range.reset") {
                    model.resetNoWorkoutGlucoseRange()
                    loadFields()
                }
            }

            Section("workout.no_workout_range.about_section") {
                Text("workout.no_workout_range.about")
                Link(
                    "workout.no_workout_range.ada_source",
                    destination: URL(string: "https://diabetes.org/about-diabetes/diagnosis")!
                )
                Link(
                    "workout.no_workout_range.cgm_source",
                    destination: URL(string: "https://diabetesjournals.org/care/article/42/8/1593/36184/Clinical-Targets-for-Continuous-Glucose-Monitoring")!
                )
            }
        }
        .navigationTitle("workout.no_workout_range.title")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("common.save") {
                    guard let editedRange else { return }
                    model.updateNoWorkoutGlucoseRange(editedRange)
                    dismiss()
                }
                .disabled(editedRange == nil)
            }
        }
        .onAppear {
            guard !didLoad else { return }
            didLoad = true
            loadFields()
        }
    }

    private func rangeField(
        _ label: LocalizedStringKey,
        value: Binding<Double>
    ) -> some View {
        HStack {
            Text(label)
            Spacer()
            TextField("", value: value, format: valueFormat)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 90)
            Text(model.preferredUnit.displaySymbol)
                .foregroundStyle(.secondary)
        }
    }

    private var defaultRangeText: String {
        rangeText(.healthyAdultDefault)
    }

    private func rangeText(_ range: GlucoseReferenceRange) -> String {
        String(
            format: "%@–%@ %@",
            range.lowerValue(in: model.preferredUnit).formatted(valueFormat),
            range.upperValue(in: model.preferredUnit).formatted(valueFormat),
            model.preferredUnit.displaySymbol
        )
    }

    private func loadFields() {
        lowerValue = model.noWorkoutGlucoseRange.lowerValue(in: model.preferredUnit)
        upperValue = model.noWorkoutGlucoseRange.upperValue(in: model.preferredUnit)
    }
}

struct NoWorkoutGlucoseRangeLabel: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "rectangle.fill")
                .foregroundStyle(.green)
                .imageScale(.large)
            VStack(alignment: .leading, spacing: 4) {
                Text("workout.no_workout_range.title")
                    .font(.headline)
                Text(rangeText)
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var rangeText: String {
        let range = model.noWorkoutGlucoseRange
        let fractionDigits = model.preferredUnit == .milligramsPerDeciliter ? 0 : 1
        return String(
            format: "%@–%@ %@",
            range.lowerValue(in: model.preferredUnit).formatted(
                .number.precision(.fractionLength(fractionDigits))
            ),
            range.upperValue(in: model.preferredUnit).formatted(
                .number.precision(.fractionLength(fractionDigits))
            ),
            model.preferredUnit.displaySymbol
        )
    }
}
