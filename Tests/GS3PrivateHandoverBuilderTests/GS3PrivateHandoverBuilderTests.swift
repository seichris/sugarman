// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Sugarman contributors

import Darwin
import Foundation
import Testing
@testable import GS3DeveloperProbe
@testable import GS3DeviceProvisioning
@testable import GS3PrivateHandoverBuilder
@testable import GS3Protocol

struct GS3PrivateHandoverBuilderTests {
    @Test func successfulGenerationMatchesTheHistoricalStrictSchema() throws {
        let fixture = try Fixture()
        let artifact = try fixture.generate()
        let object = try #require(
            JSONSerialization.jsonObject(with: artifact.encodedData) as? [String: Any]
        )

        #expect(Set(object.keys) == [
            "schemaVersion", "expectedPeripheralName", "sensorAddressHex",
            "authenticationIDHex", "registeredBlockHex", "algorithmKeyHex",
            "algorithmIVHex", "effectiveDataStartIndex",
        ])
        #expect(object["schemaVersion"] as? Int == 1)
        #expect(object["expectedPeripheralName"] as? String == Fixture.name)
        #expect(object["sensorAddressHex"] as? String == Fixture.addressHex)
        #expect(object["authenticationIDHex"] as? String == "010203040506070800000000")
        #expect(object["registeredBlockHex"] as? String == Fixture.registeredBlockHex)
        #expect(object["effectiveDataStartIndex"] as? Int == Int(Fixture.historyStart))

        let probe = try V3ProbeMaterial(importJSONData: artifact.encodedData)
        let bridge = try GS3ProbeProvisioningDocument(importJSONData: artifact.encodedData)
        #expect(probe.expectedPeripheralName == Fixture.name)
        #expect(bridge.captureBackedStart == Fixture.historyStart)
    }

    @Test func deterministicUserIDEncodingRejectsNonCanonicalOrOverflowValues() throws {
        let fixture = try Fixture()
        for invalid in ["", "0", "01", "+1", "1 ", "18446744073709551616"] {
            #expect(throws: GS3PrivateHandoverError.invalidUserID) {
                try fixture.generate(userID: invalid)
            }
        }
        let first = try fixture.generate()
        let second = try fixture.generate()
        #expect(first.encodedData == second.encodedData)
    }

    @Test func captureHeaderAndTruncationFailuresFailClosed() throws {
        let fixture = try Fixture()
        #expect(throws: GS3PrivateHandoverError.invalidCapture) {
            try fixture.generate(capture: Data("not-a-capture".utf8))
        }
        var unsupported = fixture.capture
        unsupported.replaceSubrange(8..<12, with: [0, 0, 0, 2])
        #expect(throws: GS3PrivateHandoverError.unsupportedCapture) {
            try fixture.generate(capture: unsupported)
        }
        #expect(throws: GS3PrivateHandoverError.invalidCapture) {
            try fixture.generate(capture: fixture.capture.dropLastData())
        }
        for length in 0..<fixture.capture.count {
            var rejected = false
            do {
                _ = try fixture.generate(capture: Data(fixture.capture.prefix(length)))
            } catch {
                rejected = true
            }
            #expect(rejected)
        }
    }

    @Test func profileIsStrictVersionPinnedAndNeverInferred() throws {
        let fixture = try Fixture()
        let extra = fixture.profileString.replacingOccurrences(
            of: "\"schemaVersion\":1,",
            with: "\"schemaVersion\":1,\"fallback\":true,"
        )
        #expect(throws: GS3PrivateHandoverError.invalidPrivateProfile) {
            try fixture.generate(profile: Data(extra.utf8))
        }
        let wrongRevision = fixture.profileString.replacingOccurrences(
            of: GS3PrivateProfile.evidenceRevision,
            with: "unsupported-revision"
        )
        #expect(throws: GS3PrivateHandoverError.unsupportedPrivateProfile) {
            try fixture.generate(profile: Data(wrongRevision.utf8))
        }
        let wrongLength = fixture.profileString.replacingOccurrences(
            of: Fixture.algorithmKeyHex,
            with: "00"
        )
        #expect(throws: GS3PrivateHandoverError.invalidPrivateProfile) {
            try fixture.generate(profile: Data(wrongLength.utf8))
        }
        let duplicateKey = fixture.profileString.replacingOccurrences(
            of: "\"schemaVersion\":1,",
            with: "\"schemaVersion\":1,\"schemaVersion\":1,"
        )
        #expect(throws: GS3PrivateHandoverError.invalidPrivateProfile) {
            try fixture.generate(profile: Data(duplicateKey.utf8))
        }
    }

    @Test func absentAndMultipleCandidateSessionsFailClosed() throws {
        let noWrites = try Fixture(options: .init(includeAuthentication: false, includeHistory: false))
        #expect(throws: GS3PrivateHandoverError.missingCandidateSession) {
            try noWrites.generate()
        }

        let fixture = try Fixture()
        let secondSessionPackets = Fixture.makeSessionPackets(
            peer: Data(Fixture.peer.reversed()),
            address: Fixture.address,
            includeAdvertisement: true
        )
        let ambiguous = fixture.capture.appending(records: secondSessionPackets)
        #expect(throws: GS3PrivateHandoverError.ambiguousCandidateSessions) {
            try fixture.generate(capture: ambiguous)
        }
    }

    @Test func advertisedNameMustBeExactCompletePrintableAndUnique() throws {
        let missing = try Fixture(options: .init(includeAdvertisement: false))
        #expect(throws: GS3PrivateHandoverError.missingAdvertisedName) {
            try missing.generate()
        }
        let ambiguous = try Fixture(options: .init(secondName: "SYNTHETIC-OTHER"))
        #expect(throws: GS3PrivateHandoverError.ambiguousAdvertisedName) {
            try ambiguous.generate()
        }
        let nonPrintable = try Fixture(options: .init(name: "bad\nname"))
        #expect(throws: GS3PrivateHandoverError.missingAdvertisedName) {
            try nonPrintable.generate()
        }
    }

    @Test func deviceInformationAddressIsRequiredAndByteOrderComesOnlyFromReplay() throws {
        let missing = try Fixture(options: .init(includeDeviceAddressRead: false))
        #expect(throws: GS3PrivateHandoverError.missingDeviceInformationAddress) {
            try missing.generate()
        }
        let arbitrary = try Fixture(options: .init(deviceAddressValue: [9, 9, 9, 9, 9, 9]))
        #expect(throws: GS3PrivateHandoverError.missingDeviceInformationAddress) {
            try arbitrary.generate()
        }
        let reversed = try Fixture(options: .init(deviceAddressValue: Array(Fixture.address.reversed())))
        let object = try #require(
            JSONSerialization.jsonObject(with: reversed.generate().encodedData) as? [String: Any]
        )
        #expect(object["sensorAddressHex"] as? String == Fixture.addressHex)
    }

    @Test func authenticationMustBeUniqueAndPassExactReplay() throws {
        let missing = try Fixture(options: .init(includeAuthentication: false))
        #expect(throws: GS3PrivateHandoverError.missingAuthenticationWrite) {
            try missing.generate()
        }
        let conflicting = try Fixture(options: .init(conflictingAuthentication: true))
        #expect(throws: GS3PrivateHandoverError.conflictingAuthenticationWrites) {
            try conflicting.generate()
        }
        let tampered = try Fixture(options: .init(tamperAuthentication: true))
        #expect(throws: GS3PrivateHandoverError.authenticationReplayFailed) {
            try tampered.generate()
        }
        let fixture = try Fixture()
        #expect(throws: GS3PrivateHandoverError.authenticationReplayFailed) {
            try fixture.generate(userID: "1")
        }
    }

    @Test func historyRequiresOneRequestAndItsFirstFollowingValidBatch() throws {
        let missing = try Fixture(options: .init(includeHistory: false))
        #expect(throws: GS3PrivateHandoverError.missingHistoryRequest) {
            try missing.generate()
        }
        let ambiguous = try Fixture(options: .init(secondHistoryStart: 0x2345))
        #expect(throws: GS3PrivateHandoverError.ambiguousHistoryRequests) {
            try ambiguous.generate()
        }
        let noBatch = try Fixture(options: .init(includeBatch: false))
        #expect(throws: GS3PrivateHandoverError.missingFollowingDataBatch) {
            try noBatch.generate()
        }
        let invalid = try Fixture(options: .init(tamperBatch: true))
        #expect(throws: GS3PrivateHandoverError.invalidFollowingDataBatch) {
            try invalid.generate()
        }
        let mismatch = try Fixture(options: .init(batchStart: 0x1235))
        #expect(throws: GS3PrivateHandoverError.historyPairMismatch) {
            try mismatch.generate()
        }
    }

    @Test func exactDuplicateCaptureEvidenceIsSuppressed() throws {
        let fixture = try Fixture(options: .init(duplicateEvidence: true))
        let artifact = try fixture.generate()
        #expect(!artifact.encodedData.isEmpty)
    }

    @Test func artifactsProfilesAndErrorsRemainRedactedThroughDescriptionsAndReflection() throws {
        let fixture = try Fixture()
        let artifact = try fixture.generate()
        let profile = try GS3PrivateProfile(jsonData: fixture.profile)
        var text = ""
        dump(artifact, to: &text)
        dump(profile, to: &text)
        for error in allErrors {
            dump(error, to: &text)
            text += error.description
        }
        for secret in fixture.secretStrings {
            #expect(!text.contains(secret))
        }
        #expect(text.contains("redacted"))
    }

    @Test func ownerOnlyWriterIsAtomicAndCleansUpAfterFailure() throws {
        let fixture = try Fixture()
        let artifact = try fixture.generate()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        let output = directory.appendingPathComponent("handover.json")

        try artifact.writeAtomically(to: output)
        var info = stat()
        #expect(lstat(output.path, &info) == 0)
        #expect(info.st_mode & 0o777 == 0o600)
        #expect(try Data(contentsOf: output) == artifact.encodedData)
        #expect(throws: GS3PrivateHandoverError.outputWriteFailed) {
            try artifact.writeAtomically(to: output)
        }
        #expect(try Data(contentsOf: output) == artifact.encodedData)

        #expect(throws: GS3PrivateHandoverError.outputWriteFailed) {
            try artifact.writeAtomically(to: directory)
        }
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: directory.path)
            .filter { $0.hasPrefix(".gs3-private-handover-") }
        #expect(leftovers.isEmpty)
    }

    @Test func cliNeverPrintsPrivateValuesJsonOrPaths() throws {
        let fixture = try Fixture()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        let captureURL = directory.appendingPathComponent("capture-private-token.log")
        let profileURL = directory.appendingPathComponent("profile-private-token.json")
        let outputURL = directory.appendingPathComponent("output-private-token.json")
        try fixture.capture.write(to: captureURL)
        try fixture.profile.write(to: profileURL)
        var standardOutput = ""
        var standardError = ""
        let status = GS3PrivateHandoverCLI.run(
            arguments: [
                "build", "--capture", captureURL.path,
                "--user-id", Fixture.userID,
                "--private-profile", profileURL.path,
                "--output", outputURL.path,
            ],
            writeStandardOutput: { standardOutput += $0 },
            writeStandardError: { standardError += $0 }
        )
        #expect(status == 0)
        #expect(standardOutput == "Private handover written securely.\n")
        #expect(standardError.isEmpty)
        let combined = standardOutput + standardError
        for secret in fixture.secretStrings + [directory.path, "capture-private-token"] {
            #expect(!combined.contains(secret))
        }
        #expect(!combined.contains("schemaVersion"))

        standardOutput = ""
        standardError = ""
        let failed = GS3PrivateHandoverCLI.run(
            arguments: [
                "build", "--capture", captureURL.path,
                "--user-id", "wrong-private-id",
                "--private-profile", profileURL.path,
                "--output", outputURL.path,
            ],
            writeStandardOutput: { standardOutput += $0 },
            writeStandardError: { standardError += $0 }
        )
        #expect(failed == 1)
        #expect(standardOutput.isEmpty)
        #expect(standardError.contains("failed closed") || standardError.contains("invalid"))
        #expect(!standardError.contains("wrong-private-id"))
        #expect(!standardError.contains(captureURL.path))

        standardOutput = ""
        standardError = ""
        let collision = GS3PrivateHandoverCLI.run(
            arguments: [
                "build", "--capture", captureURL.path,
                "--user-id", Fixture.userID,
                "--private-profile", profileURL.path,
                "--output", captureURL.path,
            ],
            writeStandardOutput: { standardOutput += $0 },
            writeStandardError: { standardError += $0 }
        )
        #expect(collision == 1)
        #expect(standardOutput.isEmpty)
        #expect(!standardError.contains(captureURL.path))
        #expect(try Data(contentsOf: captureURL) == fixture.capture)

        standardOutput = ""
        standardError = ""
        let missingInput = GS3PrivateHandoverCLI.run(
            arguments: [
                "build", "--capture", directory.appendingPathComponent("missing").path,
                "--user-id", Fixture.userID,
                "--private-profile", profileURL.path,
                "--output", directory.appendingPathComponent("unused").path,
            ],
            writeStandardOutput: { standardOutput += $0 },
            writeStandardError: { standardError += $0 }
        )
        #expect(missingInput == 1)
        #expect(standardOutput.isEmpty)
        #expect(standardError.contains(GS3PrivateHandoverError.inputUnreadable.description))
        #expect(!standardError.contains(directory.path))
    }

    private var allErrors: [GS3PrivateHandoverError] {
        [
            .invalidArguments, .inputUnreadable, .invalidCapture, .unsupportedCapture,
            .invalidUserID, .invalidPrivateProfile, .unsupportedPrivateProfile,
            .missingCandidateSession, .ambiguousCandidateSessions,
            .missingAdvertisedName, .ambiguousAdvertisedName,
            .missingDeviceInformationAddress, .ambiguousDeviceInformationAddress,
            .missingAuthenticationWrite, .conflictingAuthenticationWrites,
            .authenticationReplayFailed, .missingHistoryRequest,
            .ambiguousHistoryRequests, .missingFollowingDataBatch,
            .invalidFollowingDataBatch, .historyPairMismatch, .outputWriteFailed,
        ]
    }
}

private struct Fixture {
    struct Options {
        var includeAdvertisement = true
        var secondName: String?
        var name = Fixture.name
        var includeDeviceAddressRead = true
        var deviceAddressValue = Fixture.address
        var includeAuthentication = true
        var conflictingAuthentication = false
        var tamperAuthentication = false
        var includeHistory = true
        var secondHistoryStart: UInt16?
        var includeBatch = true
        var batchStart = Fixture.historyStart
        var tamperBatch = false
        var duplicateEvidence = false
    }

    static let name = "SYNTHETIC-GS3"
    static let userID = "72623859790382856" // 0x0102030405060708
    static let peer: [UInt8] = [0xA6, 0xA5, 0xA4, 0xA3, 0xA2, 0xA1]
    static let address: [UInt8] = [0xA1, 0xA2, 0xA3, 0xA4, 0xA5, 0xA6]
    static let addressHex = "a1a2a3a4a5a6"
    static let registeredBlock = Array(0x30...0x3F).map(UInt8.init)
    static let registeredBlockHex = "303132333435363738393a3b3c3d3e3f"
    static let algorithmKey = Array(0x40...0x4F).map(UInt8.init)
    static let algorithmKeyHex = "404142434445464748494a4b4c4d4e4f"
    static let algorithmIV = Array(0x50...0x5F).map(UInt8.init)
    static let algorithmIVHex = "505152535455565758595a5b5c5d5e5f"
    static let historyStart: UInt16 = 0x1234

    let capture: Data
    let profile: Data
    let profileString: String

    init(options: Options = Options()) throws {
        capture = Self.makeCapture(options: options)
        profileString = Self.makeProfile()
        profile = Data(profileString.utf8)
    }

    func generate(
        capture: Data? = nil,
        userID: String = Fixture.userID,
        profile: Data? = nil
    ) throws -> GS3PrivateHandoverArtifact {
        try GS3PrivateHandoverBuilder.generate(
            captureData: capture ?? self.capture,
            ownerVisibleUserID: userID,
            privateProfileData: profile ?? self.profile
        )
    }

    var secretStrings: [String] {
        [
            Self.name, Self.userID, Self.addressHex, Self.registeredBlockHex,
            Self.algorithmKeyHex, Self.algorithmIVHex, String(Self.historyStart),
        ]
    }

    static func makeCapture(options: Options) -> Data {
        var records = makeSessionPackets(
            peer: Data(peer),
            address: address,
            includeAdvertisement: options.includeAdvertisement,
            name: options.name,
            secondName: options.secondName,
            includeDeviceAddressRead: options.includeDeviceAddressRead,
            deviceAddressValue: options.deviceAddressValue,
            includeAuthentication: options.includeAuthentication,
            conflictingAuthentication: options.conflictingAuthentication,
            tamperAuthentication: options.tamperAuthentication,
            includeHistory: options.includeHistory,
            secondHistoryStart: options.secondHistoryStart,
            includeBatch: options.includeBatch,
            batchStart: options.batchStart,
            tamperBatch: options.tamperBatch
        )
        if options.duplicateEvidence {
            records.insert(records[0], at: 1)
            if let auth = records.first(where: { $0.contains(Data([0x12, 0x32, 0x00])) }) {
                records.append(auth)
            }
            if records.count >= 2 {
                records.append(records[records.count - 2])
                records.append(records[records.count - 2])
            }
        }
        return Data.btsnoop(records: records)
    }

    static func makeSessionPackets(
        peer: Data,
        address: [UInt8],
        includeAdvertisement: Bool,
        name: String = Fixture.name,
        secondName: String? = nil,
        includeDeviceAddressRead: Bool = true,
        deviceAddressValue: [UInt8] = Fixture.address,
        includeAuthentication: Bool = true,
        conflictingAuthentication: Bool = false,
        tamperAuthentication: Bool = false,
        includeHistory: Bool = true,
        secondHistoryStart: UInt16? = nil,
        includeBatch: Bool = true,
        batchStart: UInt16 = Fixture.historyStart,
        tamperBatch: Bool = false
    ) -> [Data] {
        var packets: [Data] = []
        if includeAdvertisement {
            packets.append(advertisement(peer: peer, name: name))
            if let secondName {
                packets.append(advertisement(peer: peer, name: secondName))
            }
        }
        packets.append(connection(peer: peer))
        packets.append(acl(att: Data([0x08, 0x01, 0x00, 0xFF, 0xFF, 0x03, 0x28])))
        packets.append(acl(att: characteristicDeclarations()))
        if includeDeviceAddressRead {
            packets.append(acl(att: Data([0x0A, 0x40, 0x00])))
            packets.append(acl(att: Data([0x0B] + deviceAddressValue)))
        }

        let authID = [UInt8](1...8) + [0, 0, 0, 0]
        let inputs = try! V3AuthenticationInputs(
            deviceType: 0,
            sensorAddress: address,
            authenticationID: authID,
            recoveredRegisteredBlock: registeredBlock
        )
        var authentication = try! V3OfflineAuthenticationCodec.encode(inputs).bytes
        if tamperAuthentication { authentication[0] ^= 0x01 }
        if includeAuthentication {
            packets.append(acl(att: Data([0x12, 0x32, 0x00] + authentication)))
            if conflictingAuthentication {
                authentication[1] ^= 0x01
                packets.append(acl(att: Data([0x12, 0x32, 0x00] + authentication)))
            }
        }
        if includeHistory {
            let request = try! V3OfflineEffectiveDataRequestCodec.encode(
                V3EffectiveDataRequest(startingIndex: historyStart),
                sensorAddress: address
            ).bytes
            packets.append(acl(att: Data([0x12, 0x32, 0x00] + request)))
            if let secondHistoryStart {
                let other = try! V3OfflineEffectiveDataRequestCodec.encode(
                    V3EffectiveDataRequest(startingIndex: secondHistoryStart),
                    sensorAddress: address
                ).bytes
                packets.append(acl(att: Data([0x12, 0x32, 0x00] + other)))
            }
        }
        if includeBatch {
            var batch = encryptedBatch(start: batchStart, address: address)
            if tamperBatch { batch[23] ^= 0x01 }
            packets.append(acl(att: Data([0x1B, 0x31, 0x00] + batch)))
        }
        return packets
    }

    private static func makeProfile() -> String {
        """
        {"schemaVersion":1,"evidenceRevision":"\(GS3PrivateProfile.evidenceRevision)","officialAppVersion":"\(GS3PrivateProfile.officialAppVersion)","nativeLibrarySHA256":"\(GS3PrivateProfile.nativeLibrarySHA256)","algorithmKeyHex":"\(algorithmKeyHex)","algorithmIVHex":"\(algorithmIVHex)"}
        """
    }

    private static func characteristicDeclarations() -> Data {
        Data([
            0x09, 0x07,
            0x30, 0x00, 0x10, 0x31, 0x00, 0x31, 0xFF,
            0x33, 0x00, 0x08, 0x32, 0x00, 0x32, 0xFF,
            0x3F, 0x00, 0x02, 0x40, 0x00, 0x25, 0x2A,
        ])
    }

    private static func encryptedBatch(start: UInt16, address: [UInt8]) -> [UInt8] {
        var plaintext: [UInt8] = [
            23, 0x32, 1,
            UInt8(truncatingIfNeeded: start), UInt8(truncatingIfNeeded: start >> 8),
        ]
        plaintext.append(contentsOf: Array(repeating: 0, count: 16))
        plaintext.append(UInt8(truncatingIfNeeded: start))
        plaintext.append(UInt8(truncatingIfNeeded: start >> 8))
        plaintext.append(UInt8.zero &- plaintext.reduce(UInt8.zero, &+))
        return try! AES128OFB.crypt(
            plaintext,
            key: V3ProtocolConstants.fixedKey,
            initializationVector: address + Array(repeating: 0, count: 10)
        )
    }

    private static func advertisement(peer: Data, name: String) -> Data {
        let nameBytes = [UInt8](name.utf8)
        let advertisingData = Data([UInt8(nameBytes.count + 1), 0x09] + nameBytes)
        var parameters = Data([0x02, 0x01, 0x00, 0x00])
        parameters.append(peer)
        parameters.append(UInt8(advertisingData.count))
        parameters.append(advertisingData)
        parameters.append(0xC0)
        return Data([0x04, 0x3E, UInt8(parameters.count)]) + parameters
    }

    private static func connection(peer: Data) -> Data {
        var parameters = Data([0x01, 0x00, 0x01, 0x00, 0x00, 0x00])
        parameters.append(peer)
        parameters.append(contentsOf: Array(repeating: 0, count: 7))
        return Data([0x04, 0x3E, UInt8(parameters.count)]) + parameters
    }

    private static func acl(att: Data) -> Data {
        var l2cap = Data()
        l2cap.appendUInt16LE(UInt16(att.count))
        l2cap.appendUInt16LE(0x0004)
        l2cap.append(att)
        var packet = Data([0x02])
        packet.appendUInt16LE(0x0001)
        packet.appendUInt16LE(UInt16(l2cap.count))
        packet.append(l2cap)
        return packet
    }
}

private extension Data {
    static func btsnoop(records: [Data]) -> Data {
        var data = Data("btsnoop\0".utf8)
        data.appendUInt32BE(1)
        data.appendUInt32BE(1002)
        return data.appending(records: records)
    }

    func appending(records: [Data]) -> Data {
        var result = self
        for (index, packet) in records.enumerated() {
            result.appendUInt32BE(UInt32(packet.count))
            result.appendUInt32BE(UInt32(packet.count))
            result.appendUInt32BE(0)
            result.appendUInt32BE(0)
            result.appendUInt64BE(UInt64(index + 1))
            result.append(packet)
        }
        return result
    }

    func dropLastData() -> Data {
        Data(dropLast())
    }

    mutating func appendUInt16LE(_ value: UInt16) {
        append(UInt8(truncatingIfNeeded: value))
        append(UInt8(truncatingIfNeeded: value >> 8))
    }

    mutating func appendUInt32BE(_ value: UInt32) {
        for shift in stride(from: 24, through: 0, by: -8) {
            append(UInt8(truncatingIfNeeded: value >> UInt32(shift)))
        }
    }

    mutating func appendUInt64BE(_ value: UInt64) {
        for shift in stride(from: 56, through: 0, by: -8) {
            append(UInt8(truncatingIfNeeded: value >> UInt64(shift)))
        }
    }
}
