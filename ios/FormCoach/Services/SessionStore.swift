import Foundation
import CryptoKit

// Main-actor ownership prevents overlapping local writes. Each session is an atomic JSON file.
@MainActor
final class SessionStore {
    private let root: URL
    private let sessionsURL: URL
    init(userID: Int, backend: String) throws {
        let support = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                  appropriateFor: nil, create: true)
        let scope = SHA256.hash(data: Data(backend.utf8)).map { String(format: "%02x", $0) }.joined()
        root = support.appendingPathComponent("FormCoach/\(scope)/\(userID)", isDirectory: true)
        sessionsURL = root.appendingPathComponent("sessions", isDirectory: true)
        try FileManager.default.createDirectory(at: sessionsURL, withIntermediateDirectories: true)
        var protectedRoot = root
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try protectedRoot.setResourceValues(values)
    }
    func loadSessions() throws -> [LocalSession] {
        let files = try FileManager.default.contentsOfDirectory(at: sessionsURL, includingPropertiesForKeys: nil)
        return try files.filter { $0.pathExtension == "json" }.map {
            try JSONDecoder().decode(LocalSession.self, from: Data(contentsOf: $0))
        }.sorted { $0.payload.startedAt > $1.payload.startedAt }
    }
    func save(_ session: LocalSession) throws {
        guard UUID(uuidString: session.id) != nil else { throw APIError(message: "Invalid session identifier.") }
        try write(session, to: sessionsURL.appendingPathComponent(session.id).appendingPathExtension("json"))
    }
    func importReplays(_ clips:[CapturedReplay],sessionID:String) throws -> [LocalReplay] {
        guard UUID(uuidString:sessionID) != nil else { throw APIError(message:"Invalid session identifier.") }
        guard !clips.isEmpty else { return [] }
        let folder=sessionsURL.appendingPathComponent(sessionID,isDirectory:true)
        try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
        var result:[LocalReplay]=[]
        do {
            for clip in clips {
                let filename="rep-\(clip.index).mp4",target=folder.appendingPathComponent(filename)
                if FileManager.default.fileExists(atPath:target.path) { try FileManager.default.removeItem(at:target) }
                try FileManager.default.copyItem(at:clip.url,to:target)
                try FileManager.default.setAttributes([.protectionKey:FileProtectionType.completeUntilFirstUserAuthentication],ofItemAtPath:target.path)
                result.append(LocalReplay(index:clip.index,cue:clip.cue,shortLabel:clip.shortLabel,mirrored:clip.mirrored,filename:filename,thumbnail:clip.thumbnail))
            }
            return result
        } catch { try? FileManager.default.removeItem(at:folder); throw error }
    }
    func replayURL(sessionID:String,replay:LocalReplay) -> URL? {
        guard UUID(uuidString:sessionID) != nil,replay.filename == "rep-\(replay.index).mp4" else { return nil }
        let url=sessionsURL.appendingPathComponent(sessionID).appendingPathComponent(replay.filename)
        return FileManager.default.fileExists(atPath:url.path) ? url : nil
    }
    func deleteSession(_ id:String) throws {
        guard UUID(uuidString:id) != nil else { return }
        for url in [sessionsURL.appendingPathComponent(id),sessionsURL.appendingPathComponent(id).appendingPathExtension("json")] where FileManager.default.fileExists(atPath:url.path) { try FileManager.default.removeItem(at:url) }
    }
    func deleteReplays() throws {
        for var session in try loadSessions() {
            let folder=sessionsURL.appendingPathComponent(session.id)
            if FileManager.default.fileExists(atPath:folder.path) { try FileManager.default.removeItem(at:folder) }
            if session.replays != nil { session.replays=nil; try save(session) }
        }
        // Remove orphan clip folders left by an interrupted session save.
        for url in try FileManager.default.contentsOfDirectory(at:sessionsURL,includingPropertiesForKeys:nil) where UUID(uuidString:url.lastPathComponent) != nil { try FileManager.default.removeItem(at:url) }
    }
    func loadCache() throws -> AccountCache? {
        let url = root.appendingPathComponent("cache.json")
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try JSONDecoder().decode(AccountCache.self, from: Data(contentsOf: url))
    }
    func saveCache(_ cache: AccountCache) throws { try write(cache, to: root.appendingPathComponent("cache.json")) }
    func deleteAccountData() throws { try FileManager.default.removeItem(at: root) }
    private func write<T: Encodable>(_ value: T, to url: URL) throws {
        let data = try JSONEncoder().encode(value)
        try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
}
