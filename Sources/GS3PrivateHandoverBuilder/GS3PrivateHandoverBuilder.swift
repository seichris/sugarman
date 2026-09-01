// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Sugarman contributors

import Foundation
import GS3Protocol

public struct GS3PrivateHandoverArtifact:
    Sendable, CustomStringConvertible, CustomDebugStringConvertible,
    CustomReflectable
{
    private let data: Data

    init(data: Data) {
        self.data = data
    }

    public func writeAtomically(to outputURL: URL) throws {
        try OwnerOnlyAtomicWriter.write(data, to: outputURL)
    }

    var encodedData: Data { data }

    public var description: String {
        "GS3PrivateHandoverArtifact(privateDocument: redacted)"
    }

    public var debugDescription: String { description }

    public var customMirror: Mirror {
        Mirror(
            self,
            children: ["privateDocument": "redacted"],
            displayStyle: .struct
        )
    }
}

public enum GS3PrivateHandoverBuilder: Sendable {
    public static func generate(
        captureData: Data,
        ownerVisibleUserID: String,
        privateProfileData: Data
    ) throws -> GS3PrivateHandoverArtifact {
        let capture = try PrivateBTSnoopCapture.parse(captureData)
        let authenticationID = try OwnerAuthenticationID.encode(
            decimal: ownerVisibleUserID
        )
        let profile = try GS3PrivateProfile(jsonData: privateProfileData)

        let candidateSessions = capture.sessions.filter { session in
            session.attPayloads.contains { payload in
                payload.kind == .write
                    && (payload.value.count == 38
                        || shortUUID(session.characteristicUUIDs[payload.handle]) == "FF32")
            }
        }
        guard !candidateSessions.isEmpty else {
            throw GS3PrivateHandoverError.missingCandidateSession
        }
        guard candidateSessions.count == 1,
              let session = candidateSessions.first else {
            throw GS3PrivateHandoverError.ambiguousCandidateSessions
        }

        let candidate = try extract(
            session: session,
            completeNames: capture.completeNamesByPeer[session.peerAddress] ?? [],
            authenticationID: authenticationID
        )
        _ = try V3GlucoseCryptoMaterial(
            sensorAddress: candidate.sensorAddress,
            algorithmKey: profile.algorithmKey,
            algorithmInitializationVector: profile.algorithmInitializationVector
        )

        let document = HandoverDocument(
            schemaVersion: 1,
            expectedPeripheralName: candidate.expectedPeripheralName,
            sensorAddressHex: hex(candidate.sensorAddress),
            authenticationIDHex: hex(authenticationID),
            registeredBlockHex: hex(candidate.registeredBlock),
            algorithmKeyHex: hex(profile.algorithmKey),
            algorithmIVHex: hex(profile.algorithmInitializationVector),
            effectiveDataStartIndex: candidate.effectiveDataStartIndex
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        do {
            var data = try encoder.encode(document)
            data.append(0x0A)
            return GS3PrivateHandoverArtifact(data: data)
        } catch {
            throw GS3PrivateHandoverError.invalidPrivateProfile
        }
    }

    private struct ExtractedCandidate {
        let expectedPeripheralName: String
        let sensorAddress: [UInt8]
        let registeredBlock: [UInt8]
        let effectiveDataStartIndex: UInt16
    }

    private static func extract(
        session: PrivateBTSnoopCapture.Session,
        completeNames: Set<String>,
        authenticationID: [UInt8]
    ) throws -> ExtractedCandidate {
        guard !completeNames.isEmpty else {
            throw GS3PrivateHandoverError.missingAdvertisedName
        }
        guard completeNames.count == 1, let name = completeNames.first else {
            throw GS3PrivateHandoverError.ambiguousAdvertisedName
        }
        let nameBytes = Array(name.utf8)
        guard !nameBytes.isEmpty,
              nameBytes.count <= 64,
              nameBytes.allSatisfy({ $0 >= 0x20 && $0 < 0x7F }) else {
            throw GS3PrivateHandoverError.missingAdvertisedName
        }

        let addressCandidates = deviceAddressCandidates(
            values: session.deviceInformationValues,
            hciPeer: session.peerAddress
        )
        guard !addressCandidates.isEmpty else {
            throw GS3PrivateHandoverError.missingDeviceInformationAddress
        }

        let authEvents = session.attPayloads.filter { payload in
            payload.kind == .write
                && payload.value.count == 38
                && shortUUID(session.characteristicUUIDs[payload.handle]) == "FF32"
        }
        guard !authEvents.isEmpty else {
            throw GS3PrivateHandoverError.missingAuthenticationWrite
        }
        let distinctAuthenticationWrites = Set(authEvents.map(\.value))
        guard distinctAuthenticationWrites.count == 1,
              let authenticationCiphertext = distinctAuthenticationWrites.first else {
            throw GS3PrivateHandoverError.conflictingAuthenticationWrites
        }
        let authenticationOrdinal = authEvents.map(\.ordinal).min() ?? 0

        var replayMatches: [(address: [UInt8], registeredBlock: [UInt8])] = []
        for addressData in addressCandidates {
            let address = [UInt8](addressData)
            if let block = try? V3OfflineCaptureInspector.recoverRegisteredBlock(
                authenticationCiphertext: EncodedFrame(
                    bytes: [UInt8](authenticationCiphertext)
                ),
                sensorAddress: address,
                authenticationID: authenticationID
            ) {
                replayMatches.append((address, block))
            }
        }
        guard !replayMatches.isEmpty else {
            throw GS3PrivateHandoverError.authenticationReplayFailed
        }
        guard replayMatches.count == 1, let replay = replayMatches.first else {
            throw GS3PrivateHandoverError.ambiguousDeviceInformationAddress
        }

        var historyCandidates: [Data: (ordinal: Int, start: UInt16)] = [:]
        for payload in session.attPayloads where payload.kind == .write {
            guard payload.ordinal > authenticationOrdinal,
                  payload.value.count == 7,
                  shortUUID(session.characteristicUUIDs[payload.handle]) == "FF32",
                  let start = try? V3OfflineCaptureInspector.historyStart(
                      requestCiphertext: EncodedFrame(bytes: [UInt8](payload.value)),
                      sensorAddress: replay.address
                  ) else {
                continue
            }
            if historyCandidates[payload.value] == nil {
                historyCandidates[payload.value] = (payload.ordinal, start)
            }
        }
        guard !historyCandidates.isEmpty else {
            throw GS3PrivateHandoverError.missingHistoryRequest
        }
        guard historyCandidates.count == 1,
              let history = historyCandidates.values.first else {
            throw GS3PrivateHandoverError.ambiguousHistoryRequests
        }

        let following = session.attPayloads
            .filter { payload in
                payload.kind == .notification
                    && payload.ordinal > history.ordinal
                    && payload.value.count >= 24
                    && shortUUID(session.characteristicUUIDs[payload.handle]) == "FF31"
            }
            .sorted { $0.ordinal < $1.ordinal }
            .first
        guard let following else {
            throw GS3PrivateHandoverError.missingFollowingDataBatch
        }
        let batchStart: UInt16
        do {
            batchStart = try V3OfflineCaptureInspector.dataBatchStart(
                ciphertext: EncodedFrame(bytes: [UInt8](following.value)),
                sensorAddress: replay.address
            )
        } catch {
            throw GS3PrivateHandoverError.invalidFollowingDataBatch
        }
        guard batchStart == history.start else {
            throw GS3PrivateHandoverError.historyPairMismatch
        }

        return ExtractedCandidate(
            expectedPeripheralName: name,
            sensorAddress: replay.address,
            registeredBlock: replay.registeredBlock,
            effectiveDataStartIndex: history.start
        )
    }

    private static func deviceAddressCandidates(
        values: [Data],
        hciPeer: Data
    ) -> Set<Data> {
        let peer = [UInt8](hciPeer)
        var candidates: Set<Data> = []
        for value in values {
            let parsed: [UInt8]?
            if value.count == 6 {
                parsed = [UInt8](value)
            } else {
                parsed = parseTextualAddress(value)
            }
            guard let parsed,
                  parsed == peer || parsed == Array(peer.reversed()) else {
                continue
            }
            candidates.insert(Data(parsed))
            candidates.insert(Data(parsed.reversed()))
        }
        return candidates
    }

    private static func parseTextualAddress(_ data: Data) -> [UInt8]? {
        guard let text = String(data: data, encoding: .utf8) else { return nil }
        let compact = text.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ":", with: "")
            .replacingOccurrences(of: "-", with: "")
        let bytes = Array(compact.utf8)
        guard bytes.count == 12,
              bytes.allSatisfy({ byte in
                  (0x30...0x39).contains(byte)
                      || (0x41...0x46).contains(byte)
                      || (0x61...0x66).contains(byte)
              }) else {
            return nil
        }
        var result: [UInt8] = []
        for offset in stride(from: 0, to: bytes.count, by: 2) {
            guard let value = UInt8(String(decoding: bytes[offset...(offset + 1)], as: UTF8.self), radix: 16) else {
                return nil
            }
            result.append(value)
        }
        return result
    }

    private static func hex(_ bytes: [UInt8]) -> String {
        bytes.map { String(format: "%02x", $0) }.joined()
    }

    private struct HandoverDocument: Encodable {
        let schemaVersion: Int
        let expectedPeripheralName: String
        let sensorAddressHex: String
        let authenticationIDHex: String
        let registeredBlockHex: String
        let algorithmKeyHex: String
        let algorithmIVHex: String
        let effectiveDataStartIndex: UInt16
    }
}

private func shortUUID(_ uuid: String?) -> String? {
    guard let uuid else { return nil }
    let upper = uuid.uppercased()
    if upper.count == 4 { return upper }
    if upper.hasSuffix("-0000-1000-8000-00805F9B34FB"), upper.count >= 8 {
        return String(upper.prefix(8).suffix(4))
    }
    return nil
}
