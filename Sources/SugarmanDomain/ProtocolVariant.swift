// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Sugarman contributors

/// Firmware/protocol classification. Physical gates P1 and P2 must pass
/// before any variant is treated as implemented.
///
/// `.v3AES` is intentionally absent until a primary evidence source map exists.
public enum ProtocolVariant: String, Sendable, Codable, CaseIterable, Equatable {
    case unknown
    /// Juggluco's documented V1.20/RC4 family. Unimplemented at M0.
    case v120RC4

    public var isImplemented: Bool { false }

    public var classificationEvidenceRevision: String {
        switch self {
        case .unknown:
            return "none"
        case .v120RC4:
            return "placeholder-unimplemented"
        }
    }
}
