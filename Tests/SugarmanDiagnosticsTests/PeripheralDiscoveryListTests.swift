// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Sugarman contributors

import Foundation
import GS3Transport
import Testing
@testable import SugarmanDiagnostics

struct PeripheralDiscoveryListTests {
    @Test func observedGS3NameFormatRanksAheadOfStrongerUnrelatedDevices() {
        let likelyGS3 = advertisement(
            id: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA",
            name: "AAB12C34D5EF",
            rssi: -92
        )
        let nearbyComputer = advertisement(
            id: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB",
            name: "Nearby Computer",
            rssi: -20
        )
        let unnamed = advertisement(
            id: "CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC",
            name: nil,
            rssi: -10
        )

        let results = PeripheralDiscoveryList.results(
            from: [nearbyComputer, unnamed, likelyGS3],
            searchText: ""
        )

        #expect(results.map(\.peripheralID) == [
            likelyGS3.peripheralID,
            unnamed.peripheralID,
            nearbyComputer.peripheralID,
        ])
    }

    @Test func searchFiltersAdvertisedNamesCaseInsensitively() {
        let likelyGS3 = advertisement(
            id: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA",
            name: "AAB12C34D5EF",
            rssi: -92
        )
        let other = advertisement(
            id: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB",
            name: "FMC BTLE",
            rssi: -40
        )
        let unnamed = advertisement(
            id: "CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC",
            name: nil,
            rssi: -10
        )

        let results = PeripheralDiscoveryList.results(
            from: [likelyGS3, other, unnamed],
            searchText: "  c34d  "
        )

        #expect(results == [likelyGS3])
    }

    @Test func nameFormatHeuristicIsNarrowAndPresentationOnly() {
        #expect(PeripheralDiscoveryList.hasObservedGS3NameFormat("AAB12C34D5EF"))
        #expect(!PeripheralDiscoveryList.hasObservedGS3NameFormat("S2326E3AF42246DB5C"))
        #expect(!PeripheralDiscoveryList.hasObservedGS3NameFormat("aab12c34d5ef"))
        #expect(!PeripheralDiscoveryList.hasObservedGS3NameFormat("AAB12C34D5E!"))
        #expect(!PeripheralDiscoveryList.hasObservedGS3NameFormat(nil))
    }

    private func advertisement(id: String, name: String?, rssi: Int?) -> AdvertisementSnapshot {
        AdvertisementSnapshot(
            peripheralID: UUID(uuidString: id)!,
            name: name,
            rssi: rssi
        )
    }
}
