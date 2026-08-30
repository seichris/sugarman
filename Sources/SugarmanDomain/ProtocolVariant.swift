// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Sugarman contributors

/// Firmware/protocol classification. A variant is treated as live-capable only
/// after offline parity and the applicable physical gate pass.
public enum ProtocolVariant: String, Sendable, Codable, CaseIterable, Equatable {
    case unknown
    /// Juggluco's documented V1.20/RC4 family. Unimplemented at M0.
    case v120RC4
    /// Owned Mainland GS3 38-byte AES-OFB family. Offline auth builder only.
    case v3AES

    public var isImplemented: Bool { false }

    public var classificationEvidenceRevision: String {
        switch self {
        case .unknown:
            return "none"
        case .v120RC4:
            return "placeholder-unimplemented"
        case .v3AES:
            return "owned-mainland-gs3-v3-source-map-2026-08-30-offline-only"
        }
    }
}
