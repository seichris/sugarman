// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Sugarman contributors

import GS3Protocol

public enum V3ProbeState: Sendable, Equatable {
    case idle
    case subscribing
    case awaitingAuthentication
    case awaitingEffectiveData
    case completed
    case failed
}

public enum V3ProbeTransmission: Sendable, Equatable {
    case authentication(EncodedFrame)
    case effectiveData(EncodedFrame)

    public var frame: EncodedFrame {
        switch self {
        case .authentication(let frame), .effectiveData(let frame): frame
        }
    }
}

public struct V3ProbeReading:
    Sendable, Equatable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable
{
    public let index: UInt16
    public let glucoseTenthsMillimolesPerLiter: UInt16
    public let trendCode: UInt8
    public let source: V3GlucoseBatchSource

    public var glucoseMillimolesPerLiter: Double {
        Double(glucoseTenthsMillimolesPerLiter) / 10
    }

    public var description: String {
        "V3ProbeReading(index: \(index), glucose: redacted, trendCode: \(trendCode))"
    }

    public var debugDescription: String { description }

    public var customMirror: Mirror {
        Mirror(
            self,
            children: [
                "index": index,
                "glucose": "redacted",
                "trendCode": trendCode,
                "source": source,
            ],
            displayStyle: .struct
        )
    }
}

public enum V3ProbeEffect: Sendable, Equatable {
    case subscribeToNotifications
    case transmit(V3ProbeTransmission)
    case report(V3ProbeReading, liveReadingCount: Int, requiredLiveReadingCount: Int)
    case disconnect
}

public enum V3ProbeError: Error, Sendable, Equatable {
    case invalidTransition(from: V3ProbeState)
    case authenticationRejected(code: UInt8, detail: UInt8)
    case timedOut
    case cancelled
    case unexpectedNotification
}

extension V3ProbeError: CustomStringConvertible {
    public var description: String {
        switch self {
        case .invalidTransition(let state):
            return "Developer probe event is invalid while in \(state)."
        case .authenticationRejected(let code, let detail):
            return "The sensor rejected authentication (code \(code), detail \(detail))."
        case .timedOut:
            return "The bounded developer probe timed out."
        case .cancelled:
            return "The bounded developer probe was cancelled."
        case .unexpectedNotification:
            return "The sensor sent a notification outside the bounded probe protocol."
        }
    }
}

/// One-shot state machine for an already-active owned V3 sensor.
///
/// Its only transmissions are one typed `0xE2` authentication and, after the
/// exact observed acceptance response, one typed `0x39` effective-data request.
/// There is no retry or reconnect path.
public struct V3DeveloperHandoverProbe: Sendable {
    public private(set) var state: V3ProbeState = .idle
    public private(set) var authenticationTransmissionCount = 0
    public private(set) var effectiveDataTransmissionCount = 0
    public private(set) var uniqueLiveReadingCount = 0

    private let material: V3ProbeMaterial
    private let requiredLiveReadingCount: Int
    private var observedLiveIndexes: Set<UInt16> = []

    public init(material: V3ProbeMaterial, requiredLiveReadingCount: Int = 5) {
        precondition(requiredLiveReadingCount > 0)
        self.material = material
        self.requiredLiveReadingCount = requiredLiveReadingCount
    }

    public mutating func start() throws -> [V3ProbeEffect] {
        guard state == .idle else { throw V3ProbeError.invalidTransition(from: state) }
        state = .subscribing
        return [.subscribeToNotifications]
    }

    public mutating func didSubscribe() throws -> [V3ProbeEffect] {
        guard state == .subscribing else {
            throw V3ProbeError.invalidTransition(from: state)
        }
        guard authenticationTransmissionCount == 0 else {
            throw V3ProbeError.invalidTransition(from: state)
        }
        let frame = try material.authenticationFrame()
        authenticationTransmissionCount = 1
        state = .awaitingAuthentication
        return [.transmit(.authentication(frame))]
    }

    public mutating func didReceive(_ frame: EncodedFrame) throws -> [V3ProbeEffect] {
        switch state {
        case .awaitingAuthentication:
            let response = try material.decodeControl(frame)
            switch response {
            case .authenticationAccepted:
                guard effectiveDataTransmissionCount == 0 else {
                    throw V3ProbeError.invalidTransition(from: state)
                }
                let request = try material.effectiveDataFrame()
                effectiveDataTransmissionCount = 1
                state = .awaitingEffectiveData
                return [.transmit(.effectiveData(request))]
            case .authenticationRejected(let code, let detail):
                state = .failed
                throw V3ProbeError.authenticationRejected(code: code, detail: detail)
            case .effectiveDataAcknowledgement:
                throw V3ProbeError.unexpectedNotification
            }

        case .awaitingEffectiveData:
            if let batch = try? material.decodeGlucose(frame),
               let record = batch.records.last {
                let reading = V3ProbeReading(
                    index: record.index,
                    glucoseTenthsMillimolesPerLiter: record.glucoseTenthsMillimolesPerLiter,
                    trendCode: record.trendCode,
                    source: batch.source
                )
                guard batch.source == .liveNotification else {
                    return [
                        .report(
                            reading,
                            liveReadingCount: uniqueLiveReadingCount,
                            requiredLiveReadingCount: requiredLiveReadingCount
                        )
                    ]
                }
                guard observedLiveIndexes.insert(record.index).inserted else { return [] }
                uniqueLiveReadingCount += 1
                let progress = V3ProbeEffect.report(
                    reading,
                    liveReadingCount: uniqueLiveReadingCount,
                    requiredLiveReadingCount: requiredLiveReadingCount
                )
                if uniqueLiveReadingCount >= requiredLiveReadingCount {
                    state = .completed
                    return [progress, .disconnect]
                }
                return [progress]
            }
            if let response = try? material.decodeControl(frame),
               case .effectiveDataAcknowledgement = response {
                return []
            }
            throw V3ProbeError.unexpectedNotification

        case .idle, .subscribing, .completed, .failed:
            throw V3ProbeError.invalidTransition(from: state)
        }
    }

    public mutating func timeOut() -> [V3ProbeEffect] {
        guard state != .completed, state != .failed else { return [] }
        state = .failed
        return [.disconnect]
    }

    public mutating func cancel() -> [V3ProbeEffect] {
        guard state != .completed, state != .failed else { return [] }
        state = .failed
        return [.disconnect]
    }
}
