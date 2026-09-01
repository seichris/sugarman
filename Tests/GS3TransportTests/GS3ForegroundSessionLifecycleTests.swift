// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Sugarman contributors

import Foundation
import GS3Session
import Testing
@testable import GS3Transport

private actor LifecycleController: GS3ForegroundSessionControlling {
    private var starts = 0
    private var stops = 0
    private var startContinuation: CheckedContinuation<Void, Never>?
    private let suspendsStart: Bool

    init(suspendsStart: Bool = false) {
        self.suspendsStart = suspendsStart
    }

    func start() async throws {
        starts += 1
        if suspendsStart {
            await withCheckedContinuation { continuation in
                startContinuation = continuation
            }
        }
    }

    func stop() {
        stops += 1
        startContinuation?.resume()
        startContinuation = nil
    }

    func foregroundEnded() {
        stop()
    }

    func currentPhase() -> GS3ForegroundPhase { .idle }

    func snapshot() -> (starts: Int, stops: Int, isStarting: Bool) {
        (starts, stops, startContinuation != nil)
    }
}

private final class LifecycleFactoryLog: @unchecked Sendable {
    private let lock = NSLock()
    private var creationCount = 0

    func recordCreation() {
        lock.withLock { creationCount += 1 }
    }

    var count: Int {
        lock.withLock { creationCount }
    }
}

struct GS3ForegroundSessionLifecycleTests {
    @MainActor
    @Test func noFactoryIsInertAndConfiguredEntryStartsOnlyOnce() async throws {
        let lifecycle = GS3ForegroundSessionLifecycle()
        try await lifecycle.enterForeground()
        #expect(!lifecycle.isConfigured)
        #expect(!lifecycle.isRunning)

        let controller = LifecycleController()
        lifecycle.install { controller }
        try await lifecycle.enterForeground()
        try await lifecycle.enterForeground()

        #expect(lifecycle.isConfigured)
        #expect(lifecycle.isRunning)
        #expect(await controller.snapshot().starts == 1)

        await lifecycle.leaveForeground()
        #expect(!lifecycle.isRunning)
        #expect(await controller.snapshot().stops == 1)
    }

    @MainActor
    @Test func leavingDuringStartStopsControllerAndCannotReactivateIt() async throws {
        let lifecycle = GS3ForegroundSessionLifecycle()
        let controller = LifecycleController(suspendsStart: true)
        lifecycle.install { controller }

        let startTask = Task { @MainActor in
            try await lifecycle.enterForeground()
        }
        for _ in 0..<200 where !(await controller.snapshot().isStarting) {
            await Task.yield()
        }
        #expect(await controller.snapshot().isStarting)

        await lifecycle.leaveForeground()
        try await startTask.value

        #expect(!lifecycle.isRunning)
        #expect(await controller.snapshot().starts == 1)
        #expect(await controller.snapshot().stops == 1)
    }

    @MainActor
    @Test func leavingDuringFactoryConstructionDisposesLateController() async throws {
        let lifecycle = GS3ForegroundSessionLifecycle()
        let controller = LifecycleController()
        let factoryStarted = AsyncStream.makeStream(of: Void.self)
        let factoryRelease = AsyncStream.makeStream(of: Void.self)
        lifecycle.install {
            factoryStarted.continuation.yield()
            for await _ in factoryRelease.stream { break }
            return controller
        }

        let startTask = Task { @MainActor in
            try await lifecycle.enterForeground()
        }
        for await _ in factoryStarted.stream { break }
        await lifecycle.leaveForeground()
        factoryRelease.continuation.yield()
        factoryRelease.continuation.finish()
        try await startTask.value

        #expect(!lifecycle.isRunning)
        #expect(await controller.snapshot().starts == 0)
        #expect(await controller.snapshot().stops == 1)
    }

    @MainActor
    @Test func reentryConstructsFreshControllerAndRemoveFactoryStopsIt() async throws {
        let lifecycle = GS3ForegroundSessionLifecycle()
        let log = LifecycleFactoryLog()
        lifecycle.install {
            log.recordCreation()
            return LifecycleController()
        }

        try await lifecycle.enterForeground()
        await lifecycle.leaveForeground()
        try await lifecycle.enterForeground()
        await lifecycle.removeFactory()

        #expect(log.count == 2)
        #expect(!lifecycle.isConfigured)
        #expect(!lifecycle.isRunning)
    }
}

struct GS3PersistentSessionLifecycleTests {
    @MainActor
    @Test func repeatedStartsKeepOneControllerUntilExplicitRemoval() async throws {
        let lifecycle = GS3PersistentSessionLifecycle()
        let controller = LifecycleController()
        let log = LifecycleFactoryLog()
        lifecycle.install {
            log.recordCreation()
            return controller
        }

        try await lifecycle.startIfNeeded()
        try await lifecycle.startIfNeeded()

        #expect(lifecycle.isConfigured)
        #expect(lifecycle.isRunning)
        #expect(log.count == 1)
        #expect(await controller.snapshot().starts == 1)

        await lifecycle.removeFactory()
        #expect(!lifecycle.isConfigured)
        #expect(!lifecycle.isRunning)
        #expect(await controller.snapshot().stops == 1)
    }

    @MainActor
    @Test func concurrentStartsCannotConstructTwoOwners() async throws {
        let lifecycle = GS3PersistentSessionLifecycle()
        let controller = LifecycleController()
        let factoryStarted = AsyncStream.makeStream(of: Void.self)
        let factoryRelease = AsyncStream.makeStream(of: Void.self)
        let log = LifecycleFactoryLog()
        lifecycle.install {
            log.recordCreation()
            factoryStarted.continuation.yield()
            for await _ in factoryRelease.stream { break }
            return controller
        }

        let first = Task { @MainActor in try await lifecycle.startIfNeeded() }
        for await _ in factoryStarted.stream { break }
        let second = Task { @MainActor in try await lifecycle.startIfNeeded() }
        await Task.yield()
        factoryRelease.continuation.yield()
        factoryRelease.continuation.finish()
        try await first.value
        try await second.value

        #expect(log.count == 1)
        #expect(await controller.snapshot().starts == 1)
        await lifecycle.removeFactory()
    }

    @MainActor
    @Test func removalDuringConstructionDisposesLateController() async throws {
        let lifecycle = GS3PersistentSessionLifecycle()
        let controller = LifecycleController()
        let factoryStarted = AsyncStream.makeStream(of: Void.self)
        let factoryRelease = AsyncStream.makeStream(of: Void.self)
        lifecycle.install {
            factoryStarted.continuation.yield()
            for await _ in factoryRelease.stream { break }
            return controller
        }

        let start = Task { @MainActor in try await lifecycle.startIfNeeded() }
        for await _ in factoryStarted.stream { break }
        await lifecycle.removeFactory()
        factoryRelease.continuation.yield()
        factoryRelease.continuation.finish()
        try await start.value

        #expect(!lifecycle.isConfigured)
        #expect(!lifecycle.isRunning)
        #expect(await controller.snapshot().starts == 0)
        #expect(await controller.snapshot().stops == 1)
    }
}
