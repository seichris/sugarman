// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Sugarman contributors

import SugarmanDomain
import SwiftUI

struct WorkoutPlanEditorView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    private let existingPlan: WorkoutPlan?

    @State private var name = ""
    @State private var activityType = "Cycling"
    @State private var notes = ""
    @State private var phases = [DraftPhase()]
    @State private var isSaving = false

    private struct DraftPhase: Identifiable {
        let id: UUID
        var phase: WorkoutPhase = .preWorkout
        var label = "Pre-workout"
        var lower = "90"
        var upper = "130"
        var floor = ""
        var notes = ""

        init() {
            id = UUID()
        }

        init(target: WorkoutPhaseTarget) {
            self.id = target.id
            self.phase = target.phase
            self.label = target.label
            self.lower = String(target.lowerMgdl)
            self.upper = String(target.upperMgdl)
            self.floor = target.floorMgdl.map(String.init) ?? ""
            self.notes = target.notes ?? ""
        }
    }

    init(plan: WorkoutPlan? = nil) {
        self.existingPlan = plan
        _name = State(initialValue: plan?.name ?? "")
        _activityType = State(initialValue: plan?.activityType ?? "Cycling")
        _notes = State(initialValue: plan?.notes ?? "")
        _phases = State(initialValue: plan?.phases.map { DraftPhase(target: $0) } ?? [DraftPhase()])
    }

    private var canSave: Bool {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !activityType.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !phases.isEmpty else {
            return false
        }
        return phases.allSatisfy { draft in
            guard let lower = Int(draft.lower.trimmingCharacters(in: .whitespacesAndNewlines)),
                  let upper = Int(draft.upper.trimmingCharacters(in: .whitespacesAndNewlines)),
                  lower > 0,
                  upper >= lower else {
                return false
            }
            if let floor = parsedFloor(draft), floor > 0, floor <= lower {
                return true
            }
            return draft.floor.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("workout.editor.details") {
                    TextField("workout.editor.name", text: $name)
                    TextField("workout.editor.activity", text: $activityType)
                }

                Section {
                    ForEach($phases) { $draft in
                        VStack(alignment: .leading, spacing: 10) {
                            Picker("workout.editor.phase", selection: $draft.phase) {
                                ForEach(WorkoutPhase.allCases) { phase in
                                    Text(phaseLabel(phase)).tag(phase)
                                }
                            }
                            TextField("workout.editor.phase_label", text: $draft.label)
                            HStack {
                                TextField("workout.editor.lower", text: $draft.lower)
                                    .keyboardType(.numberPad)
                                Text("–")
                                    .foregroundStyle(.secondary)
                                TextField("workout.editor.upper", text: $draft.upper)
                                    .keyboardType(.numberPad)
                            }
                            TextField("workout.editor.floor", text: $draft.floor)
                                .keyboardType(.numberPad)
                            TextField("workout.editor.notes", text: $draft.notes, axis: .vertical)
                                .lineLimit(2...4)
                        }
                        .padding(.vertical, 4)
                    }
                    .onDelete { offsets in
                        phases.remove(atOffsets: offsets)
                    }

                    Button {
                        phases.append(DraftPhase())
                    } label: {
                        Label("workout.editor.add_phase", systemImage: "plus.circle")
                    }
                } header: {
                    Text("workout.editor.phases")
                } footer: {
                    Text("workout.editor.range_footer")
                }

                Section("workout.editor.notes_section") {
                    TextField("workout.editor.plan_notes", text: $notes, axis: .vertical)
                        .lineLimit(3...6)
                }

                Section {
                    Text(verbatim: ProductCopy.athleteInsightOnly)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle(existingPlan == nil ? "workout.editor.title" : "workout.editor.edit_title")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("workout.editor.cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "workout.editor.saving" : "workout.editor.save") {
                        Task { await save() }
                    }
                    .disabled(!canSave || isSaving)
                }
            }
        }
    }

    private func save() async {
        guard let plan = makePlan() else { return }
        isSaving = true
        if existingPlan == nil {
            await model.addWorkoutPlan(plan)
        } else {
            await model.updateWorkoutPlan(plan)
        }
        isSaving = false
        dismiss()
    }

    private func makePlan() -> WorkoutPlan? {
        guard canSave else { return nil }
        let targets = phases.compactMap { draft -> WorkoutPhaseTarget? in
            guard let lower = Int(draft.lower.trimmingCharacters(in: .whitespacesAndNewlines)),
                  let upper = Int(draft.upper.trimmingCharacters(in: .whitespacesAndNewlines)) else {
                return nil
            }
            let label = draft.label.trimmingCharacters(in: .whitespacesAndNewlines)
            let phaseNotes = draft.notes.trimmingCharacters(in: .whitespacesAndNewlines)
            return WorkoutPhaseTarget(
                phase: draft.phase,
                label: label.isEmpty ? phaseLabel(draft.phase) : label,
                lowerMgdl: lower,
                upperMgdl: upper,
                floorMgdl: parsedFloor(draft),
                notes: phaseNotes.isEmpty ? nil : phaseNotes
            )
        }
        guard targets.count == phases.count else { return nil }
        let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        return WorkoutPlan(
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            activityType: activityType.trimmingCharacters(in: .whitespacesAndNewlines),
            phases: targets,
            notes: trimmedNotes.isEmpty ? nil : trimmedNotes
        )
    }

    private func parsedFloor(_ draft: DraftPhase) -> Int? {
        let value = draft.floor.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }
        return Int(value)
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
