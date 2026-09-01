// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Sugarman contributors

import Foundation

struct GS3PrivateProfile:
    Sendable, CustomStringConvertible, CustomDebugStringConvertible,
    CustomReflectable
{
    static let schemaVersion = 1
    static let evidenceRevision =
        "owned-mainland-gs3-v3-glucose-source-map-2026-08-30"
    static let officialAppVersion = "01.10.00.00"
    static let nativeLibrarySHA256 =
        "19238019b9aca5f8ffae6a81fad98bb9f6525750b914367378f1ac1bbf765964"

    let algorithmKey: [UInt8]
    let algorithmInitializationVector: [UInt8]

    init(jsonData: Data) throws {
        guard let source = String(data: jsonData, encoding: .utf8),
              Self.requiredKeys.allSatisfy({ key in
                  Self.occurrenceCount(of: key, in: source) == 1
              }) else {
            throw GS3PrivateHandoverError.invalidPrivateProfile
        }
        let object: Any
        do {
            object = try JSONSerialization.jsonObject(with: jsonData)
        } catch {
            throw GS3PrivateHandoverError.invalidPrivateProfile
        }
        guard let dictionary = object as? [String: Any],
              Set(dictionary.keys) == Self.requiredKeys else {
            throw GS3PrivateHandoverError.invalidPrivateProfile
        }

        let document: Document
        do {
            document = try JSONDecoder().decode(Document.self, from: jsonData)
        } catch {
            throw GS3PrivateHandoverError.invalidPrivateProfile
        }
        guard document.schemaVersion == Self.schemaVersion,
              document.evidenceRevision == Self.evidenceRevision,
              document.officialAppVersion == Self.officialAppVersion,
              document.nativeLibrarySHA256 == Self.nativeLibrarySHA256 else {
            throw GS3PrivateHandoverError.unsupportedPrivateProfile
        }
        guard let key = Self.hexBytes(document.algorithmKeyHex), key.count == 16,
              let iv = Self.hexBytes(document.algorithmIVHex), iv.count == 16 else {
            throw GS3PrivateHandoverError.invalidPrivateProfile
        }
        algorithmKey = key
        algorithmInitializationVector = iv
    }

    var description: String {
        "GS3PrivateProfile(revision: pinned, algorithmKey: redacted, algorithmIV: redacted)"
    }

    var debugDescription: String { description }

    var customMirror: Mirror {
        Mirror(
            self,
            children: [
                "revision": "pinned",
                "algorithmKey": "redacted",
                "algorithmIV": "redacted",
            ],
            displayStyle: .struct
        )
    }

    private struct Document: Decodable {
        let schemaVersion: Int
        let evidenceRevision: String
        let officialAppVersion: String
        let nativeLibrarySHA256: String
        let algorithmKeyHex: String
        let algorithmIVHex: String
    }

    private static let requiredKeys: Set<String> = [
        "schemaVersion",
        "evidenceRevision",
        "officialAppVersion",
        "nativeLibrarySHA256",
        "algorithmKeyHex",
        "algorithmIVHex",
    ]

    private static func occurrenceCount(of key: String, in source: String) -> Int {
        let escaped = NSRegularExpression.escapedPattern(for: key)
        guard let expression = try? NSRegularExpression(
            pattern: "\\\"\(escaped)\\\"[\\t\\n\\r ]*:",
            options: []
        ) else {
            return 0
        }
        return expression.numberOfMatches(
            in: source,
            range: NSRange(source.startIndex..<source.endIndex, in: source)
        )
    }

    private static func hexBytes(_ text: String) -> [UInt8]? {
        let source = Array(text.utf8)
        guard source.count.isMultiple(of: 2), source.allSatisfy(isHex) else {
            return nil
        }
        var result: [UInt8] = []
        result.reserveCapacity(source.count / 2)
        for offset in stride(from: 0, to: source.count, by: 2) {
            result.append((nibble(source[offset]) << 4) | nibble(source[offset + 1]))
        }
        return result
    }

    private static func isHex(_ byte: UInt8) -> Bool {
        (0x30...0x39).contains(byte)
            || (0x41...0x46).contains(byte)
            || (0x61...0x66).contains(byte)
    }

    private static func nibble(_ byte: UInt8) -> UInt8 {
        switch byte {
        case 0x30...0x39: byte - 0x30
        case 0x41...0x46: byte - 0x41 + 10
        default: byte - 0x61 + 10
        }
    }
}
