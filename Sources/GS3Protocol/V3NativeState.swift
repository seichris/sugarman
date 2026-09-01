// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Sugarman contributors

import SugarmanDomain

/// The five decoded native status fields, without record identity, glucose,
/// timestamps, voltages, or packet bytes.
public struct V3NativeStateFingerprint:
    Sendable, Equatable, Hashable, CustomStringConvertible,
    CustomDebugStringConvertible, CustomReflectable
{
    public let presentCState: Bool
    public let algorithmCState: UInt8
    public let tState: UInt8
    public let dState: UInt8
    public let algorithmReserved: UInt8

    public init(record: V3GlucoseRecord) {
        self.presentCState = record.presentCState
        self.algorithmCState = record.algorithmCState
        self.tState = record.tState
        self.dState = record.dState
        self.algorithmReserved = record.algorithmReserved
    }

    public var description: String {
        "nativeState(presentCState: \(presentCState), algorithmCState: "
            + "\(algorithmCState), tState: \(tState), dState: \(dState), "
            + "algorithmReserved: \(algorithmReserved))"
    }

    public var debugDescription: String { description }

    public var customMirror: Mirror {
        Mirror(
            self,
            children: [
                "presentCState": presentCState,
                "algorithmCState": algorithmCState,
                "tState": tState,
                "dState": dState,
                "algorithmReserved": algorithmReserved,
            ],
            displayStyle: .struct
        )
    }
}

public enum V3NativeStateAssessment: String, Sendable, Equatable {
    case unvalidated

    public var sampleQuality: SampleQuality { .questionable }
}

/// Fail-closed classifier. No fingerprint is promoted until a separately
/// reviewed physical evidence revision establishes the healthy/error mapping.
public enum V3NativeStateClassifier: Sendable {
    public static let evidenceRevision = "unvalidated-native-state-v1"

    public static func assess(
        _ fingerprint: V3NativeStateFingerprint
    ) -> V3NativeStateAssessment {
        _ = fingerprint
        return .unvalidated
    }
}

/// Payload-free batch metadata for future physical correlation.
public struct V3NativeStateSummary:
    Sendable, Equatable, CustomStringConvertible, CustomDebugStringConvertible,
    CustomReflectable
{
    public let recordCount: Int
    public let distinctFingerprints: Set<V3NativeStateFingerprint>

    public init(records: [V3GlucoseRecord]) {
        self.recordCount = records.count
        self.distinctFingerprints = Set(records.map(V3NativeStateFingerprint.init))
    }

    public var description: String {
        let states = distinctFingerprints
            .sorted {
                (
                    $0.presentCState ? 1 : 0,
                    $0.algorithmCState,
                    $0.tState,
                    $0.dState,
                    $0.algorithmReserved
                ) < (
                    $1.presentCState ? 1 : 0,
                    $1.algorithmCState,
                    $1.tState,
                    $1.dState,
                    $1.algorithmReserved
                )
            }
            .map(\.description)
            .joined(separator: "; ")
        return "V3NativeStateSummary(records: \(recordCount), distinctStates: "
            + "\(distinctFingerprints.count), states: [\(states)], payload: omitted)"
    }

    public var debugDescription: String { description }

    public var customMirror: Mirror {
        Mirror(
            self,
            children: [
                "recordCount": recordCount,
                "distinctStateCount": distinctFingerprints.count,
                "payload": "omitted",
            ],
            displayStyle: .struct
        )
    }
}
