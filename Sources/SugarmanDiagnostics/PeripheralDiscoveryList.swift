// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Sugarman contributors

import Foundation
import GS3Transport

/// Presentation-only filtering and ordering for the bounded Bluetooth probe.
///
/// The GS3-name heuristic only helps an owner find a likely sensor in a noisy
/// scan. It is not identity, authentication, or permission to connect.
public enum PeripheralDiscoveryList {
    public static func results(
        from peripherals: [AdvertisementSnapshot],
        searchText: String
    ) -> [AdvertisementSnapshot] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let filtered = peripherals.filter { peripheral in
            guard !query.isEmpty else { return true }
            return peripheral.name?.localizedCaseInsensitiveContains(query) == true
        }

        return filtered.sorted(by: isOrderedBefore)
    }

    /// Mainland GS3 names observed in the owned official-app capture and the
    /// pinned Juggluco reference are 12 uppercase alphanumeric characters
    /// beginning with `AA`. This deliberately remains a narrow heuristic.
    public static func hasObservedGS3NameFormat(_ name: String?) -> Bool {
        guard let name else { return false }
        let scalars = name.unicodeScalars
        guard scalars.count == 12, name.hasPrefix("AA") else { return false }

        return scalars.allSatisfy { scalar in
            switch scalar.value {
            case 48...57, 65...90:
                true
            default:
                false
            }
        }
    }

    private static func isOrderedBefore(
        _ lhs: AdvertisementSnapshot,
        _ rhs: AdvertisementSnapshot
    ) -> Bool {
        let lhsIsCandidate = hasObservedGS3NameFormat(lhs.name)
        let rhsIsCandidate = hasObservedGS3NameFormat(rhs.name)
        if lhsIsCandidate != rhsIsCandidate {
            return lhsIsCandidate
        }

        let lhsRSSI = lhs.rssi ?? Int.min
        let rhsRSSI = rhs.rssi ?? Int.min
        if lhsRSSI != rhsRSSI {
            return lhsRSSI > rhsRSSI
        }

        let lhsName = lhs.name ?? ""
        let rhsName = rhs.name ?? ""
        let nameComparison = lhsName.localizedCaseInsensitiveCompare(rhsName)
        if nameComparison != .orderedSame {
            return nameComparison == .orderedAscending
        }

        return lhs.peripheralID.uuidString < rhs.peripheralID.uuidString
    }
}
