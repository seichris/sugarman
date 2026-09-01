// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Sugarman contributors

import Foundation

/// P1 question: where can iOS legitimately obtain the six Bluetooth address
/// bytes Juggluco derives from the Android-visible MAC?
///
/// `advertisement` means those bytes appear in advertisement *payload* AD
/// structures (which CoreBluetooth can surface), not merely in the HCI peer
/// address field (Android-only).
public enum SixByteAddressSource: String, Sendable, Codable, Equatable, CaseIterable {
    case package
    case nfc
    case advertisement
    case deviceInformation
    case otherReadable
    case notFound
}

/// P2 stays unanswered until an owned capture is compared offline against the
/// pinned Juggluco codec. This analyzer never claims RC4 or AES.
public enum CipherHypothesis: String, Sendable, Codable, Equatable, CaseIterable {
    case unknownUntilCapture
}

/// Fail-closed: application payloads must not be treated as glucose.
public enum GlucoseDecodeRefusal: Error, Sendable, Equatable {
    case refusedUntilPhysicalParity
}
