// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Sugarman contributors

/// Inputs needed to reproduce the owned-app V3 authentication frame offline.
///
/// The initializer validates only the lengths proven by the owned binary. It
/// does not establish ownership, derive registration material, or authorize a
/// Bluetooth write. Production logging must use `description`, which omits all
/// values.
public struct V3AuthenticationInputs:
    Sendable, Equatable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable
{
    public let deviceType: UInt8
    let sensorAddress: [UInt8]
    let registeredBlock: [UInt8]
    let authenticationID: [UInt8]
    let initializationVector: [UInt8]

    private init(
        deviceType: UInt8,
        sensorAddress: [UInt8],
        registeredBlock: [UInt8],
        authenticationID: [UInt8],
        initializationVector: [UInt8]
    ) throws {
        guard sensorAddress.count == 6 else {
            throw GS3ProtocolError.invalidSensorAddressLength(sensorAddress.count)
        }
        guard registeredBlock.count == 16 else {
            throw GS3ProtocolError.invalidRegisteredBlockLength(registeredBlock.count)
        }
        guard authenticationID.count <= 12 else {
            throw GS3ProtocolError.invalidAuthenticationIDLength(authenticationID.count)
        }
        guard initializationVector.count == 16 else {
            throw GS3ProtocolError.invalidInitializationVectorLength(initializationVector.count)
        }

        self.deviceType = deviceType
        self.sensorAddress = sensorAddress
        self.registeredBlock = registeredBlock
        self.authenticationID = authenticationID
        self.initializationVector = initializationVector
    }

    public init(
        deviceType: UInt8,
        sensorAddress: [UInt8],
        authenticationID: [UInt8],
        registeredMaterial: V3RegisteredMaterial
    ) throws {
        try self.init(
            deviceType: deviceType,
            sensorAddress: sensorAddress,
            registeredBlock: registeredMaterial.registeredBlock,
            authenticationID: authenticationID,
            initializationVector: registeredMaterial.initializationVector
        )
    }

    /// Builds the already-active handover input from material recovered through
    /// an owner-controlled official-app capture. This does not register, bind,
    /// activate, reset, or otherwise mutate sensor lifecycle state.
    public init(
        deviceType: UInt8,
        sensorAddress: [UInt8],
        authenticationID: [UInt8],
        recoveredRegisteredBlock: [UInt8]
    ) throws {
        try self.init(
            deviceType: deviceType,
            sensorAddress: sensorAddress,
            registeredBlock: recoveredRegisteredBlock,
            authenticationID: authenticationID,
            initializationVector: try v3TransportInitializationVector(
                sensorAddress: sensorAddress
            )
        )
    }

    public var description: String {
        "V3AuthenticationInputs(addressByteCount: \(sensorAddress.count), "
            + "registeredBlockByteCount: \(registeredBlock.count), "
            + "authenticationIDByteCount: \(authenticationID.count), "
            + "initializationVectorByteCount: \(initializationVector.count))"
    }

    public var debugDescription: String { description }

    public var customMirror: Mirror {
        Mirror(
            self,
            children: [
                "deviceType": deviceType,
                "sensorAddressByteCount": sensorAddress.count,
                "registeredBlockByteCount": registeredBlock.count,
                "authenticationIDByteCount": authenticationID.count,
                "initializationVectorByteCount": initializationVector.count,
            ],
            displayStyle: .struct
        )
    }
}

/// Offline-only V3 authentication encoder.
///
/// This type is deliberately not connected to `GS3ProtocolRequest`,
/// `GS3CodecFactory`, or `GS3Transport`. The live request surface remains empty
/// until an owned official-app replay vector matches and a separate physical
/// write is explicitly approved.
public enum V3OfflineAuthenticationCodec: Sendable {
    public static let evidenceRevision = "owned-mainland-gs3-v3-source-map-2026-08-30"

    public static func encode(_ inputs: V3AuthenticationInputs) throws -> EncodedFrame {
        let plaintext = makePlaintext(inputs)
        let encrypted = try AES128OFB.crypt(
            plaintext,
            key: V3ProtocolConstants.fixedKey,
            initializationVector: inputs.initializationVector
        )
        return EncodedFrame(bytes: encrypted)
    }

    private static func makePlaintext(_ inputs: V3AuthenticationInputs) -> [UInt8] {
        var frame: [UInt8] = [0x25, 0xE2, inputs.deviceType]
        frame.reserveCapacity(38)
        frame.append(contentsOf: inputs.sensorAddress)
        frame.append(contentsOf: inputs.registeredBlock)
        frame.append(contentsOf: inputs.authenticationID)
        frame.append(contentsOf: repeatElement(0, count: 12 - inputs.authenticationID.count))

        let checksum = frame.reduce(UInt8.zero) { $0 &+ $1 }
        frame.append(UInt8.zero &- checksum)
        return frame
    }
}

enum V3ProtocolConstants {
    /// Exact 16-byte constant observed at the approved owned-binary source-map
    /// location. The APK and shared library remain excluded from the build and
    /// repository; see docs/V3_AUTH_SOURCE_MAP_2026-08-30.md.
    static let fixedKey: [UInt8] = [
        0x01, 0x38, 0x0B, 0x9A, 0x00, 0x5B, 0x02, 0x5D,
        0xCD, 0x9E, 0xC3, 0x99, 0x09, 0x37, 0xAA, 0xE8,
    ]
}

func v3TransportInitializationVector(sensorAddress: [UInt8]) throws -> [UInt8] {
    guard sensorAddress.count == 6 else {
        throw GS3ProtocolError.invalidSensorAddressLength(sensorAddress.count)
    }
    return sensorAddress + [UInt8](repeating: 0, count: 10)
}
