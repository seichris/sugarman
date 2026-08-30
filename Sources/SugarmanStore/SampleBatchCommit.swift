// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Sugarman contributors

import Foundation
import SugarmanDomain

/// Payload-free result of one atomic sample-batch commit.
///
/// Cursor values remain available to the coordinator, but descriptions and
/// reflection intentionally expose only counts and booleans so lifecycle logs
/// cannot publish sensor record indexes.
public struct SampleBatchCommitResult:
    Sendable, Equatable, CustomStringConvertible, CustomDebugStringConvertible,
    CustomReflectable
{
    public let insertedCount: Int
    public let duplicateCount: Int
    public let gapRangeCount: Int
    public let lastReceivedIndex: UInt32?
    public let lastCommittedIndex: UInt32?

    public var hasGaps: Bool { gapRangeCount > 0 }

    public init(
        insertedCount: Int,
        duplicateCount: Int,
        gapRangeCount: Int,
        lastReceivedIndex: UInt32?,
        lastCommittedIndex: UInt32?
    ) {
        self.insertedCount = insertedCount
        self.duplicateCount = duplicateCount
        self.gapRangeCount = gapRangeCount
        self.lastReceivedIndex = lastReceivedIndex
        self.lastCommittedIndex = lastCommittedIndex
    }

    public var description: String {
        "SampleBatchCommitResult(inserted: \(insertedCount), duplicates: "
            + "\(duplicateCount), gapRanges: \(gapRangeCount), "
            + "receivedCursorPresent: \(lastReceivedIndex != nil), "
            + "committedCursorPresent: \(lastCommittedIndex != nil))"
    }

    public var debugDescription: String { description }

    public var customMirror: Mirror {
        Mirror(
            self,
            children: [
                "insertedCount": insertedCount,
                "duplicateCount": duplicateCount,
                "gapRangeCount": gapRangeCount,
                "receivedCursorPresent": lastReceivedIndex != nil,
                "committedCursorPresent": lastCommittedIndex != nil,
            ],
            displayStyle: .struct
        )
    }
}

struct SampleBatchMutationPlan {
    let samplesToInsert: [GlucoseSample]
    let result: SampleBatchCommitResult
}

enum SampleBatchCommitPlanner {
    static func makePlan(
        session: SensorSession,
        existingSamples: [GlucoseSample],
        incomingSamples: [GlucoseSample]
    ) throws -> SampleBatchMutationPlan {
        guard incomingSamples.allSatisfy({ $0.sessionID == session.id }) else {
            throw StoreError.sampleSessionMismatch
        }
        guard session.lastRequestedIndex != nil else {
            throw StoreError.historyRequestNotPrepared
        }

        var recordsByIndex: [UInt32: GlucoseSample] = [:]
        for sample in existingSamples {
            if let existing = recordsByIndex[sample.sensorIndex],
               !sameSensorRecord(existing, sample) {
                throw StoreError.conflictingSample(sample.id)
            }
            recordsByIndex[sample.sensorIndex] = sample
        }

        var samplesToInsert: [GlucoseSample] = []
        var incomingByIndex: [UInt32: GlucoseSample] = [:]
        var duplicateCount = 0
        for sample in incomingSamples {
            if let earlier = incomingByIndex[sample.sensorIndex] {
                guard sameSensorRecord(earlier, sample) else {
                    throw StoreError.conflictingSample(sample.id)
                }
                duplicateCount += 1
                continue
            }
            incomingByIndex[sample.sensorIndex] = sample

            if let existing = recordsByIndex[sample.sensorIndex] {
                guard sameSensorRecord(existing, sample) else {
                    throw StoreError.conflictingSample(sample.id)
                }
                duplicateCount += 1
            } else {
                recordsByIndex[sample.sensorIndex] = sample
                samplesToInsert.append(sample)
            }
        }

        let incomingMaximum = incomingSamples.map(\.sensorIndex).max()
        let lastReceived = [session.lastReceivedIndex, incomingMaximum]
            .compactMap { $0 }
            .max()
        let cursor = contiguousCursor(
            session: session,
            storedIndices: Set(recordsByIndex.keys),
            lastReceivedIndex: lastReceived
        )

        return SampleBatchMutationPlan(
            samplesToInsert: samplesToInsert,
            result: SampleBatchCommitResult(
                insertedCount: samplesToInsert.count,
                duplicateCount: duplicateCount,
                gapRangeCount: cursor.gapRangeCount,
                lastReceivedIndex: lastReceived,
                lastCommittedIndex: cursor.lastCommittedIndex
            )
        )
    }

    private static func sameSensorRecord(
        _ lhs: GlucoseSample,
        _ rhs: GlucoseSample
    ) -> Bool {
        lhs.sessionID == rhs.sessionID
            && lhs.sensorIndex == rhs.sensorIndex
            && lhs.sensorTimestamp == rhs.sensorTimestamp
            && lhs.milligramsPerDeciliter == rhs.milligramsPerDeciliter
            && lhs.originalTenthsMillimolesPerLiter
                == rhs.originalTenthsMillimolesPerLiter
            && lhs.trend == rhs.trend
            && lhs.quality == rhs.quality
    }

    private static func contiguousCursor(
        session: SensorSession,
        storedIndices: Set<UInt32>,
        lastReceivedIndex: UInt32?
    ) -> (lastCommittedIndex: UInt32?, gapRangeCount: Int) {
        let firstUncommitted: UInt32?
        if let committed = session.lastCommittedIndex {
            firstUncommitted = committed == .max ? nil : committed + 1
        } else {
            firstUncommitted = session.lastRequestedIndex
        }
        guard let firstUncommitted, let upper = lastReceivedIndex,
              firstUncommitted <= upper else {
            return (session.lastCommittedIndex, 0)
        }

        let sorted = storedIndices
            .filter { $0 >= firstUncommitted && $0 <= upper }
            .sorted()
        var expected: UInt32? = firstUncommitted
        var lastCommitted = session.lastCommittedIndex
        var gapRangeCount = 0
        var contiguous = true

        for index in sorted {
            guard let currentExpected = expected else { break }
            if index > currentExpected {
                gapRangeCount += 1
                contiguous = false
            }
            if contiguous, index == currentExpected {
                lastCommitted = index
            }
            expected = index == .max ? nil : index + 1
        }

        if let expected, expected <= upper {
            gapRangeCount += 1
        }
        return (lastCommitted, gapRangeCount)
    }
}
