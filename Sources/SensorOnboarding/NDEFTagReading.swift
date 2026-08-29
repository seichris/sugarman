// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Sugarman contributors

import Foundation
#if canImport(CoreNFC)
import CoreNFC
#endif

/// Whether this build compiled a Core NFC NDEF reader. Simulator and macOS
/// stay `false`. The type exists on every platform so tests can assert the
/// `#if canImport(CoreNFC)` split.
public enum NDEFTagReadingAvailability: Sendable {
    public static var coreNFCCompiled: Bool {
        #if canImport(CoreNFC)
        true
        #else
        false
        #endif
    }

    public static var readingAvailable: Bool {
        #if canImport(CoreNFC)
        NFCNDEFReaderSession.readingAvailable
        #else
        false
        #endif
    }
}

/// Reads NDEF text/URI records from an owned tag. Implementations must not
/// send NFC tag commands, write NDEF, or activate a sensor.
public protocol NDEFTagReading: Sendable {
    func readTextRecords() async throws -> [String]
}

#if canImport(CoreNFC)
import CoreNFC

/// Extracts UTF-8 text from NDEF messages without logging unique identifiers.
public enum NDEFTextRecordExtractor: Sendable {
    public static func textPayloads(from messages: [NFCNDEFMessage]) -> [String] {
        var texts: [String] = []
        for message in messages {
            for record in message.records {
                if let payload = record.wellKnownTypeTextPayload(), !payload.0.isEmpty {
                    let text = payload.0
                    texts.append(text)
                    continue
                }
                if let uri = record.wellKnownTypeURIPayload() {
                    texts.append(uri.absoluteString)
                    continue
                }
                if let payload = String(data: record.payload, encoding: .utf8) {
                    let trimmed = payload.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty {
                        texts.append(trimmed)
                    }
                }
            }
        }
        return texts
    }
}

/// One-shot `NFCNDEFReaderSession`. Read-only. Read-only NDEF session; tag writes are not implemented.
public final class CoreNFCNDEFReader: NSObject, NDEFTagReading, @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<[String], Error>?
    private var session: NFCNDEFReaderSession?

    public override init() {
        super.init()
    }

    public func readTextRecords() async throws -> [String] {
        guard NFCNDEFReaderSession.readingAvailable else {
            throw OnboardingError.unsupportedFormat(reason: "NFC NDEF reading is not available on this device")
        }
        return try await withCheckedThrowingContinuation { continuation in
            lock.lock()
            if self.continuation != nil {
                lock.unlock()
                continuation.resume(
                    throwing: OnboardingError.unsupportedFormat(reason: "an NFC session is already in progress")
                )
                return
            }
            self.continuation = continuation
            let session = NFCNDEFReaderSession(
                delegate: self,
                queue: nil,
                invalidateAfterFirstRead: true
            )
            session.alertMessage = "Hold the owned sensor tag near iPhone. Sugarman only reads NDEF. It does not activate or bind the sensor."
            self.session = session
            lock.unlock()
            session.begin()
        }
    }

    private func finish(with result: Result<[String], Error>) {
        lock.lock()
        let pending = continuation
        continuation = nil
        session = nil
        lock.unlock()
        switch result {
        case .success(let texts):
            pending?.resume(returning: texts)
        case .failure(let error):
            pending?.resume(throwing: error)
        }
    }
}

extension CoreNFCNDEFReader: NFCNDEFReaderSessionDelegate {
    public func readerSession(_ session: NFCNDEFReaderSession, didInvalidateWithError error: Error) {
        _ = session
        let nsError = error as NSError
        if nsError.domain == NFCReaderError.errorDomain,
           nsError.code == NFCReaderError.readerSessionInvalidationErrorFirstNDEFTagRead.rawValue {
            return
        }
        if nsError.domain == NFCReaderError.errorDomain,
           nsError.code == NFCReaderError.readerSessionInvalidationErrorUserCanceled.rawValue {
            finish(with: .failure(OnboardingError.unsupportedFormat(reason: "NFC session cancelled")))
            return
        }
        finish(with: .failure(error))
    }

    public func readerSession(_ session: NFCNDEFReaderSession, didDetectNDEFs messages: [NFCNDEFMessage]) {
        _ = session
        let texts = NDEFTextRecordExtractor.textPayloads(from: messages)
        if texts.isEmpty {
            finish(
                with: .failure(
                    OnboardingError.unsupportedFormat(reason: "NDEF tag contained no text or URI record")
                )
            )
            return
        }
        finish(with: .success(texts))
    }

    public func readerSessionDidBecomeActive(_ session: NFCNDEFReaderSession) {
        _ = session
    }
}
#endif
