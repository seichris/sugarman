// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Sugarman contributors

/// Opaque, caller-provisioned material for an owned, already-active V3
/// session. It can form only the physically observed authentication and
/// effective-data requests and decode their observed response family.
///
/// This type does not load, derive, persist, import, log, activate, bind,
/// reset, or transmit anything. Production callers must provide the material
/// from a separately reviewed device-only source.
public struct V3ActiveSessionMaterial:
    Sendable, CustomStringConvertible, CustomDebugStringConvertible,
    CustomReflectable
{
    private let sensorAddress: [UInt8]
    private let authenticationID: [UInt8]
    private let registeredBlock: [UInt8]
    private let algorithmKey: [UInt8]
    private let algorithmInitializationVector: [UInt8]

    public init(
        sensorAddress: [UInt8],
        authenticationID: [UInt8],
        registeredBlock: [UInt8],
        algorithmKey: [UInt8],
        algorithmInitializationVector: [UInt8]
    ) throws {
        _ = try V3AuthenticationInputs(
            deviceType: 0,
            sensorAddress: sensorAddress,
            authenticationID: authenticationID,
            recoveredRegisteredBlock: registeredBlock
        )
        _ = try V3GlucoseCryptoMaterial(
            sensorAddress: sensorAddress,
            algorithmKey: algorithmKey,
            algorithmInitializationVector: algorithmInitializationVector
        )
        self.sensorAddress = sensorAddress
        self.authenticationID = authenticationID
        self.registeredBlock = registeredBlock
        self.algorithmKey = algorithmKey
        self.algorithmInitializationVector = algorithmInitializationVector
    }

    package func authenticationFrame() throws -> EncodedFrame {
        try V3OfflineAuthenticationCodec.encode(
            V3AuthenticationInputs(
                deviceType: 0,
                sensorAddress: sensorAddress,
                authenticationID: authenticationID,
                recoveredRegisteredBlock: registeredBlock
            )
        )
    }

    package func effectiveDataFrame(startingIndex: UInt32) throws -> EncodedFrame {
        guard let start = UInt16(exactly: startingIndex) else {
            throw GS3ProtocolError.v3EffectiveDataStartIndexOutOfRange
        }
        return try V3OfflineEffectiveDataRequestCodec.encode(
            V3EffectiveDataRequest(startingIndex: start),
            sensorAddress: sensorAddress
        )
    }

    package func decodeControl(_ frame: EncodedFrame) throws -> V3ControlResponse {
        try V3OfflineControlResponseDecoder.decode(
            frame,
            sensorAddress: sensorAddress
        )
    }

    package func decodeGlucose(_ frame: EncodedFrame) throws -> V3GlucoseBatch {
        try V3OfflineGlucoseNotificationDecoder.decodeBatch(
            frame,
            using: V3GlucoseCryptoMaterial(
                sensorAddress: sensorAddress,
                algorithmKey: algorithmKey,
                algorithmInitializationVector: algorithmInitializationVector
            )
        )
    }

    public var description: String {
        "V3ActiveSessionMaterial(addressBytes: \(sensorAddress.count), "
            + "authenticationIDBytes: \(authenticationID.count), "
            + "registeredBlockBytes: \(registeredBlock.count), "
            + "algorithmKeyBytes: \(algorithmKey.count), "
            + "algorithmIVBytes: \(algorithmInitializationVector.count))"
    }

    public var debugDescription: String { description }

    public var customMirror: Mirror {
        Mirror(
            self,
            children: [
                "sensorAddressByteCount": sensorAddress.count,
                "authenticationIDByteCount": authenticationID.count,
                "registeredBlockByteCount": registeredBlock.count,
                "algorithmKeyByteCount": algorithmKey.count,
                "algorithmIVByteCount": algorithmInitializationVector.count,
            ],
            displayStyle: .struct
        )
    }
}
