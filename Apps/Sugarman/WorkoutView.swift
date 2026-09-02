// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Sugarman contributors

import SugarmanDomain
import SwiftUI

struct WorkoutView: View {
    @Environment(AppModel.self) private var model
    @State private var editorMode: EditorMode?

    private enum EditorMode: Identifiable {
        case new

        var id: String { "new" }
    }

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
                savedWorkoutsSection
                if let plan = model.selectedWorkoutPlan,
                   let target = model.selectedWorkoutPhaseTarget {
                    Section("workout.selected") {
                        SelectedWorkoutTargetRow(plan: plan, target: target)
                    }
                }
                recordedWorkoutsSection
            }
            .navigationTitle("workout.title")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button {
                            editorMode = .new
                        } label: {
                            Label("workout.add", systemImage: "plus")
                        }
                        Button {
                            Task { await model.addCodexTwoDayRide() }
                        } label: {
                            Label("workout.add_codex_template", systemImage: "text.book.closed")
                        }
                    } label: {
                        Label("workout.add", systemImage: "plus")
                    }
                    .accessibilityLabel(Text("workout.add"))
                }
            }
            .sheet(item: $editorMode) { _ in
                WorkoutPlanEditorView()
            }
        }
    }

    @ViewBuilder
    private var savedWorkoutsSection: some View {
        Section {
            if model.workoutPlans.isEmpty {
                Text("workout.saved_empty")
                    .foregroundStyle(.secondary)
                Button {
                    Task { await model.addCodexTwoDayRide() }
                } label: {
                    Label("workout.add_codex_template", systemImage: "text.book.closed")
                }
                Button {
                    editorMode = .new
                } label: {
                    Label("workout.create", systemImage: "plus.circle")
                }
            } else {
                Button {
                    model.clearWorkoutSelection()
                } label: {
                    HStack(spacing: 12) {
                        Label("workout.none", systemImage: "circle.slash")
                        Spacer(minLength: 4)
                        if model.selectedWorkoutPlanID == nil {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.tint)
                                .accessibilityHidden(true)
                        }
                    }
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(model.selectedWorkoutPlanID == nil ? .isSelected : [])

                ForEach(model.workoutPlans) { plan in
                    NavigationLink {
                        WorkoutPlanDetailView(plan: plan)
                    } label: {
                        workoutPlanRow(plan)
                    }
                }
                .onDelete { offsets in
                    let ids = offsets.map { model.workoutPlans[$0].id }
                    Task {
                        for id in ids {
                            await model.deleteWorkoutPlan(id)
                        }
                    }
                }
            }
        } header: {
            Text("workout.saved")
        } footer: {
            Text("workout.saved_footer")
        }
    }

    @ViewBuilder
    private var recordedWorkoutsSection: some View {
        Section("workout.recorded") {
            if model.visibleWorkouts.isEmpty {
                Text("workout.recorded_empty")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(model.visibleWorkouts) { workout in
                    recordedWorkoutRow(workout)
                }
            }
        }
    }

    private func workoutPlanRow(_ plan: WorkoutPlan) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "figure.outdoor.cycle")
                .foregroundStyle(.tint)
                .imageScale(.large)
            VStack(alignment: .leading, spacing: 4) {
                Text(plan.name)
                    .font(.headline)
                Text(plan.activityType)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(
                    String(
                        format: String(localized: "workout.phase_count"),
                        locale: .current,
                        plan.phases.count
                    )
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            if model.selectedWorkoutPlanID == plan.id {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.tint)
                    .accessibilityHidden(true)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func recordedWorkoutRow(_ workout: WorkoutContext) -> some View {
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
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            Text("\(workout.activityType.capitalized), \(timeRange(workout)), \(countText)")
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

struct SelectedWorkoutTargetRow: View {
    @Environment(AppModel.self) private var model

    let plan: WorkoutPlan
    let target: WorkoutPhaseTarget

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(plan.name)
                    .font(.headline)
                Spacer()
                Text(phaseLabel(target.phase))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Text(target.label)
                .font(.subheadline)
            Text(rangeText)
                .font(.body.monospacedDigit())
            if let floor = target.floorMgdl {
                Text(
                    String(
                        format: String(localized: "workout.floor_format"),
                        locale: .current,
                        floorValue(floor),
                        model.preferredUnit.displaySymbol
                    )
                )
                .font(.footnote)
                .foregroundStyle(.orange)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("\(plan.name), \(phaseLabel(target.phase)), \(target.label), \(rangeText)"))
    }

    private var rangeText: String {
        let mgdl = String(
            format: String(localized: "workout.range_mgdl"),
            locale: .current,
            target.lowerMgdl,
            target.upperMgdl
        )
        let mmol = String(
            format: String(localized: "workout.range_mmol"),
            locale: .current,
            target.lowerValue(in: .millimolesPerLiter),
            target.upperValue(in: .millimolesPerLiter)
        )
        switch model.preferredUnit {
        case .milligramsPerDeciliter:
            return mgdl
        case .millimolesPerLiter:
            return mmol
        }
    }

    private func floorValue(_ value: Int) -> Double {
        switch model.preferredUnit {
        case .milligramsPerDeciliter:
            Double(value)
        case .millimolesPerLiter:
            Double(value) / 18.0
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
}
