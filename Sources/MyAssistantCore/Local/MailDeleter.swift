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

public protocol MailDeleting: Sendable {
    func moveToTrash(_ query: MailQuery) async -> MailDeleteResult
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
