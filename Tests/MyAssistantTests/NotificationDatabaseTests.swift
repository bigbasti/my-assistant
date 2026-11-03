import Testing
import Foundation
import SQLite3
@testable import MyAssistantCore

@Suite struct NotificationDatabaseTests {
    static func plist(title: String?, body: String?, usda: Data?, cate: String? = nil) throws -> Data {
        var req: [String: Any] = [:]
        if let title { req["titl"] = title }
        if let body { req["body"] = body }
        if let usda { req["usda"] = usda }
        if let cate { req["cate"] = cate }
        return try PropertyListSerialization.data(fromPropertyList: ["req": req], format: .binary, options: 0)
    }

    static func usda() throws -> Data {
        try NSKeyedArchiver.archivedData(withRootObject: [
            "view": "{\"actionType\":\"view\",\"messageId\":\"1793626351355\"}",
            "chat": "19:abc_def@unq.gbl.spaces",
        ], requiringSecureCoding: false)
    }

    struct Row { var app: String; var uuid: UInt8; var delivered: Double; var data: Data }

    static func makeDB(_ rows: [Row]) throws -> String {
        let path = NSTemporaryDirectory() + "nd-\(UUID().uuidString).db"
        var db: OpaquePointer?
        sqlite3_open(path, &db)
        defer { sqlite3_close(db) }
        let schema = """
        CREATE TABLE app(app_id INTEGER PRIMARY KEY, identifier TEXT);
        CREATE TABLE record(rec_id INTEGER PRIMARY KEY, app_id INTEGER, uuid BLOB, data BLOB, request_date REAL, request_last_date REAL, delivered_date REAL, presented INTEGER, style INTEGER, snooze_fire_date REAL);
        """
        sqlite3_exec(db, schema, nil, nil, nil)
        var ids: [String: Int32] = [:]
        for r in rows {
            if ids[r.app] == nil {
                let id = Int32(ids.count + 1)
                ids[r.app] = id
                sqlite3_exec(db, "INSERT INTO app VALUES(\(id), '\(r.app)')", nil, nil, nil)
            }
            var st: OpaquePointer?
            sqlite3_prepare_v2(db, "INSERT INTO record(app_id, uuid, data, delivered_date) VALUES(?,?,?,?)", -1, &st, nil)
            sqlite3_bind_int(st, 1, ids[r.app]!)
            let u = [UInt8](repeating: r.uuid, count: 16)
            sqlite3_bind_blob(st, 2, u, 16, nil)
            let d = [UInt8](r.data)
            sqlite3_bind_blob(st, 3, d, Int32(d.count), nil)
            sqlite3_bind_double(st, 4, r.delivered)
            sqlite3_step(st)
            sqlite3_finalize(st)
        }
        return path
    }

    @Test func readsTeamsRecord() throws {
        let data = try Self.plist(title: "Doe, Jane", body: "ok. see you", usda: Self.usda(), cate: "msg")
        let path = try Self.makeDB([Row(app: "com.microsoft.teams2", uuid: 0xAB, delivered: 815319151, data: data)])
        let recs = try NotificationDatabase(path: path).read(bundleIDs: ["com.microsoft.teams2"])
        #expect(recs.count == 1)
        let r = recs[0]
        #expect(r.title == "Doe, Jane")
        #expect(r.body == "ok. see you")
        #expect(r.category == "msg")
        #expect(r.uuidHex == String(repeating: "ab", count: 16))
        #expect(r.bundleID == "com.microsoft.teams2")
        #expect(r.archivedStrings.contains("{\"actionType\":\"view\",\"messageId\":\"1793626351355\"}"))
        #expect(r.archivedStrings.contains("19:abc_def@unq.gbl.spaces"))
        #expect(r.delivered == Date(timeIntervalSinceReferenceDate: 815319151))
    }

    @Test func filtersByBundleID() throws {
        let data = try Self.plist(title: "a", body: "b", usda: nil)
        let path = try Self.makeDB([
            Row(app: "com.microsoft.teams2", uuid: 1, delivered: 10, data: data),
            Row(app: "com.apple.mail", uuid: 2, delivered: 11, data: data),
        ])
        let recs = try NotificationDatabase(path: path).read(bundleIDs: ["com.microsoft.teams2"])
        #expect(recs.map(\.bundleID) == ["com.microsoft.teams2"])
        #expect(recs[0].archivedStrings == [])
    }

    @Test func newestFirst() throws {
        let data = try Self.plist(title: "a", body: "b", usda: nil)
        let path = try Self.makeDB([
            Row(app: "com.microsoft.teams2", uuid: 1, delivered: 10, data: data),
            Row(app: "com.microsoft.outlook", uuid: 2, delivered: 30, data: data),
            Row(app: "com.microsoft.teams2", uuid: 3, delivered: 20, data: data),
        ])
        let recs = try NotificationDatabase(path: path).read(bundleIDs: ["com.microsoft.teams2", "com.microsoft.outlook"])
        #expect(recs.map(\.delivered.timeIntervalSinceReferenceDate) == [30, 20, 10])
    }

    @Test func corruptPlistSkipsRecordOnly() throws {
        let good = try Self.plist(title: "a", body: "b", usda: nil)
        let path = try Self.makeDB([
            Row(app: "com.microsoft.teams2", uuid: 1, delivered: 10, data: good),
            Row(app: "com.microsoft.teams2", uuid: 2, delivered: 20, data: Data("garbage".utf8)),
        ])
        let recs = try NotificationDatabase(path: path).read(bundleIDs: ["com.microsoft.teams2"])
        #expect(recs.count == 1)
    }

    @Test func missingFileIsAccessDenied() {
        let db = NotificationDatabase(path: "/nonexistent-dir-\(UUID().uuidString)/db")
        #expect(throws: NotificationDBError.accessDenied) {
            try db.read(bundleIDs: ["x"])
        }
    }
}
