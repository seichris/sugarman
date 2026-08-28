// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Sugarman contributors

import Foundation
import Testing
@testable import SugarmanDomain

struct SugarmanDomainTests {
    @Test func protocolVariantHasNoV3AES() {
        let names = ProtocolVariant.allCases.map(\.rawValue)
        #expect(names == ["unknown", "v120RC4"])
        #expect(!names.contains("v3AES"))
        #expect(ProtocolVariant.allCases.allSatisfy { $0.isImplemented == false })
    }

    @Test func glucoseSampleKeyIsSessionAndIndex() {
        let session = UUID()
        let sample = GlucoseSample(
            sessionID: session,
            sensorIndex: 7,
            sensorTimestamp: Date(timeIntervalSince1970: 1),
            receiptTimestamp: Date(timeIntervalSince1970: 2),
            milligramsPerDeciliter: 100,
            decoderRevision: "none"
        )
        #expect(sample.id == SampleKey(sessionID: session, sensorIndex: 7))
        #expect(sample.milligramsPerDeciliter == 100)
    }

    @Test func identityStoresRedactedSerialOnly() {
        let identity = SensorIdentity(redactedSerial: "A…Z/11")
        #expect(identity.redactedSerial == "A…Z/11")
        #expect(identity.protocolVariant == .unknown)
    }

    @Test func sessionNeverHoldsCredentials() {
        let session = SensorSession(sensorID: UUID(), ownerAccountReference: "owner-ref-1")
        #expect(session.ownerAccountReference == "owner-ref-1")
    }

    @Test func connectionEventOmitsGlucose() {
        let event = ConnectionEvent(
            timestamp: Date(),
            state: .disconnected,
            reason: .outOfRange,
            appLifecycle: .background
        )
        #expect(event.state == .disconnected)
    }

    @Test func noDosingCopyIsPresent() {
        #expect(ProductCopy.noDosing.contains("Never use these readings to dose insulin."))
        #expect(ProductCopy.noDosing.contains("does not diagnose"))
        #expect(ProductCopy.syntheticDemo.contains("not a real sensor"))
        #expect(ProductCopy.athleteInsightOnly.contains("does not recommend"))
    }

    @Test func workoutAndFuelingHaveNoPrescription() {
        let workout = WorkoutContext(start: Date(), activityType: "run")
        let fueling = FuelingEvent(timestamp: Date(), carbohydrateGrams: 30, label: "gel")
        let scoped = FuelingEvent(timestamp: Date(), label: "bar", sessionID: UUID())
        #expect(workout.activityType == "run")
        #expect(fueling.label == "gel")
        #expect(fueling.sessionID == nil)
        #expect(scoped.sessionID != nil)
    }

    @Test func syntheticDemoCatalogIsLabeledAndDrivesSafetyStates() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        for scenario in SyntheticDemoScenario.allCases {
            let fixture = SyntheticDemoCatalog.make(scenario, now: now)
            #expect(fixture.identity.productName == "Synthetic demo sensor")
            #expect(fixture.identity.redactedSerial == "…DEMO")
            #expect(fixture.identity.classificationEvidenceRevision == "synthetic-demo")
            #expect(fixture.identity.protocolVariant == .unknown)
            #expect(fixture.samples.allSatisfy { $0.decoderRevision == "synthetic-demo" })
            #expect(fixture.samples.allSatisfy { $0.source == .live || $0.source == .backfill })
            switch scenario {
            case .connectedNoData:
                #expect(fixture.samples.isEmpty)
                #expect(fixture.connection == .subscribed)
                #expect(fixture.lifecycle == .live)
            case .current:
                #expect(fixture.samples.count == 8)
                #expect(fixture.samples.filter { $0.source == .backfill }.count == 3)
                #expect(fixture.connection == .subscribed)
                #expect(fixture.lifecycle == .live)
            case .stale:
                #expect(fixture.lifecycle == .live)
            case .disconnected:
                #expect(fixture.connection == .disconnected)
            case .warmUp:
                #expect(fixture.lifecycle == .warmUp)
            case .sensorError:
                #expect(fixture.lifecycle == .error)
            case .expired:
                #expect(fixture.lifecycle == .expired)
            }
        }
    }

    @Test func millimolesUsesTenthsWhenPresentOtherwiseDividesBy18() {
        let session = UUID()
        let withTenths = GlucoseSample(
            sessionID: session,
            sensorIndex: 1,
            sensorTimestamp: Date(timeIntervalSince1970: 1),
            receiptTimestamp: Date(timeIntervalSince1970: 2),
            milligramsPerDeciliter: 108,
            originalTenthsMillimolesPerLiter: 61,
            decoderRevision: "none"
        )
        let withoutTenths = GlucoseSample(
            sessionID: session,
            sensorIndex: 2,
            sensorTimestamp: Date(timeIntervalSince1970: 1),
            receiptTimestamp: Date(timeIntervalSince1970: 2),
            milligramsPerDeciliter: 108,
            decoderRevision: "none"
        )
        #expect(withTenths.millimolesPerLiter() == Double(61) / 10.0)
        #expect(withoutTenths.millimolesPerLiter() == 108.0 / 18.0)
        #expect(withTenths.value(in: .milligramsPerDeciliter) == 108.0)
        #expect(withTenths.value(in: .millimolesPerLiter) == Double(61) / 10.0)
        #expect(GlucoseUnit.milligramsPerDeciliter.displaySymbol == "mg/dL")
        #expect(GlucoseUnit.millimolesPerLiter.displaySymbol == "mmol/L")
    }
}
