import Testing
import Foundation
@testable import MyAssistantCore

@Suite struct AlertMapperTests {
    static let t = Date(timeIntervalSince1970: 1_800_000_000)
    static let view = "{\"actionType\":\"view\",\"messageId\":\"1793626351355\"}"
    static let reply = "{\"actionType\":\"quickReply\",\"convId\":\"19:abc_def@unq.gbl.spaces\"}"

    static func teams(_ strings: [String]) -> AlertRecord {
        AlertRecord(uuidHex: "aa11", bundleID: "com.microsoft.teams2", delivered: t,
                    title: "Anna", subtitle: nil, body: "Hello", category: nil, archivedStrings: strings)
    }

    @Test func teamsFullMapping() {
        let n = AlertMapper.map(Self.teams([Self.view, Self.reply, "19:abc_def@unq.gbl.spaces"]))
        #expect(n?.id == "teams:1793626351355")
        #expect(n?.kind == .teams)
        #expect(n?.title == "Teams message")
        #expect(n?.sender == "Anna")
        #expect(n?.preview == "Hello")
        #expect(n?.openURL?.absoluteString == "msteams:/l/message/19%3Aabc_def%40unq.gbl.spaces/1793626351355")
        #expect(n?.firstSurfacedAt == Self.t)
        #expect(n?.surfacedAt == Self.t)
        #expect(n?.snoozedUntil == nil)
    }

    @Test func teamsChatOnlyUsesChatLink() {
        let n = AlertMapper.map(Self.teams(["19:abc_def@unq.gbl.spaces"]))
        #expect(n?.id == "teams:aa11")
        #expect(n?.openURL?.absoluteString == "msteams:/l/chat/19%3Aabc_def%40unq.gbl.spaces/0")
    }

    @Test func teamsWithoutIDsFallsBack() {
        let n = AlertMapper.map(Self.teams(["junk", "{not json", "[1]"]))
        #expect(n?.id == "teams:aa11")
        #expect(n?.openURL == nil)
    }

    @Test func outlookMapping() {
        let r = AlertRecord(uuidHex: "bb22", bundleID: "com.microsoft.outlook", delivered: Self.t,
                            title: "Subject", subtitle: "Bob", body: "Body", category: nil, archivedStrings: [])
        let n = AlertMapper.map(r)
        #expect(n?.id == "mail:bb22")
        #expect(n?.kind == .mail)
        #expect(n?.title == "Subject")
        #expect(n?.sender == "Bob")
        #expect(n?.preview == "Body")
        #expect(n?.openURL == nil)
    }

    @Test func unknownBundleIsNil() {
        let r = AlertRecord(uuidHex: "cc", bundleID: "com.other", delivered: Self.t,
                            title: "x", subtitle: nil, body: nil, category: nil, archivedStrings: [])
        #expect(AlertMapper.map(r) == nil)
    }

    @Test func freshnessWindow() {
        let r = Self.teams([])
        #expect(AlertMapper.isFresh(r, now: Self.t.addingTimeInterval(24 * 3600 - 60)))
        #expect(!AlertMapper.isFresh(r, now: Self.t.addingTimeInterval(24 * 3600 + 60)))
    }
}
