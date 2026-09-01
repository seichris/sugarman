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
        #expect(ProductCopy.questionableSample.contains("questionable"))
        #expect(ProductCopy.questionableSample.contains("not a current"))
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

    @Test func workoutPlanCatalogStoresTwoDayReferenceBands() {
        let plans = WorkoutPlanCatalog.twoDay150KmRide
        #expect(plans.count == 2)
        #expect(plans[0].name == "150 km bike — Day 1")
        #expect(plans[1].name == "150 km bike — Day 2")
        #expect(plans.allSatisfy { $0.isValid })
        #expect(plans[0].phases.map(\.phase) == [.preWorkout, .duringWorkout, .postWorkout, .overnight])
        #expect(plans[1].phases.map(\.phase) == [.preWorkout, .duringWorkout, .postWorkout])

        let during = plans[0].phases[1]
        #expect(during.lowerMgdl == 90)
        #expect(during.upperMgdl == 150)
        #expect(during.floorMgdl == 80)
        #expect(during.lowerValue(in: .millimolesPerLiter) == 5.0)
        #expect(during.upperValue(in: .millimolesPerLiter) == 150.0 / 18.0)
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
                #expect(fixture.samples.allSatisfy { $0.quality == .ok })
            case .stale:
                #expect(fixture.lifecycle == .live)
            case .disconnected:
                #expect(fixture.connection == .disconnected)
            case .warmUp:
                #expect(fixture.lifecycle == .warmUp)
            case .sensorError:
                #expect(fixture.lifecycle == .error)
                #expect(fixture.samples.allSatisfy { $0.quality == .error })
            case .expired:
                #expect(fixture.lifecycle == .expired)
            case .questionableSample:
                #expect(fixture.connection == .subscribed)
                #expect(fixture.lifecycle == .live)
                #expect(fixture.samples.last?.quality == .questionable)
                #expect(fixture.samples.dropLast().allSatisfy { $0.quality == .ok })
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

    @Test func activeSessionPrefersDemoThenSelectionNotUUIDSort() {
        let earlyID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let lateID = UUID(uuidString: "ffffffff-ffff-ffff-ffff-ffffffffffff")!
        let early = SensorSession(
            id: earlyID,
            sensorID: UUID(),
            activatedAt: Date(timeIntervalSince1970: 100)
        )
        let late = SensorSession(
            id: lateID,
            sensorID: UUID(),
            activatedAt: Date(timeIntervalSince1970: 200)
        )
        let uuidFirst = [early, late].sorted { $0.id.uuidString < $1.id.uuidString }.first?.id
        #expect(uuidFirst == earlyID)

        #expect(
            ActiveSessionSelection.resolve(
                sessions: [early, late],
                demoSessionID: lateID,
                selectedSessionID: earlyID
            ) == lateID
        )
        #expect(
            ActiveSessionSelection.resolve(
                sessions: [early, late],
                demoSessionID: UUID(),
                selectedSessionID: lateID
            ) == lateID
        )
        #expect(
            ActiveSessionSelection.resolve(
                sessions: [early, late],
                demoSessionID: nil,
                selectedSessionID: nil
            ) == lateID
        )
        #expect(
            ActiveSessionSelection.resolve(
                sessions: [early],
                demoSessionID: nil,
                selectedSessionID: nil
            ) == earlyID
        )
        #expect(
            ActiveSessionSelection.resolve(
                sessions: [],
                demoSessionID: lateID,
                selectedSessionID: earlyID
            ) == nil
        )
        #expect(
            ActiveSessionSelection.selectionAfterInsert(
                insertedID: lateID,
                sessions: [late],
                currentSelection: nil
            ) == lateID
        )
        #expect(
            ActiveSessionSelection.selectionAfterInsert(
                insertedID: lateID,
                sessions: [early, late],
                currentSelection: earlyID
            ) == earlyID
        )
    }
}
