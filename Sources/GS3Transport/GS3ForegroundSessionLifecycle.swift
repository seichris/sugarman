// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Sugarman contributors

import Foundation

/// Main-actor lifecycle boundary between an application scene and one typed
/// foreground GS3 controller.
///
/// Installing a factory is inert. Entering the foreground constructs and
/// starts at most one controller, while leaving the foreground invalidates any
/// in-progress start and stops both starting and active controllers. The
/// generation check prevents a delayed start from becoming active after a
/// scene has ended.
@MainActor
public final class GS3ForegroundSessionLifecycle {
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

    public func removeFactory() async {
        factory = nil
        await leaveForeground()
    }

    public func enterForeground() async throws {
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
            await controller.foregroundEnded()
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

    public func leaveForeground() async {
        lifecycleGeneration &+= 1
        constructingGeneration = nil
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
