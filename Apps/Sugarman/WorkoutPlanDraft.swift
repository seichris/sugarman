// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Sugarman contributors

import Foundation
import SugarmanDomain

/// Value state used by the editor and host regression tests.
struct WorkoutPlanDraft {
    let existingPlan: WorkoutPlan?
    var name: String
    var activityType: String
    var notes: String
    var phases: [Phase]

    init(plan: WorkoutPlan? = nil) {
        existingPlan = plan
        name = plan?.name ?? ""
        activityType = plan?.activityType ?? "Cycling"
        notes = plan?.notes ?? ""
        phases = plan?.phases.map { Phase(target: $0) } ?? [Phase()]
    }

    struct Phase: Identifiable {
        let id: UUID
        var phase: WorkoutPhase = .preWorkout
        var label = String(localized: "workout.phase.pre")
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


    var canSave: Bool {
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


    func makePlan() -> WorkoutPlan? {
        guard canSave else { return nil }
        let targets = phases.compactMap { draft -> WorkoutPhaseTarget? in
            guard let lower = Int(draft.lower.trimmingCharacters(in: .whitespacesAndNewlines)),
                  let upper = Int(draft.upper.trimmingCharacters(in: .whitespacesAndNewlines)) else {
                return nil
            }
            let label = draft.label.trimmingCharacters(in: .whitespacesAndNewlines)
            let phaseNotes = draft.notes.trimmingCharacters(in: .whitespacesAndNewlines)
            return WorkoutPhaseTarget(
                id: draft.id,
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
            id: existingPlan?.id ?? UUID(),
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            activityType: activityType.trimmingCharacters(in: .whitespacesAndNewlines),
            phases: targets,
            notes: trimmedNotes.isEmpty ? nil : trimmedNotes,
            createdAt: existingPlan?.createdAt ?? Date()
        )
    }

    private func parsedFloor(_ draft: Phase) -> Int? {
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
