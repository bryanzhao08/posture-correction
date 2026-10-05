import Foundation
import SwiftUI
import FormCore

@MainActor
final class AppState: ObservableObject {
    @Published private(set) var cache: AccountCache?
    @Published private(set) var sessions: [LocalSession] = []
    @Published private(set) var profiles: Profiles?
    @Published var error: String?
    @Published private(set) var isSyncing = false
    @Published private(set) var backendURL: String
    let api: APIClient
    private var store: SessionStore?
    private var generation = UUID()
    private var deletingAccount = false
    private var syncRequested = false
    private let defaults = UserDefaults.standard
    var user: User? { cache?.user }
    var spokenCues: Bool { cache?.spokenCues ?? false }
    var sharePose: Bool { cache?.sharePose ?? false }
    var pendingCount: Int { sessions.filter { $0.server == nil || ($0.recording != nil && !$0.poseUploaded) }.count }

    init() {
        #if DEBUG && targetEnvironment(simulator)
        // The end-to-end registration test uses an isolated backend and cannot reuse another server's login.
        if CommandLine.arguments.contains("-uiTesting") && CommandLine.arguments.contains("-resetTestAccount") {
            if CommandLine.arguments.contains("-resetTrainingChoices") {
                for sport in Sport.allCases {
                    UserDefaults.standard.removeObject(forKey: "training." + sport.rawValue)
                    UserDefaults.standard.removeObject(forKey: "trainingView." + sport.rawValue)
                }
            }
            try? KeychainStore.delete()
            UserDefaults.standard.removeObject(forKey: "cachedUser")
        }
        #endif
        let url = UserDefaults.standard.string(forKey: "backendURL") ?? "http://localhost:8000"
        backendURL = url
        api = APIClient(baseURL: URL(string: url) ?? URL(string: "http://localhost:8000")!, token: KeychainStore.load())
        do {
            guard let resource = Bundle.main.url(forResource: "sport_profiles", withExtension: "json") else {
                throw APIError(message: "The bundled sport profiles are missing. Reinstall the app.")
            }
            profiles = try Profiles.load(from: Data(contentsOf: resource))
        } catch { self.error = error.localizedDescription }
        if api.token != nil, let data = defaults.data(forKey: "cachedUser"),
           let cachedUser = try? JSONDecoder().decode(User.self, from: data) {
            do { try openAccount(cachedUser) } catch { self.error = error.localizedDescription }
        }
        api.onAuthenticatedSuccess = { [weak self] in
            guard let self = self, self.user != nil, !self.isSyncing, !self.deletingAccount,
                  self.pendingCount > 0 || self.cache?.pendingPatch != nil else { return }
            Task { await self.syncPending() }
        }
    }
    private func openAccount(_ user: User) throws {
        let newStore = try SessionStore(userID: user.id, backend: backendURL)
        var newCache = try newStore.loadCache() ?? AccountCache(user: user)
        if newCache.pendingPatch == nil { newCache.user = user }
        let local = try newStore.loadSessions()
        try newStore.saveCache(newCache)
        store = newStore
        cache = newCache
        sessions = local
        defaults.set(try JSONEncoder().encode(newCache.user), forKey: "cachedUser")
    }
    func authenticate(email: String, password: String, name: String?, register: Bool) async throws {
        let epoch = generation
        let result: AuthOut = try await api.post(register ? "/auth/register" : "/auth/login",
            body: AuthIn(email: email.trimmingCharacters(in: .whitespacesAndNewlines), password: password,
                         name: register ? name : nil), authenticated: false)
        guard epoch == generation else { throw CancellationError() }
        // Local storage must be ready before committing persistent login.
        try openAccount(result.user)
        do { try KeychainStore.save(result.accessToken) }
        catch { cache = nil; sessions = []; store = nil; defaults.removeObject(forKey: "cachedUser"); throw error }
        api.token = result.accessToken
        generation = UUID()
        error = nil
    }
    func launch() async {
        guard api.token != nil else { return }
        if user == nil {
            do {
                let epoch = generation
                let remote: User = try await api.get("/me")
                guard epoch == generation else { return }
                try openAccount(remote)
            } catch { self.error = error.localizedDescription; return }
        }
        await syncPending()
        let epoch = generation
        do {
            let remote: User = try await api.get("/me")
            guard epoch == generation else { return }
            if cache?.pendingPatch == nil { cache?.user = remote; try persistCache() }
        } catch { if epoch == generation { self.error = error.localizedDescription } }
        guard epoch == generation else { return }
        await refreshHome()
    }
    func refreshHome() async {
        guard user != nil else { return }
        let epoch = generation
        for sport in Sport.allCases {
            do {
                let stats: Stats = try await api.get("/stats/" + sport.rawValue)
                guard epoch == generation else { return }
                cache?.stats[sport.rawValue] = stats
                try persistCache()
            } catch { if epoch == generation { self.error = error.localizedDescription }; return }
        }
        if epoch == generation { error = nil }
    }
    func refreshHistory(_ sport: Sport) async {
        let epoch = generation
        do {
            let history: [SessionListItem] = try await api.get("/sessions", query: [
                URLQueryItem(name: "sport", value: sport.rawValue), URLQueryItem(name: "limit", value: "50")])
            guard epoch == generation else { return }
            cache?.history[sport.rawValue] = history
            try persistCache()
            let checkpoints: [Checkpoint] = try await api.get("/checkpoints", query: [URLQueryItem(name: "sport", value: sport.rawValue)])
            guard epoch == generation else { return }
            cache?.checkpoints[sport.rawValue] = checkpoints
            try persistCache()
            let stats: Stats = try await api.get("/stats/" + sport.rawValue)
            guard epoch == generation else { return }
            cache?.stats[sport.rawValue] = stats
            try persistCache()
            error = nil
            for item in history where cachedDetail(item.id) == nil {
                if Task.isCancelled { return }
                let detail: SessionOut = try await api.get("/sessions/\(item.id)")
                guard epoch == generation else { return }
                cache?.details[String(item.id)] = detail
                try persistCache()
            }
        } catch { if epoch == generation { self.error = error.localizedDescription } }
    }
    func cachedDetail(_ id: Int) -> SessionOut? {
        cache?.details[String(id)] ?? sessions.compactMap(\.server).first { $0.id == id }
    }
    func detail(_ id: Int) async throws -> SessionOut {
        let epoch = generation
        do {
            let detail: SessionOut = try await api.get("/sessions/\(id)")
            guard epoch == generation else { throw CancellationError() }
            cache?.details[String(id)] = detail
            try persistCache()
            return detail
        } catch {
            guard epoch == generation else { throw CancellationError() }
            if let saved = cache?.details[String(id)] { return saved }
            if let saved = sessions.compactMap(\.server).first(where: { $0.id == id }) { return saved }
            throw error
        }
    }
    @discardableResult
    func saveSession(_ payload: SessionIn, recording: Recording?) throws -> String {
        guard !deletingAccount else { throw APIError(message: "Your account is being deleted.") }
        if sessions.contains(where: { $0.id == payload.clientID }) { return payload.clientID }
        guard let store = store else { throw APIError(message: "Session storage is unavailable. Log in again.") }
        let local = LocalSession(payload: payload, server: nil, recording: sharePose ? recording : nil,
                                 poseUploaded: false, uploadError: nil)
        try store.save(local)
        sessions.insert(local, at: 0)
        Task { await self.syncPending() }
        return local.id
    }
    private func updateSession(_ session: LocalSession) throws {
        guard let store = store else { throw APIError(message: "Session storage is unavailable.") }
        try store.save(session)
        if let index = sessions.firstIndex(where: { $0.id == session.id }) { sessions[index] = session }
    }
    func syncPending() async {
        guard user != nil, !deletingAccount else { return }
        if isSyncing { syncRequested = true; return }
        isSyncing = true
        syncRequested = false
        let epoch = generation
        defer {
            if epoch == generation {
                isSyncing = false
                if syncRequested { syncRequested = false; Task { await self.syncPending() } }
            }
        }
        if let patch = cache?.pendingPatch {
            do {
                let remote: User = try await api.patch("/me", body: patch)
                guard epoch == generation else { return }
                // An edit made while PATCH was in flight remains queued.
                if cache?.pendingPatch == patch {
                    cache?.user = remote
                    cache?.pendingPatch = nil
                }
                try persistCache()
            } catch { if epoch == generation { self.error = error.localizedDescription } }
        }
        var changedSports = Set<String>()
        // Replay offline sessions oldest first so comparisons/checkpoints follow practice order.
        let queuedIDs = sessions.filter { $0.server == nil || ($0.recording != nil && !$0.poseUploaded) }
            .sorted { Display.date($0.payload.startedAt) < Display.date($1.payload.startedAt) }.map(\.id)
        for id in queuedIDs {
            guard epoch == generation, var local = sessions.first(where: { $0.id == id }) else { return }
            do {
                if local.server == nil {
                    let uploaded: SessionOut = try await api.post("/sessions", body: local.payload)
                    guard epoch == generation else { return }
                    // Preserve consent changes made during this request.
                    local = sessions.first(where: { $0.id == id }) ?? local
                    local.server = uploaded
                    local.uploadError = nil
                    try updateSession(local)
                    changedSports.insert(local.payload.sport)
                }
                if sharePose, let recording = local.recording, !local.poseUploaded, let server = local.server {
                    try await api.postEmpty("/sessions/\(server.id)/keypoints", body: recording)
                    guard epoch == generation else { return }
                    local = sessions.first(where: { $0.id == id }) ?? local
                    local.poseUploaded = true
                    local.recording = nil
                    local.uploadError = nil
                    try updateSession(local)
                }
            } catch {
                guard epoch == generation else { return }
                var failed = sessions.first(where: { $0.id == id }) ?? local
                failed.uploadError = error.localizedDescription
                do { try updateSession(failed) } catch { self.error = error.localizedDescription }
                // Stop this pass; retry on launch, manual retry, or a subsequent successful request.
                break
            }
        }
        for sport in changedSports {
            do {
                let stats: Stats = try await api.get("/stats/" + sport)
                guard epoch == generation else { return }
                cache?.stats[sport] = stats
                try persistCache()
            } catch { if epoch == generation { self.error = error.localizedDescription } }
        }
    }
    func saveSettings(handedness: Handedness, emailReports: Bool, spokenCues: Bool, sharePose: Bool) throws {
        guard var updated = cache else { return }
        updated.user.handedness = handedness
        updated.user.emailReports = emailReports
        updated.pendingPatch = UserPatch(name: nil, handedness: handedness, emailReports: emailReports)
        updated.spokenCues = spokenCues
        updated.sharePose = sharePose
        // Revoking consent also removes any raw frames still waiting locally.
        if !sharePose {
            for saved in sessions where saved.recording != nil {
                var local = saved
                local.recording = nil
                if local.server != nil { local.uploadError = nil }
                try updateSession(local)
            }
        }
        try store?.saveCache(updated)
        cache = updated
        defaults.set(try JSONEncoder().encode(updated.user), forKey: "cachedUser")
        Task { await self.syncPending() }
    }
    func setSpokenCues(_ enabled: Bool) throws {
        guard var updated = cache else { return }
        updated.spokenCues = enabled
        try store?.saveCache(updated)
        cache = updated
    }
    private func persistCache() throws {
        if let cache = cache {
            try store?.saveCache(cache)
            defaults.set(try JSONEncoder().encode(cache.user), forKey: "cachedUser")
        }
    }
    func logout() throws {
        try KeychainStore.delete()
        generation = UUID()
        api.token = nil
        defaults.removeObject(forKey: "cachedUser")
        cache = nil
        sessions = []
        store = nil
        isSyncing = false
        syncRequested = false
        error = nil
    }
    func deleteAccount() async throws {
        deletingAccount = true
        generation = UUID()
        isSyncing = false
        let epoch = generation
        defer { deletingAccount = false }
        try await api.delete("/me")
        guard epoch == generation else { return }
        // Stop retry tasks before purging the deleted account's local files.
        generation = UUID()
        let accountStore = store
        try logout()
        try accountStore?.deleteAccountData()
    }
    func changeBackend(_ text: String) throws {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: trimmed), let host = url.host, !host.isEmpty,
              ["http", "https"].contains(url.scheme?.lowercased() ?? ""), url.user == nil,
              url.password == nil, url.query == nil, url.fragment == nil else {
            throw APIError(message: "Enter a valid http or https backend URL, such as http://formcoach.local:8000.")
        }
        if trimmed != backendURL {
            try logout()
            backendURL = trimmed
            api.baseURL = url
            defaults.set(trimmed, forKey: "backendURL")
        }
    }
    func lastScore(_ sport: Sport) -> Double? {
        let local = sessions.first { $0.payload.sport == sport.rawValue }
        let remote = cache?.stats[sport.rawValue]?.trend.last
        if let local = local, remote == nil || Display.date(local.payload.startedAt) >= Display.date(remote!.startedAt) {
            return local.payload.summary.score
        }
        return remote?.score
    }
    func sessionCount(_ sport: Sport) -> Int {
        let allLocal = sessions.filter { $0.payload.sport == sport.rawValue }
        guard let stats = cache?.stats[sport.rawValue] else { return allLocal.count }
        return max(stats.sessions + allLocal.filter { $0.server == nil }.count, allLocal.count)
    }
}
