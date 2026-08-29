// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Sugarman contributors

import Foundation

/// Live AVCapture + Vision Data Matrix (QR fallback) exists only when compiled
/// for iOS with AVFoundation and Vision. Simulator UI still uses PhotosPicker
/// / file import. Parsing always goes through `BoundedPackageParser` and
/// still requires confirmation before storing identity.
public enum LiveBarcodeCaptureAvailability: Sendable {
    public static var liveCaptureCompiled: Bool {
        #if os(iOS) && canImport(AVFoundation) && canImport(Vision)
        true
        #else
        false
        #endif
    }
}

#if canImport(Vision)
import Vision

/// Shared symbology policy for still-image and live capture. Data Matrix is
/// preferred; QR is a fallback. No sensor activation.
public enum BarcodeSymbologyPolicy: Sendable {
    public static var liveCapture: [VNBarcodeSymbology] {
        [.dataMatrix, .qr]
    }

    public static func preferredPayload(from observations: [VNBarcodeObservation]) -> String? {
        let dataMatrix = observations
            .filter { $0.symbology == .dataMatrix }
            .compactMap(\.payloadStringValue)
            .first { !$0.isEmpty }
        if let dataMatrix {
            return dataMatrix
        }
        return observations
            .filter { $0.symbology == .qr }
            .compactMap(\.payloadStringValue)
            .first { !$0.isEmpty }
    }
}
#endif
