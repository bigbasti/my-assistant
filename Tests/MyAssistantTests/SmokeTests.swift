import Testing
@testable import MyAssistantCore

@Suite struct SmokeTests {
    @Test func versionIsSet() { #expect(AppInfo.version == "0.1.0") }
}
