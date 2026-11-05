import Testing
import Foundation
@testable import MyAssistantCore

@Suite struct UpdaterTests {
    @Test func versionsCompareNumerically() {
        #expect(AppVersion("1.0.10")! > AppVersion("1.0.9")!)
        #expect(AppVersion("v1.1.0")! > AppVersion("1.0.99")!)
        #expect(AppVersion("1.0.2")! == AppVersion("v1.0.2")!)
        #expect(AppVersion("2")! > AppVersion("1.9.9")!)
        #expect(AppVersion("abc") == nil)
    }

    static let json = #"""
    {"tag_name":"v1.0.7","name":"My Assistant 1.0.7","html_url":"https://github.com/bigbasti/my-assistant/releases/tag/v1.0.7",
     "body":"## Install\n...\n\nSHA-256: `aabbccddeeff00112233445566778899aabbccddeeff00112233445566778899`",
     "assets":[{"name":"checksum.txt","browser_download_url":"https://x/checksum.txt","size":10},
               {"name":"My-Assistant-1.0.7.zip","browser_download_url":"https://github.com/bigbasti/my-assistant/releases/download/v1.0.7/My-Assistant-1.0.7.zip","size":1234567}]}
    """#

    @Test func parsesLatestRelease() throws {
        let r = try ReleaseInfo.parse(Data(Self.json.utf8))
        #expect(r.version == AppVersion("1.0.7"))
        #expect(r.zipURL.absoluteString.hasSuffix("/My-Assistant-1.0.7.zip"))
        #expect(r.zipSize == 1234567)
        #expect(r.sha256 == "aabbccddeeff00112233445566778899aabbccddeeff00112233445566778899")
        #expect(r.notes.hasPrefix("## Install"))
    }

    @Test func releaseWithoutZipIsRejected() {
        let json = #"{"tag_name":"v1.0.8","body":"","html_url":"https://x","assets":[]}"#
        #expect(throws: UpdateError.noDownload) { try ReleaseInfo.parse(Data(json.utf8)) }
    }

    @Test func updateAvailableOnlyWhenNewer() throws {
        let r = try ReleaseInfo.parse(Data(Self.json.utf8))
        #expect(r.isNewer(than: AppVersion("1.0.6")!))
        #expect(!r.isNewer(than: AppVersion("1.0.7")!))
        #expect(!r.isNewer(than: AppVersion("1.1.0")!))
    }

    @Test func checksumOfData() {
        #expect(Updater.sha256(Data("abc".utf8)) == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    }

    @Test func installScriptQuotesPathsAndWaitsForQuit() {
        let s = Updater.installScript(pid: 4242, newApp: "/tmp/up date/My Assistant.app", target: "/Applications/My Assistant.app")
        #expect(s.contains("while kill -0 4242"))
        #expect(s.contains("'/tmp/up date/My Assistant.app'"))
        #expect(s.contains("rm -rf '/Applications/My Assistant.app'"))
        #expect(s.contains("open '/Applications/My Assistant.app'"))
        #expect(Updater.shellQuote("it's") == "'it'\\''s'")
    }

    @Test func autoCheckIsDue() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        #expect(Updater.isAutoCheckDue(last: nil, now: now))
        #expect(!Updater.isAutoCheckDue(last: now.addingTimeInterval(-3600), now: now))
        #expect(Updater.isAutoCheckDue(last: now.addingTimeInterval(-86_401), now: now))
    }
}

@Suite struct UpdatesTabTests {
    @Test func showsOnlyTheChangesSection() {
        let notes = "## Install\n\n1. Download\n\n## Changes\n\n- feat: a\n- fix: b\n\nSHA-256: `abc`"
        #expect(UpdatesTab.changes(in: notes) == "- feat: a\n- fix: b")
    }
}
