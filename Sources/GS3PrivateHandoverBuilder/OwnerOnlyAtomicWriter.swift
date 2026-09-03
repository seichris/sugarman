// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Sugarman contributors

import Darwin
import Foundation

enum OwnerOnlyAtomicWriter {
    static func write(_ data: Data, to outputURL: URL) throws {
        guard outputURL.isFileURL else {
            throw GS3PrivateHandoverError.outputWriteFailed
        }
        let directory = outputURL.deletingLastPathComponent()
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(
            atPath: directory.path,
            isDirectory: &isDirectory
        ), isDirectory.boolValue else {
            throw GS3PrivateHandoverError.outputWriteFailed
        }

        let temporaryURL = directory.appendingPathComponent(
            ".gs3-private-handover-\(UUID().uuidString).tmp",
            isDirectory: false
        )
        let descriptor = Darwin.open(
            temporaryURL.path,
            O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW,
            mode_t(S_IRUSR | S_IWUSR)
        )
        guard descriptor >= 0 else {
            throw GS3PrivateHandoverError.outputWriteFailed
        }
        var renamed = false
        defer {
            _ = Darwin.close(descriptor)
            if !renamed {
                _ = Darwin.unlink(temporaryURL.path)
            }
        }

        let wroteAll = data.withUnsafeBytes { rawBuffer -> Bool in
            guard let base = rawBuffer.baseAddress else { return data.isEmpty }
            var offset = 0
            while offset < rawBuffer.count {
                let written = Darwin.write(
                    descriptor,
                    base.advanced(by: offset),
                    rawBuffer.count - offset
                )
                if written <= 0 { return false }
                offset += written
            }
            return true
        }
        guard wroteAll,
              Darwin.fchmod(descriptor, mode_t(S_IRUSR | S_IWUSR)) == 0,
              Darwin.fsync(descriptor) == 0,
              Darwin.renamex_np(
                  temporaryURL.path,
                  outputURL.path,
                  UInt32(RENAME_EXCL)
              ) == 0 else {
            throw GS3PrivateHandoverError.outputWriteFailed
        }
        renamed = true

        let directoryDescriptor = Darwin.open(directory.path, O_RDONLY)
        if directoryDescriptor >= 0 {
            _ = Darwin.fsync(directoryDescriptor)
            _ = Darwin.close(directoryDescriptor)
        }
    }
}
