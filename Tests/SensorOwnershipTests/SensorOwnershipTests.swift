// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Sugarman contributors

import Foundation
import Testing
@testable import SensorOwnership

struct SensorOwnershipTests {
    @Test func exclusiveLeaseBlocksASecondOwnerAndReleasesDeterministically() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "sugarman-owner-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let lockURL = directory.appendingPathComponent("sensor-owner.lock")

        let first = try SensorOwnerLease.acquire(lockFileURL: lockURL)
        #expect(first.isActive)
        let attributes = try FileManager.default.attributesOfItem(atPath: lockURL.path)
        #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
        #expect(throws: SensorOwnershipError.alreadyOwnedByAnotherProcess) {
            try SensorOwnerLease.acquire(lockFileURL: lockURL)
        }

        first.release()
        #expect(!first.isActive)
        let replacement = try SensorOwnerLease.acquire(lockFileURL: lockURL)
        #expect(replacement.isActive)
        replacement.release()
    }

    @Test func processExitSemanticsAreMirroredByDeinit() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "sugarman-owner-deinit-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let lockURL = directory.appendingPathComponent("sensor-owner.lock")

        var lease: SensorOwnerLease? = try SensorOwnerLease.acquire(lockFileURL: lockURL)
        #expect(lease?.isActive == true)
        lease = nil
        let replacement = try SensorOwnerLease.acquire(lockFileURL: lockURL)
        #expect(replacement.isActive)
        replacement.release()
    }

    @Test func independentProcessOwnerBlocksTheSwiftLeaseUntilRelease() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "sugarman-owner-process-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let lockURL = directory.appendingPathComponent("sensor-owner.lock")

        let childInput = Pipe()
        let childOutput = Pipe()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [
            "python3",
            "-c",
            """
            import fcntl, sys
            with open(sys.argv[1], "a+b", buffering=0) as lock_file:
                fcntl.flock(lock_file.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
                sys.stdout.write("ready\\n")
                sys.stdout.flush()
                sys.stdin.buffer.read(1)
            """,
            lockURL.path,
        ]
        process.standardInput = childInput
        process.standardOutput = childOutput
        process.standardError = Pipe()
        try process.run()
        defer {
            if process.isRunning {
                try? childInput.fileHandleForWriting.write(contentsOf: Data([1]))
                childInput.fileHandleForWriting.closeFile()
                process.waitUntilExit()
            }
        }

        let readyData = try #require(
            try childOutput.fileHandleForReading.read(upToCount: 6)
        )
        #expect(String(decoding: readyData, as: UTF8.self) == "ready\n")
        #expect(throws: SensorOwnershipError.alreadyOwnedByAnotherProcess) {
            try SensorOwnerLease.acquire(lockFileURL: lockURL)
        }

        try childInput.fileHandleForWriting.write(contentsOf: Data([1]))
        childInput.fileHandleForWriting.closeFile()
        process.waitUntilExit()
        #expect(process.terminationStatus == 0)

        let replacement = try SensorOwnerLease.acquire(lockFileURL: lockURL)
        #expect(replacement.isActive)
        replacement.release()
    }

    @Test func ownershipDiagnosticsOmitTheSharedPathAndKernelHandle() throws {
        let secretPathComponent = "private-sensor-identifier-\(UUID().uuidString)"
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            secretPathComponent,
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let lease = try SensorOwnerLease.acquire(
            lockFileURL: directory.appendingPathComponent("sensor-owner.lock")
        )
        defer { lease.release() }

        var dumped = ""
        dump(lease, to: &dumped)
        #expect(!lease.description.contains(secretPathComponent))
        #expect(!String(reflecting: lease).contains(secretPathComponent))
        #expect(!dumped.contains(secretPathComponent))
        #expect(lease.description == "SensorOwnerLease(active: true)")
    }
}
