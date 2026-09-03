// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Sugarman contributors

import Foundation

public enum GS3PrivateHandoverError: Error, Sendable, Equatable {
    case invalidArguments
    case inputUnreadable
    case invalidCapture
    case unsupportedCapture
    case invalidUserID
    case invalidPrivateProfile
    case unsupportedPrivateProfile
    case missingCandidateSession
    case ambiguousCandidateSessions
    case missingAdvertisedName
    case ambiguousAdvertisedName
    case missingDeviceInformationAddress
    case ambiguousDeviceInformationAddress
    case missingAuthenticationWrite
    case conflictingAuthenticationWrites
    case authenticationReplayFailed
    case missingHistoryRequest
    case ambiguousHistoryRequests
    case missingFollowingDataBatch
    case invalidFollowingDataBatch
    case historyPairMismatch
    case outputWriteFailed
}
extension GS3PrivateHandoverError: LocalizedError, CustomStringConvertible {
    public var errorDescription: String? { description }

    public var description: String {
        switch self {
        case .invalidArguments:
            "The command arguments are invalid."
        case .inputUnreadable:
            "A required private input could not be read."
        case .invalidCapture:
            "The Bluetooth HCI capture is malformed or truncated."
        case .unsupportedCapture:
            "The Bluetooth HCI capture format is unsupported."
        case .invalidUserID:
            "The owner-visible numeric user ID is invalid."
        case .invalidPrivateProfile:
            "The private profile is malformed."
        case .unsupportedPrivateProfile:
            "The private profile is not pinned to the supported evidence revision."
        case .missingCandidateSession:
            "No complete capture-backed GS3 session was found."
        case .ambiguousCandidateSessions:
            "More than one complete capture-backed GS3 session was found."
        case .missingAdvertisedName:
            "The selected session has no exact complete advertised name."
        case .ambiguousAdvertisedName:
            "The selected session has conflicting complete advertised names."
        case .missingDeviceInformationAddress:
            "The selected session has no verified six-byte Device Information address."
        case .ambiguousDeviceInformationAddress:
            "The selected session has more than one replay-valid address order."
        case .missingAuthenticationWrite:
            "The selected session has no captured official authentication write."
        case .conflictingAuthenticationWrites:
            "The selected session has conflicting authentication writes."
        case .authenticationReplayFailed:
            "The selected authentication write failed exact decrypt and re-encode parity."
        case .missingHistoryRequest:
            "The selected session has no capture-backed history request."
        case .ambiguousHistoryRequests:
            "The selected session has conflicting capture-backed history requests."
        case .missingFollowingDataBatch:
            "The selected history request has no following data batch."
        case .invalidFollowingDataBatch:
            "The first following data batch failed closed validation."
        case .historyPairMismatch:
            "The captured history request and following data batch do not start together."
        case .outputWriteFailed:
            "The private handover document could not be written securely."
        }
    }
}
