// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Sugarman contributors

enum OwnerAuthenticationID {
    static func encode(decimal: String) throws -> [UInt8] {
        let bytes = Array(decimal.utf8)
        guard !bytes.isEmpty,
              bytes.count <= 20,
              bytes.allSatisfy({ (0x30...0x39).contains($0) }),
              !(bytes.count > 1 && bytes[0] == 0x30),
              let value = UInt64(decimal),
              value > 0 else {
            throw GS3PrivateHandoverError.invalidUserID
        }
        var encoded: [UInt8] = []
        encoded.reserveCapacity(12)
        for shift in stride(from: 56, through: 0, by: -8) {
            encoded.append(UInt8(truncatingIfNeeded: value >> UInt64(shift)))
        }
        encoded.append(contentsOf: [0, 0, 0, 0])
        return encoded
    }
}
