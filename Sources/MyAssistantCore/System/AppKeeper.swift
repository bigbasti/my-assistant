import AppKit
import Darwin

/// Stops restarting an item that keeps dying right after being restarted.
public struct CrashLoopGuard: Sendable {
    public enum Decision: Equatable, Sendable { case restart, pause }

    /// A death within this many seconds of a restart counts as "quick".
    public static let quickWindow: TimeInterval = 30
    /// Quick deaths in a row before restarting pauses.
    public static let limit = 3

    private var lastRestart: [UUID: Date] = [:]
    private var quickDeaths: [UUID: Int] = [:]
    private var paused: Set<UUID> = []

    public init() {}

    public mutating func decide(_ id: UUID, now: Date) -> Decision {
        if paused.contains(id) { return .pause }
        if let last = lastRestart[id], now.timeIntervalSince(last) <= Self.quickWindow {
            quickDeaths[id, default: 0] += 1
        } else {
            quickDeaths[id] = 0
        }
        if quickDeaths[id, default: 0] >= Self.limit {
            paused.insert(id)
            return .pause
        }
        return .restart
    }

    public mutating func noteRestart(_ id: UUID, at date: Date) { lastRestart[id] = date }

    public mutating func reset(_ id: UUID) {
        lastRestart[id] = nil; quickDeaths[id] = nil; paused.remove(id)
    }
}

/// Restarts watched apps and processes when they're missing.
@Observable @MainActor
public final class AppKeeper {
    public private(set) var status: [UUID: KeeperStatus] = [:]

    @ObservationIgnored private let model: AppModel
    @ObservationIgnored private let isRunning: @MainActor (WatchedItem) -> Bool
    @ObservationIgnored private let launch: @MainActor (WatchedItem) throws -> Void
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private var guardState = CrashLoopGuard()
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var token: NSObjectProtocol?

    public init(model: AppModel,
                isRunning: @escaping @MainActor (WatchedItem) -> Bool = AppKeeper.systemIsRunning,
                launch: @escaping @MainActor (WatchedItem) throws -> Void = AppKeeper.systemLaunch,
                now: @escaping () -> Date = Date.init) {
        self.model = model; self.isRunning = isRunning; self.launch = launch; self.now = now
    }

    public func start() {
        stop()
        check()
        // Apps announce quitting; plain processes are caught by the 5 s check.
        token = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                // Give the app a moment to be fully gone before relaunching.
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) { self?.check() }
            }
        }
        let t = Timer(timeInterval: 5, repeats: true) { [weak self] _ in MainActor.assumeIsolated { self?.check() } }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    public func stop() {
        timer?.invalidate(); timer = nil
        if let token { NSWorkspace.shared.notificationCenter.removeObserver(token) }
        token = nil
    }

    public func check() {
        let on = model.settings.keepAppsRunning
        let items = model.settings.watched
        status = status.filter { id, _ in items.contains { $0.id == id } }
        for item in items {
            guard on, item.enabled else {
                guardState.reset(item.id)
                status[item.id] = .off
                continue
            }
            if isRunning(item) {
                if case .restarted = status[item.id] {} else { status[item.id] = .running }
                continue
            }
            if status[item.id] == .paused { continue }
            switch guardState.decide(item.id, now: now()) {
            case .pause:
                status[item.id] = .paused
            case .restart:
                do {
                    try launch(item)
                    guardState.noteRestart(item.id, at: now())
                    status[item.id] = .restarted(now())
                } catch {
                    status[item.id] = .failed(error.localizedDescription)
                }
            }
        }
    }

    // MARK: system implementations

    public static func systemIsRunning(_ item: WatchedItem) -> Bool {
        switch item.target {
        case .app(let bundleID, let path):
            return NSWorkspace.shared.runningApplications.contains {
                (bundleID != nil && $0.bundleIdentifier == bundleID) || $0.bundleURL?.path == path
            }
        case .process(let path, let arguments):
            return ProcessList.pids(executablePath: path, arguments: arguments).isEmpty == false
        }
    }

    public static func systemLaunch(_ item: WatchedItem) throws {
        switch item.target {
        case .app(_, let path):
            let config = NSWorkspace.OpenConfiguration()
            config.activates = false
            config.addsToRecentItems = false
            // Some apps activate themselves on launch anyway; hand focus back to where the user was.
            let previous = NSWorkspace.shared.frontmostApplication
            NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: path), configuration: config) { launched, _ in
                guard let launched, let previous, previous != launched else { return }
                for delay in [0.3, 1.0, 2.0] {
                    DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                        if NSWorkspace.shared.frontmostApplication == launched { previous.activate() }
                    }
                }
            }
        case .process(let path, let arguments):
            let p = Process()
            p.executableURL = URL(fileURLWithPath: path)
            p.arguments = arguments
            p.standardInput = FileHandle.nullDevice
            p.standardOutput = FileHandle.nullDevice
            p.standardError = FileHandle.nullDevice
            try p.run()
        }
    }
}

/// Lists running apps and processes for the "Pick running…" sheet.
public enum ProcessList {
    public struct Entry: Identifiable, Sendable {
        public var id: String { "\(pid)" }
        public let pid: pid_t
        public let name: String
        public let item: WatchedItem
    }

    @MainActor
    public static func runningApps() -> [Entry] {
        NSWorkspace.shared.runningApplications
            .filter { $0.processIdentifier != getpid() && $0.bundleURL != nil }
            .compactMap { app in
                guard let url = app.bundleURL else { return nil }
                var item = WatchedItem.app(at: url)
                if let n = app.localizedName { item.name = n }
                return Entry(pid: app.processIdentifier, name: item.name, item: item)
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Non-app processes owned by the current user, with their full command line.
    public static func userProcesses() -> [Entry] {
        let uid = getuid()
        return allPIDs().compactMap { pid -> Entry? in
            var info = proc_bsdinfo()
            guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, Int32(MemoryLayout<proc_bsdinfo>.size)) > 0,
                  info.pbi_uid == uid, pid != getpid(),
                  let args = procArgs(pid), !args.path.contains(".app/") else { return nil }
            let name = URL(fileURLWithPath: args.path).lastPathComponent
            return Entry(pid: pid, name: ([name] + args.arguments).joined(separator: " "),
                         item: WatchedItem(name: name, target: .process(path: args.path, arguments: args.arguments)))
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    public static func pids(executablePath: String, arguments: [String]) -> [pid_t] {
        allPIDs().filter { pid in
            guard path(of: pid) == executablePath, let a = procArgs(pid) else { return false }
            return matches(path: executablePath, arguments: arguments, candidate: (a.path, a.arguments))
        }
    }

    public static func matches(path: String, arguments: [String], candidate: (path: String, arguments: [String])) -> Bool {
        candidate.path == path && candidate.arguments == arguments
    }

    static func allPIDs() -> [pid_t] {
        let count = proc_listallpids(nil, 0)
        guard count > 0 else { return [] }
        var pids = [pid_t](repeating: 0, count: Int(count) + 64)
        let n = proc_listallpids(&pids, Int32(pids.count * MemoryLayout<pid_t>.size))
        return Array(pids.prefix(Int(max(0, n)))).filter { $0 > 0 }
    }

    static func path(of pid: pid_t) -> String? {
        var buf = [CChar](repeating: 0, count: Int(MAXPATHLEN) * 4)
        guard proc_pidpath(pid, &buf, UInt32(buf.count)) > 0 else { return nil }
        return String(cString: buf)
    }

    static func procArgs(_ pid: pid_t) -> (path: String, arguments: [String])? {
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        var size = 0
        guard sysctl(&mib, 3, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var data = Data(count: size)
        let ok = data.withUnsafeMutableBytes { sysctl(&mib, 3, $0.baseAddress, &size, nil, 0) == 0 }
        guard ok else { return nil }
        return parseProcArgs(data.prefix(size))
    }

    /// Parses the KERN_PROCARGS2 buffer: argc, exec path, padding NULs, argv (argv[0] dropped).
    public static func parseProcArgs(_ data: Data) -> (path: String, arguments: [String])? {
        guard data.count > 4 else { return nil }
        let argc = data.prefix(4).withUnsafeBytes { $0.loadUnaligned(as: Int32.self) }
        var i = data.startIndex + 4
        func readString() -> String? {
            guard let end = data[i...].firstIndex(of: 0) else { return nil }
            let s = String(decoding: data[i..<end], as: UTF8.self)
            i = end
            return s
        }
        guard let exec = readString(), !exec.isEmpty else { return nil }
        while i < data.endIndex, data[i] == 0 { i += 1 }
        var argv: [String] = []
        while argv.count < argc, i < data.endIndex, let s = readString() {
            argv.append(s)
            i += 1
        }
        return (exec, Array(argv.dropFirst()))
    }
}
