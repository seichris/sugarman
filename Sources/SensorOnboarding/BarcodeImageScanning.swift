// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Sugarman contributors

import Foundation

#if canImport(CoreGraphics)
import CoreGraphics
#endif
#if canImport(ImageIO)
import ImageIO
#endif

/// Scans a still image for barcode payload strings. Implementations must not
/// talk to a live GS3 sensor. Vision is stubbed behind this protocol so tests
/// can inject synthetic payloads without pixels.
public protocol BarcodeImageScanning: Sendable {
    func payloads(fromImageData data: Data) async throws -> [String]
}

/// Test double. Returns configured payloads and ignores image bytes.
public struct StubBarcodeImageScanner: BarcodeImageScanning, Sendable {
    public var payloadsToReturn: [String]
    public var error: OnboardingError?

    public init(payloadsToReturn: [String] = [], error: OnboardingError? = nil) {
        self.payloadsToReturn = payloadsToReturn
        self.error = error
    }

    public func payloads(fromImageData data: Data) async throws -> [String] {
        _ = data
        if let error {
            throw error
        }
        return payloadsToReturn
    }
}

#if canImport(Vision)
import Vision

/// Apple Vision Data Matrix / GS1 barcode scanner. Independent of Juggluco
/// PhotoScan. Takes `CGImage` or encoded image `Data` and returns payload
/// strings for the bounded package parser.
public struct VisionDataMatrixScanner: BarcodeImageScanning, Sendable {
    public init() {}

    public func payloads(fromImageData data: Data) async throws -> [String] {
        guard let image = makeCGImage(from: data) else {
            throw OnboardingError.invalidEncoding
        }
        return try await payloads(from: image)
    }

    public func payloads(from image: CGImage) async throws -> [String] {
        let request = VNDetectBarcodesRequest()
        request.symbologies = [.dataMatrix, .qr, .code128, .gs1DataBar, .gs1DataBarExpanded]
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        try handler.perform([request])
        let results = request.results ?? []
        return results.compactMap(\.payloadStringValue).filter { !$0.isEmpty }
    }

    private func makeCGImage(from data: Data) -> CGImage? {
        #if canImport(ImageIO)
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            return nil
        }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
        #else
        _ = data
        return nil
        #endif
    }
}
#endif
