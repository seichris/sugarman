// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Sugarman contributors

import Foundation

/// Stable identity for an owned sensor. Serials are stored redacted.
public struct SensorIdentity: Sendable, Equatable, Codable, Identifiable, Hashable {
    public var id: UUID
    public var productName: String?
    public var sku: String?
    public var gtin: String?
    public var redactedSerial: String
    public var udiIssuingAgency: String?
    public var peerUUID: UUID?
    public var firmwareRevision: String?
    public var hardwareRevision: String?
    public var manufacturer: String?
    public var protocolVariant: ProtocolVariant
    public var classificationEvidenceRevision: String

    public init(
        id: UUID = UUID(),
        productName: String? = nil,
        sku: String? = nil,
        gtin: String? = nil,
        redactedSerial: String,
        udiIssuingAgency: String? = nil,
        peerUUID: UUID? = nil,
        firmwareRevision: String? = nil,
        hardwareRevision: String? = nil,
        manufacturer: String? = nil,
        protocolVariant: ProtocolVariant = .unknown,
        classificationEvidenceRevision: String = "none"
    ) {
        self.id = id
        self.productName = productName
        self.sku = sku
        self.gtin = gtin
        self.redactedSerial = redactedSerial
        self.udiIssuingAgency = udiIssuingAgency
        self.peerUUID = peerUUID
        self.firmwareRevision = firmwareRevision
        self.hardwareRevision = hardwareRevision
        self.manufacturer = manufacturer
        self.protocolVariant = protocolVariant
        self.classificationEvidenceRevision = classificationEvidenceRevision
    }
}
