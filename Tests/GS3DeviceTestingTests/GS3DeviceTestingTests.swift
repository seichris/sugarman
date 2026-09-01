// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Sugarman contributors

import Testing
@testable import GS3DeviceTesting

struct GS3DeviceTestingTests {
    @Test func externalOwnershipConfirmationIsProcessLocalAndRevocable() throws {
        let gate = GS3DeviceTestExternalOwnershipGate()

        #expect(!gate.isConfirmed)
        #expect(throws: GS3DeviceTestExternalOwnershipError.confirmationRequired) {
            try gate.requireConfirmation()
        }

        gate.confirmExclusiveAccess()
        #expect(gate.isConfirmed)
        try gate.requireConfirmation()

        gate.revoke()
        #expect(!gate.isConfirmed)
        #expect(throws: GS3DeviceTestExternalOwnershipError.confirmationRequired) {
            try gate.requireConfirmation()
        }
    }

    @Test func separateGateNeverInheritsAnotherProcessesConfirmation() {
        let firstProcess = GS3DeviceTestExternalOwnershipGate()
        firstProcess.confirmExclusiveAccess()

        let nextProcess = GS3DeviceTestExternalOwnershipGate()
        #expect(firstProcess.isConfirmed)
        #expect(!nextProcess.isConfirmed)
    }
}
