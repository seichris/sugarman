// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Sugarman contributors

import Foundation
import Testing
@testable import AccountBinding

struct AccountBindingTests {
    let binding = ManualOwnerBinding()

    @Test func acceptsManualOwnerID() throws {
        let id = try binding.validate(" owner-123 ")
        #expect(id.value == "owner-123")
    }

    @Test func rejectsEmail() {
        #expect(throws: AccountBindingError.emailNotAccepted) {
            try binding.validate("user@example.com")
        }
    }

    @Test func rejectsEmptyAndWeirdCharacters() {
        #expect(throws: AccountBindingError.empty) {
            try binding.validate(" ")
        }
        #expect(throws: AccountBindingError.invalidCharacters) {
            try binding.validate("id with spaces")
        }
    }

    @Test func codableCannotBypassValidation() throws {
        let valid = try binding.validate("owner-123")
        let roundTrip = try JSONDecoder().decode(
            OwnerAccountID.self,
            from: JSONEncoder().encode(valid)
        )
        #expect(roundTrip == valid)

        let invalid = Data(#"{"value":"user@example.com"}"#.utf8)
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(OwnerAccountID.self, from: invalid)
        }
    }
}
