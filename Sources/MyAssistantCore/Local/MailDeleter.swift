import Foundation

/// Identifies the mail behind an Outlook alert well enough to find it in Apple Mail.
public struct MailQuery: Equatable, Sendable {
    public let subject: String
    public let sender: String
    /// Seconds between the alert and now; Apple Mail's clock is used on the script side to avoid date parsing.
    public let secondsAgo: Int
    public let toleranceSeconds: Int
}

public enum MailDeleteResult: Equatable, Sendable {
    case deleted, notFound, ambiguous(Int), mailNotSetUp, notAuthorized, failed(String)

    init(scriptOutput raw: String) {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        switch s {
        case "deleted": self = .deleted
        case "notfound": self = .notFound
        case "noaccount": self = .mailNotSetUp
        default:
            if s.hasPrefix("ambiguous:"), let n = Int(s.dropFirst("ambiguous:".count)) { self = .ambiguous(n) }
            else { self = .failed(s) }
        }
    }

    public var message: String? {
        switch self {
        case .deleted: nil
        case .notFound: "Couldn't find this mail in Apple Mail."
        case .ambiguous(let n): "\(n) matching mails found, nothing deleted."
        case .mailNotSetUp: "Turn on Mail for your Exchange account in System Settings → Internet Accounts."
        case .notAuthorized: "Allow My Assistant to control Mail in System Settings → Privacy & Security → Automation."
        case .failed(let m): "Delete failed: \(m)"
        }
    }
}

public enum MailOpenResult: Equatable, Sendable {
    case found(String), notFound, notAuthorized, failed(String)

    init(scriptOutput raw: String) {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("msgid:") { self = .found(String(s.dropFirst("msgid:".count))) }
        else if s == "notfound" || s == "noaccount" { self = .notFound }
        else { self = .failed(s) }
    }

    /// Apple Mail's link to one message: message://<Message-ID>, angle brackets percent-encoded.
    public static func messageURL(for messageID: String) -> URL? {
        let bare = messageID.trimmingCharacters(in: CharacterSet(charactersIn: "<> "))
        return URL(string: "message://%3C\(bare)%3E")
    }
}

public protocol MailDeleting: Sendable {
    func moveToTrash(_ query: MailQuery) async -> MailDeleteResult
    /// Message-ID of the best matching inbox mail in Apple Mail (read-only).
    func messageID(for query: MailQuery) async -> MailOpenResult
}

public extension MailDeleting {
    func messageID(for query: MailQuery) async -> MailOpenResult { .notFound }
}

/// Deletes (moves to Deleted Items) the single inbox mail in Apple Mail matching subject, sender and time.
/// Arguments are passed via argv so subjects with quotes or backslashes can't break the script.
public struct AppleMailDeleter: MailDeleting {
    public init() {}

    static let script = """
    on run argv
        set subj to item 1 of argv
        set snd to item 2 of argv
        set ago to (item 3 of argv) as integer
        set tol to (item 4 of argv) as integer
        tell application "Mail"
            if (count of accounts) is 0 then return "noaccount"
            set t to (current date) - ago
            set lo to t - tol
            set hi to t + tol
            set candidates to (messages of inbox whose subject is subj and date received ≥ lo and date received ≤ hi)
            set hits to {}
            repeat with m in candidates
                if (sender of m) contains snd then set end of hits to (contents of m)
            end repeat
            if (count of hits) is 0 then return "notfound"
            if (count of hits) > 1 then return "ambiguous:" & (count of hits)
            delete (item 1 of hits)
            return "deleted"
        end tell
    end run
    """

    /// Read-only lookup: picks the matching mail received closest to the alert time.
    static let findScript = """
    on run argv
        set subj to item 1 of argv
        set snd to item 2 of argv
        set ago to (item 3 of argv) as integer
        set tol to (item 4 of argv) as integer
        tell application "Mail"
            if (count of accounts) is 0 then return "noaccount"
            set t to (current date) - ago
            set candidates to (messages of inbox whose subject is subj and date received ≥ (t - tol) and date received ≤ (t + tol))
            set best to missing value
            set bestDiff to 999999
            repeat with m in candidates
                if (sender of m) contains snd then
                    set d to (date received of m) - t
                    if d < 0 then set d to -d
                    if d < bestDiff then
                        set bestDiff to d
                        set best to (contents of m)
                    end if
                end if
            end repeat
            if best is missing value then return "notfound"
            return "msgid:" & (message id of best)
        end tell
    end run
    """

    public func messageID(for q: MailQuery) async -> MailOpenResult {
        let (status, out, err) = await Self.run(Self.findScript, q)
        if status != 0 {
            return err.contains("-1743") ? .notAuthorized : .failed(err.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return MailOpenResult(scriptOutput: out)
    }

    static func run(_ script: String, _ q: MailQuery) async -> (Int32, String, String) {
        await Task.detached {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            p.arguments = ["-e", script, q.subject, q.sender, String(q.secondsAgo), String(q.toleranceSeconds)]
            let out = Pipe(), err = Pipe()
            p.standardOutput = out; p.standardError = err
            do { try p.run() } catch { return (-1, "", error.localizedDescription) }
            p.waitUntilExit()
            return (p.terminationStatus,
                    String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "",
                    String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "")
        }.value
    }

    public func moveToTrash(_ q: MailQuery) async -> MailDeleteResult {
        await Task.detached {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            p.arguments = ["-e", Self.script, q.subject, q.sender, String(q.secondsAgo), String(q.toleranceSeconds)]
            let out = Pipe(), err = Pipe()
            p.standardOutput = out; p.standardError = err
            do { try p.run() } catch { return .failed(error.localizedDescription) }
            p.waitUntilExit()
            let stdout = String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            let stderr = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            if p.terminationStatus != 0 {
                // -1743: the user hasn't allowed Automation of Mail for this app.
                return stderr.contains("-1743") ? .notAuthorized : .failed(stderr.trimmingCharacters(in: .whitespacesAndNewlines))
            }
            return MailDeleteResult(scriptOutput: stdout)
        }.value
    }
}
