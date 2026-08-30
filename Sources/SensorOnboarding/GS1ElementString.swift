// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Sugarman contributors

import Foundation

/// Independently implemented bounded parser for synthetic GS1/UDI-like
/// element strings. Accepts parenthesized AIs such as `(01)GTIN(21)serial`
/// and concatenated AI 01 / 17 / 10 / 21. Unknown layouts return nil so the
/// package parser can fail closed. This is not a copy of Juggluco PhotoScan
/// and is not hardware proof.
public struct GS1ElementString: Sendable, Equatable {
    public var gtin: String
    public var serial: String
    public var lot: String?
    public var expiryYYMMDD: String?

    public init(gtin: String, serial: String, lot: String? = nil, expiryYYMMDD: String? = nil) {
        self.gtin = gtin
        self.serial = serial
        self.lot = lot
        self.expiryYYMMDD = expiryYYMMDD
    }

    public static let groupSeparator: Character = "\u{001D}"

    public static func parse(_ payload: String) -> GS1ElementString? {
        let trimmed = payload.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return nil }
        if trimmed.contains("(") {
            return parseParenthesized(trimmed)
        }
        return parseConcatenated(trimmed)
    }

    private static func parseParenthesized(_ payload: String) -> GS1ElementString? {
        var fields: [String: String] = [:]
        var remaining = payload[...]
        while let open = remaining.firstIndex(of: "(") {
            let afterOpen = remaining.index(after: open)
            guard let close = remaining[afterOpen...].firstIndex(of: ")") else { return nil }
            let ai = String(remaining[afterOpen..<close])
            guard !ai.isEmpty, ai.allSatisfy(\.isNumber) else { return nil }
            let valueStart = remaining.index(after: close)
            let valueEnd = remaining[valueStart...].firstIndex(of: "(") ?? remaining.endIndex
            let value = String(remaining[valueStart..<valueEnd])
            if value.isEmpty { return nil }
            fields[ai] = value
            remaining = remaining[valueEnd...]
        }
        return make(fields: fields)
    }

    private static func parseConcatenated(_ payload: String) -> GS1ElementString? {
        if payload.contains(where: { $0.isWhitespace }) {
            return nil
        }
        var index = payload.startIndex
        var fields: [String: String] = [:]
        while index < payload.endIndex {
            if payload[index] == groupSeparator {
                index = payload.index(after: index)
                continue
            }
            guard payload.distance(from: index, to: payload.endIndex) >= 2 else { return nil }
            let aiEnd = payload.index(index, offsetBy: 2)
            let ai = String(payload[index..<aiEnd])
            index = aiEnd
            switch ai {
            case "01":
                guard let value = takeFixed(from: payload, index: &index, length: 14),
                      value.allSatisfy(\.isNumber) else { return nil }
                fields[ai] = value
            case "17":
                guard let value = takeFixed(from: payload, index: &index, length: 6),
                      value.allSatisfy(\.isNumber) else { return nil }
                fields[ai] = value
            case "10", "21":
                let value = takeVariable(from: payload, index: &index)
                guard !value.isEmpty else { return nil }
                fields[ai] = value
            default:
                return nil
            }
        }
        return make(fields: fields)
    }

    private static func takeFixed(from payload: String, index: inout String.Index, length: Int) -> String? {
        guard payload.distance(from: index, to: payload.endIndex) >= length else { return nil }
        let end = payload.index(index, offsetBy: length)
        let value = String(payload[index..<end])
        index = end
        return value
    }

    private static func takeVariable(from payload: String, index: inout String.Index) -> String {
        let start = index
        while index < payload.endIndex {
            if payload[index] == groupSeparator {
                break
            }
            index = payload.index(after: index)
        }
        return String(payload[start..<index])
    }

    private static func make(fields: [String: String]) -> GS1ElementString? {
        guard let gtin = fields["01"], gtin.count == 14, gtin.allSatisfy(\.isNumber) else {
            return nil
        }
        guard let serial = fields["21"], !serial.isEmpty else {
            return nil
        }
        let lot = fields["10"]
        let expiry = fields["17"]
        if let expiry, expiry.count != 6 || !expiry.allSatisfy(\.isNumber) {
            return nil
        }
        return GS1ElementString(gtin: gtin, serial: serial, lot: lot, expiryYYMMDD: expiry)
    }
}
