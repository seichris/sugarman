// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Sugarman contributors

import Foundation
import GS3Protocol

public enum V3ProbeState: Sendable, Equatable {
    case idle
    case subscribing
    case awaitingAuthentication
    case awaitingEffectiveData
    case completed
    case failed
}

extension V3ProbeState: CustomStringConvertible {
    public var description: String {
        switch self {
        case .idle: "idle"
        case .subscribing: "subscribing"
        case .awaitingAuthentication: "awaiting authentication"
        case .awaitingEffectiveData: "awaiting effective data"
        case .completed: "completed"
        case .failed: "failed"
        }
    }
}

/// Payload-free classification of an FF31 notification.
///
/// This deliberately omits ciphertext, plaintext, identifiers, status-detail
/// bytes, glucose values, record indexes, and cryptographic material.
public enum V3ProbeInboundClassification: Sendable, Equatable {
    case authenticationAccepted
    case authenticationRejected
    case effectiveDataAcknowledgement
    case effectiveDataBatch
    case liveNotificationBatch
    case malformedOrUnsupported
}

extension V3ProbeInboundClassification: CustomStringConvertible {
    public var description: String {
        switch self {
        case .authenticationAccepted: "authentication acceptance"
        case .authenticationRejected: "authentication rejection"
        case .effectiveDataAcknowledgement: "effective-data acknowledgement"
        case .effectiveDataBatch: "effective-data batch"
        case .liveNotificationBatch: "live-notification batch"
        case .malformedOrUnsupported: "malformed or unsupported notification"
        }
    }
}

/// Redacted state/packet evidence retained only by the developer probe UI.
public struct V3ProbePacketDiagnostic:
    Sendable, Equatable, CustomStringConvertible, CustomDebugStringConvertible,
    CustomReflectable
{
    public let stateBefore: V3ProbeState
    public let stateAfter: V3ProbeState
    public let classification: V3ProbeInboundClassification
    public let byteCount: Int
    public let authenticationTransmissionCount: Int
    public let effectiveDataTransmissionCount: Int
    public let uniqueLiveReadingCount: Int

    public var description: String {
        "RX FF31: \(classification), \(byteCount) bytes; "
            + "\(stateBefore) -> \(stateAfter); "
            + "authorized E2=\(authenticationTransmissionCount), "
            + "authorized 0x39=\(effectiveDataTransmissionCount), "
            + "unique live=\(uniqueLiveReadingCount)"
    }

    public var debugDescription: String { description }

    public var customMirror: Mirror {
        Mirror(
            self,
            children: [
                "stateBefore": stateBefore,
                "stateAfter": stateAfter,
                "classification": classification,
                "byteCount": byteCount,
                "authenticationTransmissionCount": authenticationTransmissionCount,
                "effectiveDataTransmissionCount": effectiveDataTransmissionCount,
                "uniqueLiveReadingCount": uniqueLiveReadingCount,
            ],
            displayStyle: .struct
        )
    }
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
    case unexpectedNotification(V3ProbePacketDiagnostic)
}

extension V3ProbeError: LocalizedError, CustomStringConvertible {
    public var errorDescription: String? { description }

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
        case .unexpectedNotification(let diagnostic):
            return "Unexpected \(diagnostic.classification) while "
                + "\(diagnostic.stateBefore) (\(diagnostic.byteCount) bytes; "
                + "authorized E2=\(diagnostic.authenticationTransmissionCount), "
                + "authorized 0x39=\(diagnostic.effectiveDataTransmissionCount)). "
                + "Disconnected; do not retry this artifact."
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
    public private(set) var lastPacketDiagnostic: V3ProbePacketDiagnostic?

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
        let stateBefore = state
        let decoded = decode(frame)

        switch state {
        case .awaitingAuthentication:
            switch decoded.controlResponse {
            case .authenticationAccepted:
                guard effectiveDataTransmissionCount == 0 else {
                    throw V3ProbeError.invalidTransition(from: state)
                }
                let request = try material.effectiveDataFrame()
                effectiveDataTransmissionCount = 1
                state = .awaitingEffectiveData
                recordDiagnostic(
                    stateBefore: stateBefore,
                    classification: decoded.classification,
                    byteCount: frame.byteCount
                )
                return [.transmit(.effectiveData(request))]
            case .authenticationRejected(let code, let detail):
                state = .failed
                recordDiagnostic(
                    stateBefore: stateBefore,
                    classification: decoded.classification,
                    byteCount: frame.byteCount
                )
                throw V3ProbeError.authenticationRejected(code: code, detail: detail)
            case .effectiveDataAcknowledgement, .none:
                throw unexpectedNotification(
                    stateBefore: stateBefore,
                    classification: decoded.classification,
                    byteCount: frame.byteCount
                )
            }

        case .awaitingEffectiveData:
            if let batch = decoded.glucoseBatch,
               let record = batch.records.last {
                let reading = V3ProbeReading(
                    index: record.index,
                    glucoseTenthsMillimolesPerLiter: record.glucoseTenthsMillimolesPerLiter,
                    trendCode: record.trendCode,
                    source: batch.source
                )
                guard batch.source == .liveNotification else {
                    recordDiagnostic(
                        stateBefore: stateBefore,
                        classification: decoded.classification,
                        byteCount: frame.byteCount
                    )
                    return [
                        .report(
                            reading,
                            liveReadingCount: uniqueLiveReadingCount,
                            requiredLiveReadingCount: requiredLiveReadingCount
                        )
                    ]
                }
                guard observedLiveIndexes.insert(record.index).inserted else {
                    recordDiagnostic(
                        stateBefore: stateBefore,
                        classification: decoded.classification,
                        byteCount: frame.byteCount
                    )
                    return []
                }
                uniqueLiveReadingCount += 1
                let progress = V3ProbeEffect.report(
                    reading,
                    liveReadingCount: uniqueLiveReadingCount,
                    requiredLiveReadingCount: requiredLiveReadingCount
                )
                if uniqueLiveReadingCount >= requiredLiveReadingCount {
                    state = .completed
                    recordDiagnostic(
                        stateBefore: stateBefore,
                        classification: decoded.classification,
                        byteCount: frame.byteCount
                    )
                    return [progress, .disconnect]
                }
                recordDiagnostic(
                    stateBefore: stateBefore,
                    classification: decoded.classification,
                    byteCount: frame.byteCount
                )
                return [progress]
            }
            if case .effectiveDataAcknowledgement = decoded.controlResponse {
                recordDiagnostic(
                    stateBefore: stateBefore,
                    classification: decoded.classification,
                    byteCount: frame.byteCount
                )
                return []
            }
            throw unexpectedNotification(
                stateBefore: stateBefore,
                classification: decoded.classification,
                byteCount: frame.byteCount
            )

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

    private func decode(
        _ frame: EncodedFrame
    ) -> (
        classification: V3ProbeInboundClassification,
        controlResponse: V3ControlResponse?,
        glucoseBatch: V3GlucoseBatch?
    ) {
        if let response = try? material.decodeControl(frame) {
            let classification: V3ProbeInboundClassification
            switch response {
            case .authenticationAccepted:
                classification = .authenticationAccepted
            case .authenticationRejected:
                classification = .authenticationRejected
            case .effectiveDataAcknowledgement:
                classification = .effectiveDataAcknowledgement
            }
            return (classification, response, nil)
        }
        if let batch = try? material.decodeGlucose(frame) {
            let classification: V3ProbeInboundClassification = switch batch.source {
            case .effectiveData: .effectiveDataBatch
            case .liveNotification: .liveNotificationBatch
            }
            return (classification, nil, batch)
        }
        return (.malformedOrUnsupported, nil, nil)
    }

    private mutating func recordDiagnostic(
        stateBefore: V3ProbeState,
        classification: V3ProbeInboundClassification,
        byteCount: Int
    ) {
        lastPacketDiagnostic = V3ProbePacketDiagnostic(
            stateBefore: stateBefore,
            stateAfter: state,
            classification: classification,
            byteCount: byteCount,
            authenticationTransmissionCount: authenticationTransmissionCount,
            effectiveDataTransmissionCount: effectiveDataTransmissionCount,
            uniqueLiveReadingCount: uniqueLiveReadingCount
        )
    }

    private mutating func unexpectedNotification(
        stateBefore: V3ProbeState,
        classification: V3ProbeInboundClassification,
        byteCount: Int
    ) -> V3ProbeError {
        state = .failed
        let diagnostic = V3ProbePacketDiagnostic(
            stateBefore: stateBefore,
            stateAfter: state,
            classification: classification,
            byteCount: byteCount,
            authenticationTransmissionCount: authenticationTransmissionCount,
            effectiveDataTransmissionCount: effectiveDataTransmissionCount,
            uniqueLiveReadingCount: uniqueLiveReadingCount
        )
        lastPacketDiagnostic = diagnostic
        return .unexpectedNotification(diagnostic)
    }
}
