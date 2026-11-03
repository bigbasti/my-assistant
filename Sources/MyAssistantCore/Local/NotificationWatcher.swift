import Foundation

@MainActor
public final class NotificationWatcher {
    private let model: AppModel
    private let read: @Sendable ([String]) throws(NotificationDBError) -> [AlertRecord]
    private let now: () -> Date
    private let dbPath: String
    private var seen: Set<SourceKind> = []
    private var sources: [String: DispatchSourceFileSystemObject] = [:]
    private var debounce: DispatchWorkItem?
    private var timer: DispatchSourceTimer?

    private static let bundles: [(SourceKind, String)] = [(.teams, AlertMapper.teamsBundle), (.mail, AlertMapper.outlookBundle)]

    public init(model: AppModel,
                read: @escaping @Sendable ([String]) throws(NotificationDBError) -> [AlertRecord],
                now: @escaping () -> Date = Date.init,
                dbPath: String = NotificationDatabase.defaultPath) {
        self.model = model
        self.read = read
        self.now = now
        self.dbPath = dbPath
    }

    public func start() {
        stop()
        for path in [dbPath, dbPath + "-wal"] { arm(path) }
        let t = DispatchSource.makeTimerSource(queue: .main)
        t.schedule(deadline: .now() + 5, repeating: 5)
        t.setEventHandler { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                for path in [self.dbPath, self.dbPath + "-wal"] where self.sources[path] == nil { self.arm(path) }
                self.readNow()
            }
        }
        t.resume()
        timer = t
        readNow()
    }

    public func stop() {
        for s in sources.values { s.cancel() }
        sources = [:]
        debounce?.cancel(); debounce = nil
        timer?.cancel(); timer = nil
    }

    private func arm(_ path: String) {
        let fd = open(path, O_EVTONLY)
        guard fd >= 0 else { return }
        let s = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd, eventMask: [.write, .extend, .rename, .delete], queue: .main)
        s.setEventHandler { [weak self, weak s] in
            let ev = s?.data ?? []
            MainActor.assumeIsolated {
                guard let self else { return }
                if ev.contains(.rename) || ev.contains(.delete) {
                    self.sources[path]?.cancel()
                    self.sources[path] = nil
                    self.arm(path)
                }
                self.scheduleRead()
            }
        }
        s.setCancelHandler { close(fd) }
        s.resume()
        sources[path] = s
    }

    private func scheduleRead() {
        debounce?.cancel()
        let item = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.readNow() }
        }
        debounce = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: item)
    }

    public func readNow() {
        let enabled = Self.bundles.filter { model.settings.enabled.contains($0.0) }
        for (kind, _) in Self.bundles where !model.settings.enabled.contains(kind) { model.status[kind] = .disabled }
        guard !enabled.isEmpty else { return }
        let date = now()
        do {
            var records = try read(enabled.map(\.1))
            if !model.state.alertsBootstrapped {
                records = records.filter { AlertMapper.isFresh($0, now: date) }
            }
            let mapped = records.compactMap(AlertMapper.map)
            model.notifications.ingest(mapped)
            for n in mapped { seen.insert(n.kind) }
            if !model.state.alertsBootstrapped {
                model.state.alertsBootstrapped = true
                model.save()
            }
            for (kind, _) in enabled { model.status[kind] = seen.contains(kind) ? .ok(date) : .noAlertsYet }
        } catch {
            switch error {
            case .busy: break
            case .accessDenied: for (kind, _) in enabled { model.status[kind] = .needsFullDiskAccess }
            case .failed(let code): for (kind, _) in enabled { model.status[kind] = .error("Notification database error \(code)") }
            }
        }
    }
}
