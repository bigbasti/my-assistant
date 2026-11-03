import Testing
import Foundation
@testable import MyAssistantCore

@MainActor @Suite struct MailDeleteTests {
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    final class FakeDeleter: MailDeleting, @unchecked Sendable {
        var result: MailDeleteResult
        var queries: [MailQuery] = []
        init(_ r: MailDeleteResult) { result = r }
        func moveToTrash(_ q: MailQuery) async -> MailDeleteResult { queries.append(q); return result }
    }

    func model(_ d: FakeDeleter) -> AppModel {
        let m = AppModel(persistence: Persistence(url: FileManager.default.temporaryDirectory.appendingPathComponent("md-\(UUID()).json")),
                         now: { self.t0 })
        m.mailDeleter = d
        return m
    }

    func mail() -> AssistantNotification {
        AssistantNotification(id: "mail:ab", kind: .mail, title: "Quarterly report", sender: "Ben Weber",
                              preview: "p", openURL: nil, firstSurfacedAt: t0.addingTimeInterval(-90), surfacedAt: t0)
    }

    @Test func parsesScriptOutput() {
        #expect(MailDeleteResult(scriptOutput: "deleted\n") == .deleted)
        #expect(MailDeleteResult(scriptOutput: "notfound") == .notFound)
        #expect(MailDeleteResult(scriptOutput: "ambiguous:3") == .ambiguous(3))
        #expect(MailDeleteResult(scriptOutput: "noaccount") == .mailNotSetUp)
        #expect(MailDeleteResult(scriptOutput: "weird") == .failed("weird"))
    }

    @Test func queryUsesSubjectSenderAndAge() async {
        let d = FakeDeleter(.deleted); let m = model(d)
        m.notifications.ingest([mail()])
        _ = await m.deleteMail(mail())
        #expect(d.queries == [MailQuery(subject: "Quarterly report", sender: "Ben Weber", secondsAgo: 90, toleranceSeconds: 300)])
    }

    @Test func deletedRemovesCard() async {
        let m = model(FakeDeleter(.deleted))
        m.notifications.ingest([mail()])
        #expect(await m.deleteMail(mail()) == .deleted)
        #expect(m.notifications.visible.isEmpty)
    }

    @Test func notFoundKeepsCard() async {
        let m = model(FakeDeleter(.notFound))
        m.notifications.ingest([mail()])
        #expect(await m.deleteMail(mail()) == .notFound)
        #expect(m.notifications.visible.map(\.id) == ["mail:ab"])
    }

    @Test func ambiguousKeepsCard() async {
        let m = model(FakeDeleter(.ambiguous(2)))
        m.notifications.ingest([mail()])
        _ = await m.deleteMail(mail())
        #expect(m.notifications.visible.count == 1)
    }

    @Test func messagesAreUserReadable() {
        #expect(MailDeleteResult.notFound.message == "Couldn't find this mail in Apple Mail.")
        #expect(MailDeleteResult.ambiguous(2).message == "2 matching mails found, nothing deleted.")
        #expect(MailDeleteResult.mailNotSetUp.message == "Turn on Mail for your Exchange account in System Settings → Internet Accounts.")
        #expect(MailDeleteResult.notAuthorized.message == "Allow My Assistant to control Mail in System Settings → Privacy & Security → Automation.")
    }
}
