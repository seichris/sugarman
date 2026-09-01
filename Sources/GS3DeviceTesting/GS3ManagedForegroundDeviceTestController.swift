// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Sugarman contributors

import GS3DeviceProvisioning
import GS3Session
import GS3Transport
import SugarmanStore

/// Device-Test-only wrapper around the production foreground controller.
///
/// Its sole additional capability is a bounded cancellation of an already-live
/// link so the real reconnect path can be exercised. It exposes no packet,
/// characteristic, peripheral, command, identity, or private-material value.
public actor GS3ManagedForegroundDeviceTestController:
    GS3ForegroundSessionControlling
{
    private let controller: any GS3ForegroundDeviceTestControlling

    package init(controller: any GS3ForegroundDeviceTestControlling) {
        self.controller = controller
    }

    public func start() async throws {
        try await controller.start()
    }

    public func stop() async {
        await controller.stop()
    }

    public func foregroundEnded() async {
        await controller.foregroundEnded()
    }

    public func currentPhase() async -> GS3ForegroundPhase {
        await controller.currentPhase()
    }

    /// Returns `true` only when one live CoreBluetooth cancellation was
    /// accepted. Calls outside `.live` are inert and send no sensor command.
    public func injectLinkLoss() async -> Bool {
        await controller.injectLinkLossForDeviceTesting()
    }
}

extension DeviceOnlyGS3Provisioning {
    public func makeManagedForegroundDeviceTestController(
        store: any SugarmanStoring,
        callbacks: GS3ForegroundSessionCallbacks = GS3ForegroundSessionCallbacks()
    ) async throws -> GS3ManagedForegroundDeviceTestController {
        GS3ManagedForegroundDeviceTestController(
            controller: try await makeDeviceTestController(
                store: store,
                callbacks: callbacks
            )
        )
    }
}
