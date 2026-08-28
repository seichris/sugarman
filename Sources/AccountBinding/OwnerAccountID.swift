// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Sugarman contributors

import Foundation

public enum AccountBindingError: Error, Sendable, Equatable {
    case empty
    case tooLong
    case invalidCharacters
    case emailNotAccepted
}

extension AccountBindingError: LocalizedError, CustomStringConvertible {
    public var errorDescription: String? { description }
    public var description: String {
        switch self {
        case .empty:
            return "Owner account ID is empty."
        case .tooLong:
            return "Owner account ID exceeds the allowed length."
        case .invalidCharacters:
            return "Owner account ID contains unsupported characters."
        case .emailNotAccepted:
            return "Email addresses are not accepted. Enter the legitimate owner ID only."
        }
    }
}

/// User-entered legitimate owner identifier. Not an email, not an MD5, and
/// not a network login.
public struct OwnerAccountID: Sendable, Hashable, Codable, Equatable {
    public let value: String

    public init(validated value: String) {
        self.value = value
    }
}

public struct ManualOwnerBinding: Sendable {
    public var maximumLength: Int

    public init(maximumLength: Int = 64) {
        self.maximumLength = maximumLength
    }

    public func validate(_ raw: String) throws -> OwnerAccountID {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            throw AccountBindingError.empty
        }
        if trimmed.count > maximumLength {
            throw AccountBindingError.tooLong
        }
        if trimmed.contains("@") {
            throw AccountBindingError.emailNotAccepted
        }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_."))
        if trimmed.unicodeScalars.contains(where: { !allowed.contains($0) }) {
            throw AccountBindingError.invalidCharacters
        }
        return OwnerAccountID(validated: trimmed)
    }
}
