// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Sugarman contributors

import Foundation
import HealthKit

public enum AppleHealthAuthorizationState: String, Sendable, Equatable {
    case unavailable
    case notDetermined
    case denied
    case authorized
}

public enum AppleHealthWriterError: Error, Sendable, Equatable {
    case unavailable
    case bloodGlucoseTypeUnavailable
}

public protocol AppleHealthGlucoseWritingClient: Sendable {
    func authorizationState() async -> AppleHealthAuthorizationState
    func requestWriteAuthorization() async throws
    func earliestPermittedSampleDate() async throws -> Date
    func save(_ payloads: [AppleHealthGlucosePayload]) async throws
}

public actor SystemAppleHealthGlucoseWriter: AppleHealthGlucoseWritingClient {
    private let healthStore: HKHealthStore
    private let policy: AppleHealthValidationPolicy
    private let now: @Sendable () -> Date

    public init(
        healthStore: HKHealthStore = HKHealthStore(),
        policy: AppleHealthValidationPolicy = .closed,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.healthStore = healthStore
        self.policy = policy
        self.now = now
    }

    public func authorizationState() async -> AppleHealthAuthorizationState {
        guard HKHealthStore.isHealthDataAvailable() else { return .unavailable }
        guard let type = HKObjectType.quantityType(forIdentifier: .bloodGlucose) else {
            return .unavailable
        }
        switch healthStore.authorizationStatus(for: type) {
        case .notDetermined: return .notDetermined
        case .sharingDenied: return .denied
        case .sharingAuthorized: return .authorized
        @unknown default: return .unavailable
        }
    }

    public func requestWriteAuthorization() async throws {
        guard HKHealthStore.isHealthDataAvailable() else {
            throw AppleHealthWriterError.unavailable
        }
        guard let type = HKObjectType.quantityType(forIdentifier: .bloodGlucose) else {
            throw AppleHealthWriterError.bloodGlucoseTypeUnavailable
        }
        try await healthStore.requestAuthorization(toShare: [type], read: [])
    }

    public func earliestPermittedSampleDate() async throws -> Date {
        guard HKHealthStore.isHealthDataAvailable() else {
            throw AppleHealthWriterError.unavailable
        }
        return healthStore.earliestPermittedSampleDate()
    }

    public func save(_ payloads: [AppleHealthGlucosePayload]) async throws {
        guard !payloads.isEmpty else { return }
        guard let type = HKObjectType.quantityType(forIdentifier: .bloodGlucose) else {
            throw AppleHealthWriterError.bloodGlucoseTypeUnavailable
        }
        let earliestDate = healthStore.earliestPermittedSampleDate()
        let checkedPayloads = try payloads.map {
            try policy.payload(
                for: $0.sample,
                earliestPermittedDate: earliestDate,
                now: now()
            )
        }
        let unit = HKUnit(from: "mg/dL")
        let samples: [HKQuantitySample] = checkedPayloads.map { payload in
            HKQuantitySample(
                type: type,
                quantity: HKQuantity(
                    unit: unit,
                    doubleValue: Double(payload.milligramsPerDeciliter)
                ),
                start: payload.timestamp,
                end: payload.timestamp,
                metadata: [
                    HKMetadataKeySyncIdentifier: payload.syncIdentifier,
                    HKMetadataKeySyncVersion: AppleHealthGlucosePayload.syncVersion,
                ]
            )
        }
        try await healthStore.save(samples)
    }
}
