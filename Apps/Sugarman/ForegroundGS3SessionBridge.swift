// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Sugarman contributors

import GS3Transport

/// App lifecycle bridge for the typed foreground coordinator.
///
/// No factory is installed by the release bootstrap, so the normal app remains
/// unable to construct live material or contact a sensor. A separately
/// reviewed device-only provisioning boundary may install a typed factory for
/// an exact physical-test artifact without adding raw commands here.
@MainActor
final class ForegroundGS3SessionBridge {
    typealias Factory = @Sendable () async throws -> any GS3ForegroundSessionControlling
    private typealias ControllerSlot = (
        generation: UInt64,
        controller: any GS3ForegroundSessionControlling
    )

    private var factory: Factory?
    private var activeController: ControllerSlot?
    private var startingController: ControllerSlot?
    private var lifecycleGeneration: UInt64 = 0

    var isConfigured: Bool { factory != nil }
    var isRunning: Bool { activeController != nil }

    func install(factory: @escaping Factory) {
        precondition(activeController == nil && startingController == nil)
        self.factory = factory
    }

    func removeFactory() async {
        factory = nil
        await leaveForeground()
    }

    func enterForeground() async throws {
        guard activeController == nil,
              startingController == nil,
              let factory else { return }
        lifecycleGeneration &+= 1
        let generation = lifecycleGeneration
        let controller: any GS3ForegroundSessionControlling
        do {
            controller = try await factory()
        } catch {
            guard generation == lifecycleGeneration else { return }
            throw error
        }
        guard generation == lifecycleGeneration else { return }

        startingController = (generation, controller)
        do {
            try await controller.start()
        } catch {
            if startingController?.generation == generation {
                startingController = nil
            }
            guard generation == lifecycleGeneration else { return }
            throw error
        }
        if startingController?.generation == generation {
            startingController = nil
        }
        guard generation == lifecycleGeneration else { return }
        activeController = (generation, controller)
    }

    func leaveForeground() async {
        lifecycleGeneration &+= 1
        let starting = startingController
        let active = activeController
        startingController = nil
        activeController = nil
        if let starting {
            await starting.controller.foregroundEnded()
        }
        if let active {
            await active.controller.foregroundEnded()
        }
    }
}
