// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Sugarman contributors

import SugarmanDomain
import SwiftUI

struct WorkoutPlanEditorView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    private let existingPlan: WorkoutPlan?

    @State private var draft: WorkoutPlanDraft
    @State private var isSaving = false
    @State private var saveError: String?

    init(plan: WorkoutPlan? = nil) {
        self.existingPlan = plan
        _draft = State(initialValue: WorkoutPlanDraft(plan: plan))
    }

    var body: some View {
        NavigationStack {
            Form {
                if let saveError {
                    Section { Text(saveError).foregroundStyle(.red) }
                }
                Section("workout.editor.details") {
                    TextField("workout.editor.name", text: $draft.name)
                    TextField("workout.editor.activity", text: $draft.activityType)
                }

                Section {
                    ForEach($draft.phases) { $draft in
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
                        draft.phases.remove(atOffsets: offsets)
                    }

                    Button {
                        draft.phases.append(WorkoutPlanDraft.Phase())
                    } label: {
                        Label("workout.editor.add_phase", systemImage: "plus.circle")
                    }
                } header: {
                    Text("workout.editor.phases")
                } footer: {
                    Text("workout.editor.range_footer")
                }

                Section("workout.editor.notes_section") {
                    TextField("workout.editor.plan_notes", text: $draft.notes, axis: .vertical)
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
                    .disabled(!draft.canSave || isSaving)
                }
            }
        }
    }

    private func save() async {
        guard !isSaving, let plan = draft.makePlan() else { return }
        isSaving = true
        let saved: Bool
        if existingPlan == nil {
            saved = await model.addWorkoutPlan(plan)
        } else {
            saved = await model.updateWorkoutPlan(plan)
        }
        isSaving = false
        if saved {
            dismiss()
        } else {
            saveError = model.workoutActionError
        }
    }

    private func phaseLabel(_ phase: WorkoutPhase) -> String {
        switch phase {
        case .preWorkout: String(localized: "workout.phase.pre")
        case .duringWorkout: String(localized: "workout.phase.during")
        case .postWorkout: String(localized: "workout.phase.post")
        case .overnight: String(localized: "workout.phase.overnight")
        }
    }
}
