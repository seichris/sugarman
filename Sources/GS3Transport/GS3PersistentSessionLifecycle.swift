// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Sugarman contributors

import Foundation

/// Main-actor owner for one production session whose lifetime follows durable
/// user intent rather than the foreground scene. Background transitions are
/// intentionally inert; explicit removal is the sole stop boundary.
@MainActor
public final class GS3PersistentSessionLifecycle {
    public typealias Factory =
        @Sendable () async throws -> any GS3ForegroundSessionControlling

    private typealias ControllerSlot = (
        generation: UInt64,
        controller: any GS3ForegroundSessionControlling
    )

    private var factory: Factory?
    private var activeController: ControllerSlot?
    private var startingController: ControllerSlot?
    private var constructingGeneration: UInt64?
    private var lifecycleGeneration: UInt64 = 0

    public init() {}

    public var isConfigured: Bool { factory != nil }
    public var isRunning: Bool { activeController != nil }

    public func install(factory: @escaping Factory) {
        precondition(activeController == nil && startingController == nil)
        self.factory = factory
    }

    public func startIfNeeded() async throws {
        guard activeController == nil,
              startingController == nil,
              constructingGeneration == nil,
              let factory else { return }
        lifecycleGeneration &+= 1
        let generation = lifecycleGeneration
        constructingGeneration = generation
        let controller: any GS3ForegroundSessionControlling
        do {
            controller = try await factory()
        } catch {
            if constructingGeneration == generation {
                constructingGeneration = nil
            }
            guard generation == lifecycleGeneration else { return }
            throw error
        }
        if constructingGeneration == generation {
            constructingGeneration = nil
        }
        guard generation == lifecycleGeneration else {
            await controller.stop()
            return
        }

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

    public func removeFactory() async {
        factory = nil
        lifecycleGeneration &+= 1
        constructingGeneration = nil
        let starting = startingController
        let active = activeController
        startingController = nil
        activeController = nil
        if let starting {
            await starting.controller.stop()
        }
        if let active {
            await active.controller.stop()
        }
    }
}
