import Foundation
import SQLite3

public enum NotificationDBError: Error, Equatable {
    case accessDenied, busy, failed(Int32)
}

public struct NotificationDatabase: Sendable {
    public static var defaultPath: String {
        NSHomeDirectory() + "/Library/Group Containers/group.com.apple.usernoted/db2/db"
    }

    let path: String

    public init(path: String = NotificationDatabase.defaultPath) {
        self.path = path
    }

    static func map(_ code: Int32) -> NotificationDBError {
        switch code & 0xFF {
        case SQLITE_BUSY, SQLITE_LOCKED: return .busy
        case SQLITE_CANTOPEN, SQLITE_AUTH, SQLITE_PERM: return .accessDenied
        default: return .failed(code)
        }
    }

    public func read(bundleIDs: [String]) throws(NotificationDBError) -> [AlertRecord] {
        guard !bundleIDs.isEmpty else { return [] }
        let dir = (path as NSString).deletingLastPathComponent
        do { _ = try FileManager.default.contentsOfDirectory(atPath: dir) } catch { throw .accessDenied }

        var comps = URLComponents()
        comps.scheme = "file"
        comps.path = path
        comps.queryItems = [URLQueryItem(name: "mode", value: "ro")]
        guard let uri = comps.string else { throw .failed(SQLITE_ERROR) }

        var db: OpaquePointer?
        let rc = sqlite3_open_v2(uri, &db, SQLITE_OPEN_READONLY | SQLITE_OPEN_URI, nil)
        defer { sqlite3_close(db) }
        guard rc == SQLITE_OK else { throw Self.map(rc) }
        sqlite3_busy_timeout(db, 0)

        let marks = bundleIDs.map { _ in "?" }.joined(separator: ",")
        let sql = """
        SELECT a.identifier, r.uuid, r.delivered_date, r.data FROM record r
        JOIN app a ON a.app_id = r.app_id
        WHERE a.identifier IN (\(marks)) ORDER BY r.delivered_date DESC
        """
        var st: OpaquePointer?
        let prc = sqlite3_prepare_v2(db, sql, -1, &st, nil)
        defer { sqlite3_finalize(st) }
        guard prc == SQLITE_OK else { throw Self.map(prc) }
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        for (i, id) in bundleIDs.enumerated() {
            sqlite3_bind_text(st, Int32(i + 1), id, -1, transient)
        }

        func blob(_ col: Int32) -> Data {
            guard let p = sqlite3_column_blob(st, col) else { return Data() }
            return Data(bytes: p, count: Int(sqlite3_column_bytes(st, col)))
        }

        var out: [AlertRecord] = []
        while true {
            let s = sqlite3_step(st)
            if s == SQLITE_DONE { break }
            guard s == SQLITE_ROW else { throw Self.map(s) }
            guard let idp = sqlite3_column_text(st, 0) else { continue }
            if let rec = AlertRecord.parse(
                uuid: blob(1), bundleID: String(cString: idp),
                deliveredRef: sqlite3_column_double(st, 2), data: blob(3)) {
                out.append(rec)
            }
        }
        return out.sorted { $0.delivered > $1.delivered }
    }
}
