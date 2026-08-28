// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Sugarman contributors

import Foundation
import Testing
import SugarmanDomain
@testable import GS3Protocol

struct GS3ProtocolTests {
    @Test func noLiveRequestsAreRepresentable() {
        #expect(GS3ProtocolRequest.allCases.isEmpty)
    }

    @Test func unknownAndRC4FailClosed() {
        for variant in ProtocolVariant.allCases {
            let codec = UnimplementedGS3Codec(variant: variant)
            #expect(throws: GS3ProtocolError.unimplementedVariant(variant)) {
                try codec.decode(EncodedFrame(bytes: [0x00]))
            }
            #expect(throws: GS3ProtocolError.unimplementedVariant(variant)) {
                try GS3CodecFactory.make(variant: variant)
            }
        }
    }

    @Test func factoryNeverReturnsAnImplementedCodec() {
        #expect(ProtocolVariant.allCases.allSatisfy { !$0.isImplemented })
    }

    @Test func encodedFrameDescriptionOmitsBytes() {
        let frame = EncodedFrame(bytes: [0xDE, 0xAD, 0xBE, 0xEF, 0x00])
        let described = String(describing: frame)
        let reflected = String(reflecting: frame)
        #expect(described == "EncodedFrame(byteCount: 5)")
        #expect(reflected == "EncodedFrame(byteCount: 5)")
        #expect(!described.contains("222"))
        #expect(!described.contains("DEAD"))
        #expect(!reflected.contains("222"))
        #expect(frame.bytes == [0xDE, 0xAD, 0xBE, 0xEF, 0x00])
    }
}
