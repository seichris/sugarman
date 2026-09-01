// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Sugarman contributors

import Foundation
import SugarmanDomain

/// First history index verified against an owner-authorized official capture.
///
/// The value is operationally required but must remain device-only. String,
/// debug, and reflection views therefore reveal only that an anchor exists.
public struct CaptureBackedHistoryStart:
    Sendable, Equatable, CustomStringConvertible, CustomDebugStringConvertible,
    CustomReflectable
{
    public let sensorIndex: UInt32

    public init(sensorIndex: UInt32) {
        self.sensorIndex = sensorIndex
    }

    public var description: String { "CaptureBackedHistoryStart(index: redacted)" }
    public var debugDescription: String { description }
    public var customMirror: Mirror {
        Mirror(self, children: ["sensorIndex": "redacted"], displayStyle: .struct)
    }
}

public enum HistoryRequestSource: String, Sendable, Equatable {
    case captureBacked
    case durablyPrepared
    case committedOverlap
}

/// Inclusive history request chosen from durable state.
public struct HistoryRequestPlan:
    Sendable, Equatable, CustomStringConvertible, CustomDebugStringConvertible,
    CustomReflectable
{
    public let startingIndex: UInt32
    public let source: HistoryRequestSource

    public init(startingIndex: UInt32, source: HistoryRequestSource) {
        self.startingIndex = startingIndex
        self.source = source
    }

    public var description: String {
        "HistoryRequestPlan(source: \(source.rawValue), startingIndex: redacted)"
    }

    public var debugDescription: String { description }

    public var customMirror: Mirror {
        Mirror(
            self,
            children: [
                "source": source.rawValue,
                "startingIndex": "redacted",
            ],
            displayStyle: .struct
        )
    }
}

/// Crash-safe inclusive-overlap policy.
///
/// - Before any local request, use only the capture-backed device value.
/// - If a request was durably prepared but no contiguous sample committed,
///   repeat that exact request after restart.
/// - Otherwise overlap the last contiguous committed index. The store ignores
///   an equivalent duplicate and a missing next index keeps the cursor pinned.
public enum HistoryCursorPolicy: Sendable {
    public static func plan(
        session: SensorSession,
        captureBackedStart: CaptureBackedHistoryStart
    ) -> HistoryRequestPlan {
        if let committed = session.lastCommittedIndex {
            return HistoryRequestPlan(
                startingIndex: committed,
                source: .committedOverlap
            )
        }
        if let prepared = session.lastRequestedIndex {
            return HistoryRequestPlan(
                startingIndex: prepared,
                source: .durablyPrepared
            )
        }
        return HistoryRequestPlan(
            startingIndex: captureBackedStart.sensorIndex,
            source: .captureBacked
        )
    }
}
