import Testing
import Foundation
@testable import MyAssistantCore

@MainActor @Suite struct AppKeeperTests {
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    func app(_ name: String = "Slack", enabled: Bool = true) -> WatchedItem {
        WatchedItem(name: name, enabled: enabled, target: .app(bundleID: "com.tinyspeck.slackmacgap", path: "/Applications/Slack.app"))
    }

    final class World {
        var running: Set<UUID> = []
        var launched: [UUID] = []
        var now: Date
        init(now: Date) { self.now = now }
    }

    func keeper(_ items: [WatchedItem], world: World, on: Bool = true) -> (AppKeeper, AppModel) {
        let m = AppModel(persistence: Persistence(url: FileManager.default.temporaryDirectory.appendingPathComponent("ak-\(UUID()).json")))
        m.settings.watched = items
        m.settings.keepAppsRunning = on
        let k = AppKeeper(model: m, isRunning: { world.running.contains($0.id) },
                          launch: { world.launched.append($0.id); world.running.insert($0.id) },
                          now: { world.now })
        return (k, m)
    }

    // MARK: crash-loop guard

    @Test func guardPausesAfterThreeQuickDeaths() {
        var g = CrashLoopGuard()
        let id = UUID()
        var t = t0
        for _ in 0..<2 {
            #expect(g.decide(id, now: t) == .restart)
            g.noteRestart(id, at: t)
            t += 10
        }
        #expect(g.decide(id, now: t) == .restart)
        g.noteRestart(id, at: t)
        t += 10
        #expect(g.decide(id, now: t) == .pause)
    }

    @Test func slowDeathsResetTheCounter() {
        var g = CrashLoopGuard()
        let id = UUID()
        var t = t0
        for _ in 0..<5 {
            #expect(g.decide(id, now: t) == .restart)
            g.noteRestart(id, at: t)
            t += 31
        }
    }

    @Test func resetClearsPause() {
        var g = CrashLoopGuard()
        let id = UUID()
        var t = t0
        for _ in 0..<3 { _ = g.decide(id, now: t); g.noteRestart(id, at: t); t += 5 }
        #expect(g.decide(id, now: t) == .pause)
        g.reset(id)
        #expect(g.decide(id, now: t) == .restart)
    }

    // MARK: keeper

    @Test func missingAppIsLaunched() {
        let w = World(now: t0); let a = app()
        let (k, _) = keeper([a], world: w)
        k.check()
        #expect(w.launched == [a.id])
        #expect(k.status[a.id] == .restarted(t0))
    }

    @Test func runningAppIsLeftAlone() {
        let w = World(now: t0); let a = app()
        w.running = [a.id]
        let (k, _) = keeper([a], world: w)
        k.check()
        #expect(w.launched.isEmpty)
        #expect(k.status[a.id] == .running)
    }

    @Test func disabledItemOrGlobalOffIsIgnored() {
        let w = World(now: t0); let a = app(enabled: false); let b = app("Other")
        let (k, _) = keeper([a], world: w)
        k.check()
        #expect(w.launched.isEmpty && k.status[a.id] == .off)
        let (k2, _) = keeper([b], world: w, on: false)
        k2.check()
        #expect(w.launched.isEmpty && k2.status[b.id] == .off)
    }

    @Test func crashLoopPausesAndReEnableResumes() {
        let w = World(now: t0); let a = app()
        let (k, m) = keeper([a], world: w)
        for _ in 0..<3 { k.check(); w.running.remove(a.id); w.now += 5 }
        k.check()
        #expect(k.status[a.id] == .paused)
        #expect(w.launched.count == 3)
        m.settings.watched[0].enabled = false; k.check()
        m.settings.watched[0].enabled = true; k.check()
        #expect(w.launched.count == 4)
    }

    // MARK: model + helpers

    @Test func watchedItemsRoundTripAndDefaults() throws {
        let old = #"{"settings":{"playTone":false}}"#.data(using: .utf8)!
        let s = try JSONDecoder().decode(PersistedState.self, from: old)
        #expect(s.settings.watched.isEmpty && s.settings.keepAppsRunning)
        var st = PersistedState()
        st.settings.watched = [app(), WatchedItem(name: "node", enabled: true, target: .process(path: "/usr/local/bin/node", arguments: ["server.js", "--port", "3000"]))]
        let back = try JSONDecoder().decode(PersistedState.self, from: JSONEncoder().encode(st))
        #expect(back.settings.watched == st.settings.watched)
    }

    @Test func processMatchRequiresSameArguments() {
        #expect(ProcessList.matches(path: "/bin/sleep", arguments: ["3600"], candidate: ("/bin/sleep", ["3600"])))
        #expect(!ProcessList.matches(path: "/bin/sleep", arguments: ["3600"], candidate: ("/bin/sleep", ["5"])))
        #expect(!ProcessList.matches(path: "/bin/sleep", arguments: ["3600"], candidate: ("/usr/bin/other", ["3600"])))
    }

    @Test func parsesProcArgs() {
        // KERN_PROCARGS2 layout: argc (Int32), exec path, NUL padding, argv[0..argc-1], then env.
        var data = Data()
        var argc: Int32 = 3
        data.append(Data(bytes: &argc, count: 4))
        data.append("/usr/local/bin/node\0\0\0".data(using: .utf8)!)
        data.append("node\0server.js\0--port=3000\0PATH=/usr/bin\0".data(using: .utf8)!)
        let r = ProcessList.parseProcArgs(data)
        #expect(r?.path == "/usr/local/bin/node")
        #expect(r?.arguments == ["server.js", "--port=3000"])
    }
}
