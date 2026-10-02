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
