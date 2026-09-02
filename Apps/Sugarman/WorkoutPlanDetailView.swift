// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Sugarman contributors

import SugarmanDomain
import SwiftUI

struct WorkoutPlanDetailView: View {
    @Environment(AppModel.self) private var model

    let plan: WorkoutPlan
    @State private var selectedPhaseID: UUID
    @State private var editingPlan: WorkoutPlan?

    init(plan: WorkoutPlan) {
        self.plan = plan
        _selectedPhaseID = State(initialValue: plan.phases.first?.id ?? UUID())
    }

    private var selectedTarget: WorkoutPhaseTarget? {
        currentPlan.phases.first { $0.id == selectedPhaseID }
    }

    private var currentPlan: WorkoutPlan {
        model.workoutPlans.first { $0.id == plan.id } ?? plan
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

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(currentPlan.activityType)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                if currentPlan.phases.count > 1 {
                    Picker("workout.phase", selection: $selectedPhaseID) {
                        ForEach(currentPlan.phases) { target in
                            Text(phaseLabel(target.phase))
                                .tag(target.id)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                if let selectedTarget {
                    WorkoutPhaseTargetCard(target: selectedTarget)
                    WorkoutGlucoseChart(
                        samples: chartSamples,
                        target: selectedTarget,
                        unit: model.preferredUnit
                    )
                    if let notes = selectedTarget.notes, !notes.isEmpty {
                        Text(notes)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                if let notes = currentPlan.notes, !notes.isEmpty {
                    Text(notes)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Text(verbatim: ProductCopy.athleteInsightOnly)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding()
        }
        .navigationTitle(currentPlan.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("workout.edit") {
                    editingPlan = currentPlan
                }
            }
        }
        .sheet(item: $editingPlan) { plan in
            WorkoutPlanEditorView(plan: plan)
        }
        .onAppear {
            model.selectWorkoutPlan(plan.id)
            if let modelPhaseID = model.selectedWorkoutPhaseID,
               currentPlan.phases.contains(where: { $0.id == modelPhaseID }) {
                selectedPhaseID = modelPhaseID
            } else if let first = currentPlan.phases.first {
                selectedPhaseID = first.id
                model.selectWorkoutPhase(first.id)
            }
        }
        .onChange(of: selectedPhaseID) { _, newValue in
            model.selectWorkoutPhase(newValue)
        }
    }
}

struct WorkoutPhaseTargetCard: View {
    @Environment(AppModel.self) private var model

    let target: WorkoutPhaseTarget

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(target.label)
                    .font(.headline)
                Spacer()
                Text(phaseLabel(target.phase))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Text(rangeText)
                .font(.title3.monospacedDigit())
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
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private var rangeText: String {
        switch model.preferredUnit {
        case .milligramsPerDeciliter:
            return String(
                format: String(localized: "workout.range_mgdl"),
                locale: .current,
                target.lowerMgdl,
                target.upperMgdl
            )
        case .millimolesPerLiter:
            return String(
                format: String(localized: "workout.range_mmol"),
                locale: .current,
                target.lowerValue(in: .millimolesPerLiter),
                target.upperValue(in: .millimolesPerLiter)
            )
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
