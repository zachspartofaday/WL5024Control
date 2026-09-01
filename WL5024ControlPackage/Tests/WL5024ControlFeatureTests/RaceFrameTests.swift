import Foundation
import Testing
@testable import WL5024ControlFeature

struct RaceFrameTests {
    @Test func encodesRecoveredAutomaticMediaPackets() {
        #expect(Array(WL5024Command.getAutomaticMedia.frame.encoded) == [
            0x00, 0x05, 0x5A, 0x04, 0x00, 0x83, 0x2C, 0x02, 0x00,
        ])
        #expect(Array(WL5024Command.setAutomaticMedia(false).frame.encoded) == [
            0x00, 0x05, 0x5A, 0x05, 0x00, 0x82, 0x2C, 0x02, 0x00, 0x00,
        ])
        #expect(Array(WL5024Command.setAutomaticMedia(true).frame.encoded) == [
            0x00, 0x05, 0x5A, 0x05, 0x00, 0x82, 0x2C, 0x02, 0x00, 0x01,
        ])
    }

    @Test func decodesFrameInsideTransportWrapper() throws {
        let wrapped = Data([0xA1, 0x02]) + WL5024Command.getAutomaticMedia.frame.encoded + Data([0xEE])
        let decoded = try RaceFrame(decoding: wrapped)
        #expect(decoded == WL5024Command.getAutomaticMedia.frame)
    }

    @Test func decodesAutomaticMediaResponse() throws {
        let response = RaceFrame(opcode: 0x2C83, payload: Data([0x02, 0x00, 0x00])).encoded
        #expect(try WL5024Command.getAutomaticMedia.decodeAutomaticMedia(from: response) == false)
    }

    @Test func matcherRejectsUnsolicitedAndWrongModuleFrames() {
        let matcher = WL5024Command.getAutomaticMedia.transaction.expectedResponse
        let unsolicited = RaceFrame(opcode: 0x0E17, payload: Data([0x03, 0x01])).encoded
        let wrongModule = RaceFrame(opcode: 0x2C83, payload: Data([0x09, 0x00, 0x01])).encoded
        let matching = RaceFrame(opcode: 0x2C83, payload: Data([0x02, 0x00, 0x01])).encoded

        #expect(!matcher.matches(unsolicited))
        #expect(!matcher.matches(wrongModule))
        #expect(matcher.matches(matching))
        #expect(TransactionResponseRouter.classify(unsolicited, pending: matcher) == .unsolicited)
        #expect(TransactionResponseRouter.classify(wrongModule, pending: matcher) == .unsolicited)
        #expect(TransactionResponseRouter.classify(matching, pending: matcher) == .matched)
    }
}
