// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Sugarman contributors

import Darwin
import Foundation

// Darwin also imports a `flock` structure, which shadows the C function in
// Swift. Bind the public libc symbol explicitly and keep it private here.
@_silgen_name("flock")
private func sugarmanFlock(_ descriptor: Int32, _ operation: Int32) -> Int32

/// Fail-closed errors for the process-wide sensor ownership gate.
///
/// Error descriptions deliberately omit the lock-file path, process ID, file
/// descriptor, sensor identity, and application identity.
public enum SensorOwnershipError: Error, Sendable, Equatable {
    case sharedContainerUnavailable
    case invalidLockFileURL
    case alreadyOwnedByAnotherProcess
    case openFailed(code: Int32)
    case permissionFailed(code: Int32)
    case lockFailed(code: Int32)
}

extension SensorOwnershipError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .sharedContainerUnavailable:
            "Shared sensor ownership is unavailable. Sensor access remains disabled."
        case .invalidLockFileURL:
            "The shared sensor ownership location is invalid. Sensor access remains disabled."
        case .alreadyOwnedByAnotherProcess:
            "Another Sugarman process currently owns local sensor access."
        case .openFailed(let code):
            "Shared sensor ownership could not be opened (system code \(code))."
        case .permissionFailed(let code):
            "Shared sensor ownership could not be secured (system code \(code))."
        case .lockFailed(let code):
            "Shared sensor ownership could not be acquired (system code \(code))."
        }
    }
}

/// An advisory exclusive lock held by one cooperating local process.
///
/// Both the normal app and the developer probe use the same App Group file.
/// The file contains no bytes; the open descriptor and kernel lock are the
/// ownership record. The lock is automatically released on process exit.
public final class SensorOwnerLease:
    @unchecked Sendable, CustomStringConvertible, CustomDebugStringConvertible,
    CustomReflectable
{
    private let stateLock = NSLock()
    private var descriptor: Int32?

    private init(descriptor: Int32) {
        self.descriptor = descriptor
    }

    deinit {
        release()
    }

    public static func acquire(lockFileURL: URL) throws -> SensorOwnerLease {
        guard lockFileURL.isFileURL else {
            throw SensorOwnershipError.invalidLockFileURL
        }

        let descriptor = lockFileURL.withUnsafeFileSystemRepresentation { path -> Int32 in
            guard let path else { return -1 }
            return Darwin.open(
                path,
                O_RDWR | O_CREAT | O_CLOEXEC | O_NOFOLLOW,
                S_IRUSR | S_IWUSR
            )
        }
        guard descriptor >= 0 else {
            throw SensorOwnershipError.openFailed(code: errno)
        }

        guard Darwin.fchmod(descriptor, S_IRUSR | S_IWUSR) == 0 else {
            let code = errno
            Darwin.close(descriptor)
            throw SensorOwnershipError.permissionFailed(code: code)
        }

        guard sugarmanFlock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
            let code = errno
            Darwin.close(descriptor)
            if code == EWOULDBLOCK || code == EAGAIN {
                throw SensorOwnershipError.alreadyOwnedByAnotherProcess
            }
            throw SensorOwnershipError.lockFailed(code: code)
        }

        // The lock file is intentionally empty and owner-readable only.
        return SensorOwnerLease(descriptor: descriptor)
    }

    public var isActive: Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return descriptor != nil
    }

    public func release() {
        stateLock.lock()
        guard let descriptor else {
            stateLock.unlock()
            return
        }
        _ = sugarmanFlock(descriptor, LOCK_UN)
        Darwin.close(descriptor)
        self.descriptor = nil
        stateLock.unlock()
    }

    public var description: String {
        "SensorOwnerLease(active: \(isActive))"
    }

    public var debugDescription: String { description }

    public var customMirror: Mirror {
        Mirror(self, children: ["active": isActive], displayStyle: .class)
    }
}

/// Shared location used by both iOS application targets.
public enum SharedSensorOwnerLease: Sendable {
    public static let applicationGroupIdentifier = "group.app.sugarman.sensor-owner"
    public static let lockFileName = "sensor-owner.lock"

    public static func acquire(fileManager: FileManager = .default) throws -> SensorOwnerLease {
        guard let container = fileManager.containerURL(
            forSecurityApplicationGroupIdentifier: applicationGroupIdentifier
        ) else {
            throw SensorOwnershipError.sharedContainerUnavailable
        }
        return try SensorOwnerLease.acquire(
            lockFileURL: container.appendingPathComponent(lockFileName, isDirectory: false)
        )
    }
}
