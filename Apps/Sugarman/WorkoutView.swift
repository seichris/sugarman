// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Sugarman contributors

import SugarmanDomain
import SwiftUI

struct WorkoutView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text(verbatim: ProductCopy.athleteInsightOnly)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                if model.isSyntheticDemo {
                    Section {
                        SyntheticDemoBanner()
                            .listRowInsets(EdgeInsets())
                            .listRowBackground(Color.clear)
                    }
                }
                Section("workout.list") {
                    if model.visibleWorkouts.isEmpty {
                        Text("workout.empty")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(model.visibleWorkouts) { workout in
                            workoutRow(workout)
                        }
                    }
                }
            }
            .navigationTitle("workout.title")
        }
    }

    private func workoutRow(_ workout: WorkoutContext) -> some View {
        let overlapping = model.samples(overlapping: workout)
        let countText = String(
            format: String(localized: "workout.glucose_count_format"),
            locale: .current,
            overlapping.count
        )
        return VStack(alignment: .leading, spacing: 6) {
            Text(workout.activityType.capitalized)
                .font(.headline)
            Text(timeRange(workout))
                .font(.subheadline)
            if let summary = workout.summary {
                Text(summary)
                    .font(.footnote)
            }
            Text(countText)
            .font(.footnote)
            .foregroundStyle(.secondary)
            Text("workout.no_advice")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            Text("\(workout.activityType.capitalized), \(timeRange(workout)), \(countText), \(String(localized: "workout.no_advice"))")
        )
    }

    private func timeRange(_ workout: WorkoutContext) -> String {
        let formatter = DateIntervalFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        if let end = workout.end {
            return formatter.string(from: workout.start, to: end)
        }
        return workout.start.formatted(date: .abbreviated, time: .shortened)
    }
}
