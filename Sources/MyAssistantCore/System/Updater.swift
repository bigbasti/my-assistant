import AppKit
import CryptoKit
import Foundation
import Observation

/// Semantic-ish version: dot-separated integers, optional leading "v".
public struct AppVersion: Comparable, Equatable, Sendable, CustomStringConvertible {
    public let parts: [Int]

    public init?(_ string: String) {
        let s = string.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
        let parts = s.split(separator: ".").map { Int($0) }
        guard !parts.isEmpty, !parts.contains(nil) else { return nil }
        self.parts = parts.compactMap { $0 }
    }

    public var description: String { parts.map(String.init).joined(separator: ".") }

    public static func < (a: AppVersion, b: AppVersion) -> Bool {
        for i in 0..<max(a.parts.count, b.parts.count) {
            let x = i < a.parts.count ? a.parts[i] : 0, y = i < b.parts.count ? b.parts[i] : 0
            if x != y { return x < y }
        }
        return false
    }

    public static func == (a: AppVersion, b: AppVersion) -> Bool { !(a < b) && !(b < a) }
}

public enum UpdateError: Error, Equatable, LocalizedError {
    case badResponse(Int), noDownload, checksumMismatch, wrongBundle(String), installFailed(String)

    public var errorDescription: String? {
        switch self {
        case .badResponse(let c): "GitHub answered with status \(c)."
        case .noDownload: "The latest release has no app download."
        case .checksumMismatch: "The download is damaged (checksum mismatch). Nothing was installed."
        case .wrongBundle(let m): "The download doesn't contain the expected app: \(m)"
        case .installFailed(let m): "Installing failed: \(m)"
        }
    }
}

/// The parts of a GitHub release the updater needs.
public struct ReleaseInfo: Equatable, Sendable {
    public let version: AppVersion
    public let tag: String
    public let zipURL: URL
    public let zipSize: Int
    public let sha256: String?
    public let notes: String
    public let pageURL: URL?

    public func isNewer(than current: AppVersion) -> Bool { version > current }

    public static func parse(_ data: Data) throws -> ReleaseInfo {
        struct Asset: Decodable { let name: String; let browser_download_url: URL; let size: Int? }
        struct Release: Decodable { let tag_name: String; let body: String?; let html_url: URL?; let assets: [Asset] }
        let r = try JSONDecoder().decode(Release.self, from: data)
        guard let version = AppVersion(r.tag_name),
              let zip = r.assets.first(where: { $0.name.hasPrefix("My-Assistant-") && $0.name.hasSuffix(".zip") })
        else { throw UpdateError.noDownload }
        let body = r.body ?? ""
        // Release notes end with: SHA-256: `<64 hex chars>`
        let sha = body.range(of: #"SHA-256: `([0-9a-f]{64})`"#, options: .regularExpression)
            .map { String(body[$0].dropFirst("SHA-256: `".count).dropLast()) }
        return ReleaseInfo(version: version, tag: r.tag_name, zipURL: zip.browser_download_url,
                           zipSize: zip.size ?? 0, sha256: sha, notes: body, pageURL: r.html_url)
    }
}

/// Checks GitHub for a newer release, downloads, verifies and installs it.
@Observable @MainActor
public final class Updater {
    public enum State: Equatable {
        case idle, checking, upToDate(Date), available(ReleaseInfo), downloading(Double), installing, failed(String)
    }

    public static let repo = "bigbasti/my-assistant"
    public private(set) var state: State = .idle
    public let currentVersion: AppVersion

    @ObservationIgnored private let model: AppModel
    @ObservationIgnored private var timer: Timer?

    public init(model: AppModel) {
        self.model = model
        let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
        currentVersion = AppVersion(v) ?? AppVersion("0")!
    }

    // MARK: pure helpers

    public nonisolated static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    public nonisolated static func shellQuote(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    public nonisolated static func isAutoCheckDue(last: Date?, now: Date) -> Bool {
        guard let last else { return true }
        return now.timeIntervalSince(last) > 86_400
    }

    /// Waits for the running app to quit, swaps the bundle and relaunches it.
    public nonisolated static func installScript(pid: Int32, newApp: String, target: String) -> String {
        let new = shellQuote(newApp), old = shellQuote(target)
        return """
        #!/bin/sh
        while kill -0 \(pid) 2>/dev/null; do sleep 0.2; done
        rm -rf \(old) || exit 1
        mv \(new) \(old) || exit 1
        xattr -dr com.apple.quarantine \(old) 2>/dev/null
        open \(old)
        """
    }

    // MARK: checking

    /// Starts the once-a-day background check (if enabled in settings).
    public func startAutoCheck() {
        timer?.invalidate()
        let t = Timer(timeInterval: 3600, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.autoCheckIfDue() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
        DispatchQueue.main.asyncAfter(deadline: .now() + 30) { [weak self] in self?.autoCheckIfDue() }
    }

    private func autoCheckIfDue() {
        guard model.settings.autoCheckUpdates,
              Self.isAutoCheckDue(last: model.settings.lastUpdateCheck, now: Date()) else { return }
        Task { await check() }
    }

    public func check() async {
        if case .downloading = state { return }
        state = .checking
        do {
            var req = URLRequest(url: URL(string: "https://api.github.com/repos/\(Self.repo)/releases/latest")!)
            req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            req.setValue("MyAssistant/\(currentVersion)", forHTTPHeaderField: "User-Agent")
            let (data, response) = try await URLSession.shared.data(for: req)
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard code == 200 else { throw UpdateError.badResponse(code) }
            let release = try ReleaseInfo.parse(data)
            model.settings.lastUpdateCheck = Date()
            model.save()
            state = release.isNewer(than: currentVersion) ? .available(release) : .upToDate(Date())
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    // MARK: installing

    public func install(_ release: ReleaseInfo) async {
        do {
            let work = FileManager.default.temporaryDirectory.appendingPathComponent("MyAssistantUpdate-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
            let zip = work.appendingPathComponent("update.zip")
            try await download(release.zipURL, to: zip, expected: release.zipSize)

            state = .installing
            let data = try Data(contentsOf: zip)
            if let expected = release.sha256, Self.sha256(data) != expected { throw UpdateError.checksumMismatch }

            try await Self.run("/usr/bin/ditto", ["-x", "-k", zip.path, work.path])
            let newApp = work.appendingPathComponent("My Assistant.app")
            let info = Bundle(url: newApp)
            guard info?.bundleIdentifier == Bundle.main.bundleIdentifier else {
                throw UpdateError.wrongBundle("unexpected bundle identifier")
            }
            guard let v = (info?.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String).flatMap(AppVersion.init),
                  v == release.version else { throw UpdateError.wrongBundle("version doesn't match the release") }

            // Re-sign with the local developer certificate when available so macOS keeps the
            // granted permissions (they're tied to the signing identity, not the file).
            if let identity = await Self.localSigningIdentity() {
                try await Self.run("/usr/bin/codesign", ["--force", "--timestamp=none", "-s", identity, newApp.path])
            }
            try? await Self.run("/usr/bin/xattr", ["-dr", "com.apple.quarantine", newApp.path])

            let script = work.appendingPathComponent("install.sh")
            try Self.installScript(pid: ProcessInfo.processInfo.processIdentifier, newApp: newApp.path,
                                   target: Bundle.main.bundleURL.path).write(to: script, atomically: true, encoding: .utf8)
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/bin/sh")
            p.arguments = [script.path]
            try p.run()
            model.flush()
            NSApp.terminate(nil)
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    private func download(_ url: URL, to file: URL, expected: Int) async throws {
        state = .downloading(0)
        let (bytes, response) = try await URLSession.shared.bytes(from: url)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard code == 200 else { throw UpdateError.badResponse(code) }
        let total = max(expected, Int(response.expectedContentLength), 1)
        var data = Data(); data.reserveCapacity(total)
        var lastReport = 0
        for try await byte in bytes {
            data.append(byte)
            if data.count - lastReport > 65_536 {
                lastReport = data.count
                state = .downloading(min(1, Double(data.count) / Double(total)))
            }
        }
        try data.write(to: file)
        state = .downloading(1)
    }

    @discardableResult
    nonisolated static func run(_ tool: String, _ args: [String]) async throws -> String {
        try await Task.detached {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: tool)
            p.arguments = args
            let out = Pipe(), err = Pipe()
            p.standardOutput = out; p.standardError = err
            try p.run()
            p.waitUntilExit()
            let o = String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            guard p.terminationStatus == 0 else {
                let e = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                throw UpdateError.installFailed("\((tool as NSString).lastPathComponent): \(e.trimmingCharacters(in: .whitespacesAndNewlines))")
            }
            return o
        }.value
    }

    nonisolated static func localSigningIdentity() async -> String? {
        guard let out = try? await run("/usr/bin/security", ["find-identity", "-v", "-p", "codesigning"]) else { return nil }
        for line in out.split(separator: "\n") where line.contains("Apple Development") {
            let parts = line.split(separator: "\"")
            if parts.count >= 2 { return String(parts[1]) }
        }
        return nil
    }
}
